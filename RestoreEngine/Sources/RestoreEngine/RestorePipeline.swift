import Foundation

/// Orchestrates the restoration stages for one image — the Swift analog of the Python
/// `restore_image`: contrast → build upscaled background → composite restored faces onto it.
/// Faces are restored at native resolution and pasted onto the already-upscaled background, so
/// they never pass through super-resolution. Grayscale inputs collapse to gray at the end (the
/// "never colorize" guarantee).
///
/// The model-backed stages are injected (upscaler/restorer/parser) so the pipeline is testable
/// and the app supplies them from the ModelStore.
public struct RestorePipeline {
    public let upscaler: TileUpscaler
    public let restorer: CoreMLFaceRestorer
    public let parser: CoreMLFaceParser

    public init(upscaler: TileUpscaler, restorer: CoreMLFaceRestorer, parser: CoreMLFaceParser) {
        self.upscaler = upscaler
        self.restorer = restorer
        self.parser = parser
    }

    /// A progress/preview event emitted as the stages complete. `preview` images are full-size
    /// intermediate results (the UI downsamples them); the engine stays UI-agnostic.
    public enum Event: Sendable {
        case stageStarted(Stage)
        case preview(Stage, RGBImage)
        case faceRestored(index: Int, total: Int)
        case finished(RGBImage)
    }
    public enum Stage: String, Sendable { case contrast, upscale, faces }

    public func restore(
        _ loaded: LoadedImage,
        config: RestoreConfig,
        onEvent: ((Event) -> Void)? = nil
    ) throws -> RGBImage {
        var array = loaded.image
        let (targetW, targetH) = try Resolution.resolveDimensions(config.target, origW: array.width, origH: array.height)

        if config.doContrast {
            onEvent?(.stageStarted(.contrast))
            array = Contrast.normalize(array)
            onEvent?(.preview(.contrast, array))
        }

        onEvent?(.stageStarted(.upscale))
        var background = try Background.build(array, targetW: targetW, targetH: targetH, upscaler: upscaler)
        onEvent?(.preview(.upscale, background))

        if config.doFace {
            onEvent?(.stageStarted(.faces))
            let faces = try FaceDetector.detect(in: array)
            let ratio = Double(targetW) / Double(array.width)
            let restorable = faces.filter { shouldRestore(sizePx: $0.sizePx, threshold: config.faceRestoreThreshold) }
            for (i, face) in restorable.enumerated() {
                let crop = FaceAligner.warp(array, transform: face.alignTransform, size: 512)
                var restored = try restorer.restore(crop)
                if config.matchFaceColor { restored = FaceTouchups.matchColor(restored: restored, reference: crop) }
                restored = FaceTouchups.blend(restored: restored, original: crop, alpha: config.faceBlend)
                if config.faceGrain { restored = FaceTouchups.matchGrain(face: restored, reference: crop) }

                let classMap = try parser.parse(crop)
                let mask = FaceMask.feathered(classMap: classMap, width: 512, height: 512)
                background = PasteBack.composite(
                    background: background, restored512: restored, mask512: mask,
                    align: face.alignTransform, scaleRatio: ratio
                )
                onEvent?(.faceRestored(index: i + 1, total: restorable.count))
                onEvent?(.preview(.faces, background))
            }
        }

        var result = background
        if loaded.isGrayscale { result = ImageLoading.collapseToGray(result) }
        if result.width != targetW || result.height != targetH {
            result = Lanczos.resize(result, toWidth: targetW, toHeight: targetH)
        }
        onEvent?(.finished(result))
        return result
    }

    /// Whether a face this many source-pixels wide/tall should be regenerated (mirrors
    /// `_should_restore`): `threshold <= 0` restores all; otherwise skip faces larger than it.
    func shouldRestore(sizePx: Int, threshold: Int) -> Bool {
        threshold <= 0 || sizePx <= threshold
    }
}
