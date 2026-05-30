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

    public init(id: UUID = UUID(), input: URL, output: URL, status: BatchItemStatus = .queued) {
        self.id = id; self.input = input; self.output = output; self.status = status
    }
}

/// Events streamed as a batch runs. Preview images are full-size; the UI downsamples + throttles.
/// `itemFinished` reports the exact `RestoreConfig` the image was restored with, so the UI can
/// show which settings were active and decide whether a re-restore would change anything.
public enum BatchEvent: Sendable {
    case itemStarted(id: UUID)
    case itemPreview(id: UUID, stage: RestorePipeline.Stage, image: RGBImage)
    case itemFinished(id: UUID, output: URL, config: RestoreConfig)
    case itemFailed(id: UUID, reason: String)
    case itemSkipped(id: UUID, reason: String)
    case batchProgress(completed: Int, total: Int)
    case batchFinished
}
