import SwiftUI
import AppKit
import RestoreEngine

/// Display state for one queued image, mirrored from the engine's `BatchItem` for SwiftUI.
struct UIItem: Identifiable {
    let id: UUID
    let input: URL
    var status: BatchItemStatus
    var afterPreview: NSImage?   // latest stage preview / final result (downsampled)
}

/// The app's single source of truth. Owns the model store, inference engine, and batch
/// coordinator; consumes the engine's event stream on the main actor and projects it into
/// observable view state. Settings are plain values applied to new work.
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

    // Settings (mapped to RestoreConfig + OutputPolicy at enqueue)
    @Published var sizeChoice: SizeChoice = .keep
    @Published var customWidth = ""
    @Published var customHeight = ""
    @Published var faceEnabled = true
    @Published var restorationIntensity = 0.8     // → faceBlend
    @Published var matchColor = true
    @Published var matchGrain = true
    @Published var skipLargeFaces = true
    @Published var autoContrast = true
    @Published var outputFormat: OutputFormat = .keep
    @Published var jpegQuality = 95
    @Published var overwrite = false
    @Published var includeSubfolders = true
    @Published var outputDirectory: URL?

    private let store = ModelStore()
    private var engine: InferenceEngine?
    private var coordinator: BatchCoordinator?
    private var eventTask: Task<Void, Never>?
    private let thumbnails = ThumbnailCache()

    enum SizeChoice: String, CaseIterable, Identifiable {
        case keep = "Keep original", x2 = "2×", x3 = "3×", x4 = "4×", custom = "Custom…"
        var id: String { rawValue }
    }

    init() {
        Task { await refreshReadiness() }
    }

    func refreshReadiness() async {
        let ready = await store.isReady()
        modelsReady = ready
        if ready { await buildEngineIfNeeded() }
    }

    /// Side-load models from a user-picked folder (containing the .mlmodel files), then build
    /// the engine. Used until the hosted download is wired.
    func importModels(from directory: URL) async {
        isPreparing = true
        setupMessage = "Installing models…"
        defer { isPreparing = false }
        do {
            let ready = try await store.importLocalModels(from: directory)
            if Set(ready).isSuperset(of: ModelRegistry.all.map(\.name)) {
                setupMessage = nil
                await refreshReadiness()
            } else {
                setupMessage = "Folder is missing some model files (need RealESRGAN4x.mlmodel, GFPGAN.mlmodel, FaceParsing.mlmodel)."
            }
        } catch {
            setupMessage = "Couldn't install models: \(error)"
        }
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
            Task { await engine.warmUp() }
        } catch {
            setupMessage = "Couldn't load models: \(error)"
            modelsReady = false
        }
    }

    // MARK: - Ingest + run

    func add(urls: [URL]) {
        let images = expand(urls)
        guard !images.isEmpty, let coordinator else { return }
        let config = currentConfig()
        let policy = currentPolicy(for: images)
        Task {
            let added = await coordinator.enqueue(images, config: config, output: policy)
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
        Task { await coordinator.start() }
    }

    func pause() {
        guard let coordinator else { return }
        isRunning = false
        Task { await coordinator.pause() }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose Output Folder"
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }

    func beforeImage(for item: UIItem) -> NSImage? { thumbnails.full(item.input) }
    func thumbnail(for item: UIItem) -> NSImage? { thumbnails.thumb(item.input) }

    // MARK: - Event stream

    private func subscribe(to coordinator: BatchCoordinator) {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in coordinator.events {
                await self?.apply(event)
            }
        }
    }

    private func apply(_ event: BatchEvent) {
        switch event {
        case .itemStarted(let id):
            update(id) { $0.status = .processing }
            if selectedID == nil { selectedID = id }
        case .itemPreview(let id, _, let image):
            // Downsample previews for the UI; never hand SwiftUI a full-size buffer.
            let ns = image.nsImage(maxDimension: 1200)
            update(id) { $0.afterPreview = ns }
        case .itemFinished(let id, _):
            update(id) { $0.status = .done }
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

    // MARK: - Settings mapping

    private func currentConfig() -> RestoreConfig {
        RestoreConfig(
            target: sizeTarget(),
            strength: .conservative,
            doFace: faceEnabled,
            doContrast: autoContrast,
            faceBlend: restorationIntensity,
            faceRestoreThreshold: skipLargeFaces ? 500 : 0,
            faceGrain: matchGrain,
            matchFaceColor: matchColor,
            device: .auto
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
            if w == nil && h == nil { return .same }
            return .size(width: w, height: h)
        }
    }

    private func currentPolicy(for inputs: [URL]) -> OutputPolicy {
        let dir = outputDirectory ?? defaultOutputDirectory(for: inputs)
        // Folder mirroring when a single folder was the common root.
        return OutputPolicy(outputDirectory: dir, format: outputFormat, overwrite: overwrite, sourceRoot: nil)
    }

    private func defaultOutputDirectory(for inputs: [URL]) -> URL {
        let base = inputs.first?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Restored", isDirectory: true)
    }

    // MARK: - Folder expansion

    private func expand(_ urls: [URL]) -> [URL] {
        var found: [URL] = []
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let opts: FileManager.DirectoryEnumerationOptions = includeSubfolders ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
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
