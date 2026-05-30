import CoreML
import Foundation

/// Owns the loaded Core ML models and runs the pipeline. Being an `actor` makes all inference
/// **serial** — which is correct, not a limitation: the Apple Neural Engine serializes work
/// internally, so parallel predictions only inflate peak memory. Models are loaded once and
/// stay resident for the engine's lifetime (mirrors the Python `lru_cache`).
public actor InferenceEngine: ImageRestoring {
    private let pipeline: RestorePipeline

    public init(pipeline: RestorePipeline) {
        self.pipeline = pipeline
    }

    /// Build from compiled `.mlmodelc` URLs (as produced by `ModelStore`).
    public static func make(esrganURL: URL, gfpganURL: URL, parseURL: URL) throws -> InferenceEngine {
        let upscaler = try CoreMLUpscaler(compiledModelURL: esrganURL)
        let restorer = try CoreMLFaceRestorer(compiledModelURL: gfpganURL)
        let parser = try CoreMLFaceParser(compiledModelURL: parseURL)
        return InferenceEngine(pipeline: RestorePipeline(upscaler: upscaler, restorer: restorer, parser: parser))
    }

    /// Run a dummy prediction per model so the first real image doesn't eat the one-time
    /// ANE/GPU warm-up stall mid-batch.
    public func warmUp() {
        let dummy = LoadedImage(image: RGBImage(width: 16, height: 16, fill: 128), isGrayscale: false, sourceUTType: nil)
        _ = try? pipeline.restore(dummy, config: RestoreConfig(doFace: false, doContrast: true))
    }

    public func restore(
        _ loaded: LoadedImage,
        config: RestoreConfig,
        onEvent: (@Sendable (RestorePipeline.Event) -> Void)?
    ) async throws -> RGBImage {
        try Task.checkCancellation()
        return try pipeline.restore(loaded, config: config, onEvent: onEvent.map { cb in { cb($0) } })
    }
}
