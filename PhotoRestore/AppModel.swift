import SwiftUI
import AppKit
import RestoreEngine

/// Display state for one queued image, mirrored from the engine's `BatchItem` for SwiftUI.
struct UIItem: Identifiable {
    let id: UUID
    let input: URL
    var status: BatchItemStatus
    var afterPreview: NSImage?         // latest stage preview / final result (downsampled)
    var appliedConfig: RestoreConfig?  // the settings this result was produced with (nil until done)
}

/// The app's single source of truth. Owns the model store, inference engine, and batch
/// coordinator; consumes the engine's event stream on the main actor and projects it into
/// observable view state. Settings are *live* — pushed to the coordinator on every change, so
/// they apply to whatever is restored next (including re-restores).
@MainActor
final class AppModel: ObservableObject {
    // Setup / readiness
    @Published var modelsReady = false
    @Published var setupMessage: String?
    @Published var isPreparing = false

    // Queue + selection
    @Published var items: [UIItem] = []
    @Published var selectedID: UUID?
    @Published var isRunning = false
    @Published var completed = 0
    @Published var total = 0

    // Settings (mapped to RestoreConfig + OutputPolicy). Changing any pushes to the coordinator.
    @Published var sizeChoice: SizeChoice = .keep { didSet { applyCurrentSettings() } }
    @Published var customWidth = "" { didSet { applyCurrentSettings() } }
    @Published var customHeight = "" { didSet { applyCurrentSettings() } }
    @Published var faceEnabled = true { didSet { applyCurrentSettings() } }
    @Published var restorationIntensity = 0.8 { didSet { applyCurrentSettings() } }
    @Published var matchColor = true { didSet { applyCurrentSettings() } }
    @Published var matchGrain = true { didSet { applyCurrentSettings() } }
    @Published var skipLargeFaces = true { didSet { applyCurrentSettings() } }
    @Published var autoContrast = true { didSet { applyCurrentSettings() } }
    @Published var outputFormat: OutputFormat = .keep { didSet { applyCurrentSettings() } }
    @Published var jpegQuality = 95
    @Published var overwrite = false { didSet { applyCurrentSettings() } }
    @Published var includeSubfolders = true
    @Published var outputDirectory: URL? { didSet { applyCurrentSettings() } }

    private let store = ModelStore()
    private var engine: InferenceEngine?
    private var coordinator: BatchCoordinator?
    private var eventTask: Task<Void, Never>?
    private let thumbnails = ThumbnailCache()

    enum SizeChoice: String, CaseIterable, Identifiable {
        case keep = "Keep original", x2 = "2×", x3 = "3×", x4 = "4×", custom = "Custom…"
        var id: String { rawValue }
    }

    init() { Task { await refreshReadiness() } }

    // MARK: - Readiness / setup

    func refreshReadiness() async {
        modelsReady = await store.isReady()
        if modelsReady { await buildEngineIfNeeded() }
    }

    func importModels(from directory: URL) async {
        isPreparing = true; setupMessage = "Installing models…"
        defer { isPreparing = false }
        do {
            let ready = try await store.importLocalModels(from: directory)
            if Set(ready).isSuperset(of: ModelRegistry.all.map(\.name)) {
                setupMessage = nil; await refreshReadiness()
            } else {
                setupMessage = "Folder is missing some model files (need RealESRGAN4x.mlmodel, GFPGAN.mlmodel, FaceParsing.mlmodel)."
            }
        } catch { setupMessage = "Couldn't install models: \(error)" }
    }

    private func buildEngineIfNeeded() async {
        guard engine == nil else { return }
        let urls = await store.compiledURLs()
        do {
            let engine = try InferenceEngine.make(esrganURL: urls.esrgan, gfpganURL: urls.gfpgan, parseURL: urls.parse)
            self.engine = engine
            let coordinator = BatchCoordinator(engine: engine, quality: jpegQuality)
            self.coordinator = coordinator
            subscribe(to: coordinator)
            applyCurrentSettings()
            Task { await engine.warmUp() }
        } catch {
            setupMessage = "Couldn't load models: \(error)"; modelsReady = false
        }
    }

    // MARK: - Settings

    func currentConfig() -> RestoreConfig {
        RestoreConfig(
            target: sizeTarget(), strength: .conservative,
            doFace: faceEnabled, doContrast: autoContrast,
            faceBlend: restorationIntensity,
            faceRestoreThreshold: skipLargeFaces ? 500 : 0,
            faceGrain: matchGrain, matchFaceColor: matchColor, device: .auto
        )
    }

    private func sizeTarget() -> Resolution.Target {
        switch sizeChoice {
        case .keep: return .same
        case .x2: return .scale(factor: 2)
        case .x3: return .scale(factor: 3)
        case .x4: return .scale(factor: 4)
        case .custom:
            let w = Int(customWidth), h = Int(customHeight)
            return (w == nil && h == nil) ? .same : .size(width: w, height: h)
        }
    }

    private func currentPolicy() -> OutputPolicy {
        OutputPolicy(outputDirectory: outputDirectory ?? defaultOutputDirectory(),
                     format: outputFormat, overwrite: overwrite)
    }

    private func defaultOutputDirectory() -> URL {
        let base = items.first?.input.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Restored", isDirectory: true)
    }

    /// Push current settings to the coordinator so they apply to whatever restores next.
    func applyCurrentSettings() {
        guard let coordinator else { return }
        let config = currentConfig(), policy = currentPolicy()
        Task { await coordinator.updateSettings(config: config, policy: policy) }
    }

    /// Settings that differ from defaults, for the active item / current settings.
    func divergences(for config: RestoreConfig?) -> [String] {
        (config ?? currentConfig()).divergences()
    }

    /// True if re-restoring would (likely) change the result — i.e. current settings differ
    /// from the ones that produced the item's current result.
    func canReRestore(_ item: UIItem) -> Bool {
        guard case .done = item.status, let used = item.appliedConfig else { return false }
        return used != currentConfig()
    }

    // MARK: - Queue actions

    func add(urls: [URL]) {
        let images = expand(urls)
        guard !images.isEmpty, let coordinator else { return }
        applyCurrentSettings()
        Task {
            let added = await coordinator.enqueue(images)
            await MainActor.run {
                for item in added where !self.items.contains(where: { $0.id == item.id }) {
                    self.items.append(UIItem(id: item.id, input: item.input, status: item.status))
                }
                if self.selectedID == nil { self.selectedID = self.items.first?.id }
            }
        }
    }

    func start() {
        guard let coordinator else { return }
        isRunning = true
        applyCurrentSettings()
        Task { await coordinator.start() }
    }

    func pause() {
        isRunning = false
        Task { await coordinator?.pause() }
    }

    func reRestore(_ item: UIItem) {
        guard let coordinator, canReRestore(item) else { return }
        if let i = items.firstIndex(where: { $0.id == item.id }) {
            items[i].status = .queued
            items[i].afterPreview = nil
        }
        isRunning = true
        applyCurrentSettings()
        Task { await coordinator.reRestore(id: item.id); await coordinator.start() }
    }

    func remove(_ item: UIItem) {
        items.removeAll { $0.id == item.id }
        if selectedID == item.id { selectedID = items.first?.id }
        Task { await coordinator?.remove(id: item.id) }
    }

    func move(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = items.firstIndex(where: { $0.id == id }) else { return }
        let moved = items.remove(at: from)
        let insertAt = items.firstIndex(where: { $0.id == targetID }) ?? items.count
        items.insert(moved, at: insertAt)
        let order = items.map(\.id)
        Task { await coordinator?.reorder(order) }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Choose Output Folder"
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }

    func beforeImage(for item: UIItem) -> NSImage? { thumbnails.full(item.input) }
    func thumbnail(for item: UIItem) -> NSImage? { thumbnails.thumb(item.input) }

    var selectedItem: UIItem? { items.first { $0.id == selectedID } ?? items.first }

    // MARK: - Event stream

    private func subscribe(to coordinator: BatchCoordinator) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in coordinator.events { await self?.apply(event) }
        }
    }

    private func apply(_ event: BatchEvent) {
        switch event {
        case .itemStarted(let id):
            update(id) { $0.status = .processing }
            if selectedID == nil { selectedID = id }
        case .itemPreview(let id, _, let image):
            let ns = image.nsImage(maxDimension: 1200)
            update(id) { $0.afterPreview = ns }
        case .itemFinished(let id, _, let config):
            update(id) { $0.status = .done; $0.appliedConfig = config }
        case .itemFailed(let id, let reason):
            update(id) { $0.status = .failed(reason) }
        case .itemSkipped(let id, let reason):
            update(id) { $0.status = .skipped(reason) }
        case .batchProgress(let c, let t):
            completed = c; total = t
        case .batchFinished:
            isRunning = false
        }
    }

    private func update(_ id: UUID, _ change: (inout UIItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    // MARK: - Folder expansion

    private func expand(_ urls: [URL]) -> [URL] {
        var found: [URL] = []
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let opts: FileManager.DirectoryEnumerationOptions = includeSubfolders
                    ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: opts) {
                    for case let f as URL in en where ImageLoading.canDecode(url: f) { found.append(f) }
                }
            } else if ImageLoading.canDecode(url: url) {
                found.append(url)
            }
        }
        let existing = Set(items.map(\.input.standardizedFileURL))
        return found.sorted { $0.path < $1.path }.filter { !existing.contains($0.standardizedFileURL) }
    }
}
