import Foundation

/// Abstraction over "restore one image", so the batch coordinator can be tested without the
/// Core ML models. `InferenceEngine` is the real, model-backed implementation.
public protocol ImageRestoring: Sendable {
    func restore(
        _ loaded: LoadedImage,
        config: RestoreConfig,
        onEvent: (@Sendable (RestorePipeline.Event) -> Void)?
    ) async throws -> RGBImage
}

public enum BatchItemStatus: Sendable, Equatable {
    case queued
    case processing
    case done           // includes "restored, no faces found" — that's success
    case skipped(String)
    case failed(String)
}

public struct BatchItem: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let input: URL
    public var output: URL
    public var status: BatchItemStatus
    public let config: RestoreConfig

    public init(id: UUID = UUID(), input: URL, output: URL, status: BatchItemStatus = .queued, config: RestoreConfig) {
        self.id = id; self.input = input; self.output = output; self.status = status; self.config = config
    }
}

/// Events streamed as a batch runs. Preview images are full-size; the UI downsamples + throttles.
public enum BatchEvent: Sendable {
    case itemStarted(id: UUID)
    case itemPreview(id: UUID, stage: RestorePipeline.Stage, image: RGBImage)
    case itemFinished(id: UUID, output: URL)
    case itemFailed(id: UUID, reason: String)
    case itemSkipped(id: UUID, reason: String)
    case batchProgress(completed: Int, total: Int)
    case batchFinished
}
