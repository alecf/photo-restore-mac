import Foundation

/// Owns the work queue and drives the batch: one image in flight at a time (backpressure —
/// parallel inference only inflates memory), decode-on-demand, per-item error isolation (one
/// bad image never stops the batch), and a `Sendable` event stream the UI consumes. Settings
/// are snapshotted per item at enqueue time, so changing them mid-run only affects new items.
public actor BatchCoordinator {
    private let engine: any ImageRestoring
    private let quality: Int
    private var items: [BatchItem] = []
    private var running = false
    private var paused = false
    private var loopTask: Task<Void, Never>?

    private let continuation: AsyncStream<BatchEvent>.Continuation
    /// Consume this to drive the UI.
    public nonisolated let events: AsyncStream<BatchEvent>

    public init(engine: any ImageRestoring, quality: Int = 95) {
        self.engine = engine
        self.quality = quality
        (self.events, self.continuation) = AsyncStream.makeStream(of: BatchEvent.self)
    }

    public var allItems: [BatchItem] { items }

    /// Add inputs to the queue. Output paths + data-safety checks resolve here, so an item that
    /// can't be written (in-place overwrite) or already exists (no overwrite) is marked
    /// immediately rather than mid-run. Returns the created items.
    @discardableResult
    public func enqueue(_ inputs: [URL], config: RestoreConfig, output: OutputPolicy) -> [BatchItem] {
        var added: [BatchItem] = []
        for input in inputs {
            let out = output.outputURL(for: input)
            var item = BatchItem(input: input, output: out, config: config)
            if output.isInPlace(for: input) {
                item.status = .skipped("would overwrite the original in place")
                continuation.yield(.itemSkipped(id: item.id, reason: "in-place overwrite"))
            } else if output.shouldSkip(for: input) {
                item.status = .skipped("already restored")
                continuation.yield(.itemSkipped(id: item.id, reason: "already exists"))
            }
            items.append(item)
            added.append(item)
        }
        emitProgress()
        return added
    }

    public func removeQueued(id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].status == .queued else { return }
        items.remove(at: i)
        emitProgress()
    }

    /// Begin (or resume) processing. Idempotent while running.
    public func start() {
        guard !running else { return }
        running = true
        paused = false
        loopTask = Task { await self.runLoop() }
    }

    /// Finish the current image, then halt before the next (queue is preserved; `start()` resumes).
    public func pause() { paused = true }

    /// Stop now and clear the queue.
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
            items[idx].status = .processing
            let item = items[idx]
            let cont = continuation
            cont.yield(.itemStarted(id: item.id))

            do {
                try Task.checkCancellation()
                let loaded = try ImageLoading.load(url: item.input)
                let id = item.id
                let result = try await engine.restore(loaded, config: item.config) { event in
                    if case .preview(let stage, let image) = event {
                        cont.yield(.itemPreview(id: id, stage: stage, image: image))
                    }
                }
                try ImageSaving.save(result, to: item.output, quality: quality)
                setStatus(id: item.id, .done)
                cont.yield(.itemFinished(id: item.id, output: item.output))
            } catch is CancellationError {
                setStatus(id: item.id, .skipped("cancelled"))
                cont.yield(.itemSkipped(id: item.id, reason: "cancelled"))
                break
            } catch {
                setStatus(id: item.id, .failed("\(error)"))
                cont.yield(.itemFailed(id: item.id, reason: "\(error)"))
                // isolation: continue to the next item
            }
            emitProgress()
        }
        if !items.contains(where: { $0.status == .queued || $0.status == .processing }) {
            continuation.yield(.batchFinished)
        }
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
