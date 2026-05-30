import Foundation

/// Owns the work queue and drives the batch: one image in flight at a time (backpressure —
/// parallel inference only inflates memory), decode-on-demand, per-item error isolation (one
/// bad image never stops the batch), and a `Sendable` event stream the UI consumes.
///
/// Settings are *live*: the coordinator holds the current `RestoreConfig` + `OutputPolicy`
/// (pushed via `updateSettings`) and reads them when each item starts — so changing settings
/// applies to whatever is restored next, and a re-restore picks up the current settings. Each
/// finished item reports the exact config it used.
public actor BatchCoordinator {
    private let engine: any ImageRestoring
    private let quality: Int
    private var items: [BatchItem] = []
    private var liveConfig = RestoreConfig()
    private var livePolicy: OutputPolicy?
    private var running = false
    private var paused = false
    private var loopTask: Task<Void, Never>?

    private let continuation: AsyncStream<BatchEvent>.Continuation
    public nonisolated let events: AsyncStream<BatchEvent>

    public init(engine: any ImageRestoring, quality: Int = 95) {
        self.engine = engine
        self.quality = quality
        (self.events, self.continuation) = AsyncStream.makeStream(of: BatchEvent.self)
    }

    public var allItems: [BatchItem] { items }

    /// Push the current settings. Read by each item when it starts (and used to resolve outputs).
    public func updateSettings(config: RestoreConfig, policy: OutputPolicy) {
        liveConfig = config
        livePolicy = policy
    }

    /// Add inputs to the queue, resolving output paths + data-safety status with current settings.
    @discardableResult
    public func enqueue(_ inputs: [URL]) -> [BatchItem] {
        guard let policy = livePolicy else { return [] }
        var added: [BatchItem] = []
        for input in inputs {
            var item = BatchItem(input: input, output: policy.outputURL(for: input))
            item.status = resolveStatus(for: input, policy: policy)
            items.append(item)
            added.append(item)
            if case .skipped(let r) = item.status { continuation.yield(.itemSkipped(id: item.id, reason: r)) }
        }
        emitProgress()
        return added
    }

    /// Re-queue an already-finished/failed/skipped item so it restores again with current settings.
    public func reRestore(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if items[i].status == .processing || items[i].status == .queued { return }
        items[i].status = .queued
        emitProgress()
    }

    /// Remove an item (anything except the one currently processing).
    public func remove(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].status != .processing else { return }
        items.remove(at: i)
        emitProgress()
    }

    /// Reorder the queue to match the given id order (affects processing order of queued items).
    public func reorder(_ orderedIDs: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var reordered = orderedIDs.compactMap { byID[$0] }
        // keep any items not mentioned (shouldn't happen) at the end
        for item in items where !orderedIDs.contains(item.id) { reordered.append(item) }
        items = reordered
    }

    public func start() {
        guard !running else { return }
        running = true
        paused = false
        loopTask = Task { await self.runLoop() }
    }

    public func pause() { paused = true }

    public func cancelAll() {
        paused = true
        loopTask?.cancel()
        items.removeAll { $0.status == .queued }
        emitProgress()
    }

    // MARK: - Run loop

    private func runLoop() async {
        defer { running = false }
        while !paused {
            guard let idx = items.firstIndex(where: { $0.status == .queued }) else { break }
            guard let policy = livePolicy else { break }
            let config = liveConfig
            let input = items[idx].input

            // Re-resolve output with current settings; re-check data-safety at run time.
            let status = resolveStatus(for: input, policy: policy)
            if case .skipped(let r) = status {
                items[idx].status = status
                continuation.yield(.itemSkipped(id: items[idx].id, reason: r))
                emitProgress()
                continue
            }
            let output = policy.outputURL(for: input)
            items[idx].output = output
            items[idx].status = .processing
            let id = items[idx].id
            let cont = continuation
            cont.yield(.itemStarted(id: id))

            do {
                try Task.checkCancellation()
                let loaded = try ImageLoading.load(url: input)
                let result = try await engine.restore(loaded, config: config) { event in
                    if case .preview(let stage, let image) = event {
                        cont.yield(.itemPreview(id: id, stage: stage, image: image))
                    }
                }
                try ImageSaving.save(result, to: output, quality: quality)
                setStatus(id: id, .done)
                cont.yield(.itemFinished(id: id, output: output, config: config))
            } catch is CancellationError {
                setStatus(id: id, .skipped("cancelled"))
                cont.yield(.itemSkipped(id: id, reason: "cancelled"))
                break
            } catch {
                setStatus(id: id, .failed("\(error)"))
                cont.yield(.itemFailed(id: id, reason: "\(error)"))
            }
            emitProgress()
        }
        if !items.contains(where: { $0.status == .queued || $0.status == .processing }) {
            continuation.yield(.batchFinished)
        }
    }

    private func resolveStatus(for input: URL, policy: OutputPolicy) -> BatchItemStatus {
        if policy.isInPlace(for: input) { return .skipped("would overwrite the original") }
        if policy.shouldSkip(for: input) { return .skipped("already restored") }
        return .queued
    }

    private func setStatus(id: UUID, _ status: BatchItemStatus) {
        if let i = items.firstIndex(where: { $0.id == id }) { items[i].status = status }
    }

    private func emitProgress() {
        let completed = items.filter {
            switch $0.status { case .done, .skipped, .failed: return true; default: return false }
        }.count
        continuation.yield(.batchProgress(completed: completed, total: items.count))
    }
}
