import CoreML
import Foundation

/// A fixed-tile super-resolution model: takes an `inputSize × inputSize` RGB tile and
/// returns it enlarged by `scale`. Abstracted so the tiling/seam logic (TiledUpscaler) can
/// be tested with a deterministic fake, and the real Core ML model swapped in unchanged.
public protocol TileUpscaler: Sendable {
    var inputSize: Int { get }
    var scale: Int { get }
    func upscale(tile: RGBImage) throws -> RGBImage
}

public enum UpscalerError: Error, CustomStringConvertible {
    case pixelBufferCreationFailed
    case predictionFailed(String)
    case badOutput

    public var description: String {
        switch self {
        case .pixelBufferCreationFailed: return "could not create pixel buffer for model input"
        case .predictionFailed(let m): return "super-resolution prediction failed: \(m)"
        case .badOutput: return "super-resolution model returned no usable image"
        }
    }
}

/// Real-ESRGAN x4plus wrapper: fixed 512×512 → 2048×2048 (×4), Core ML.
public final class CoreMLUpscaler: TileUpscaler, @unchecked Sendable {
    public let inputSize: Int
    public let scale: Int
    private let model: MLModel
    private let inputName: String
    private let outputName: String

    public init(compiledModelURL: URL, inputSize: Int = 512, scale: Int = 4) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.model = try MLModel(contentsOf: compiledModelURL, configuration: config)
        self.inputSize = inputSize
        self.scale = scale
        // The adopted artifact names these "input" / "activation_out"; fall back to the
        // first declared feature if a future model build renames them.
        let desc = model.modelDescription
        self.inputName = desc.inputDescriptionsByName["input"]?.name
            ?? desc.inputDescriptionsByName.keys.first ?? "input"
        self.outputName = desc.outputDescriptionsByName["activation_out"]?.name
            ?? desc.outputDescriptionsByName.keys.first ?? "activation_out"
    }

    public func upscale(tile: RGBImage) throws -> RGBImage {
        guard let pb = PixelBuffer.make(from: tile) else {
            throw UpscalerError.pixelBufferCreationFailed
        }
        let provider: MLFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(
                dictionary: [inputName: MLFeatureValue(pixelBuffer: pb)]
            )
        } catch {
            throw UpscalerError.predictionFailed("\(error)")
        }
        let out: MLFeatureProvider
        do {
            out = try model.prediction(from: provider)
        } catch {
            throw UpscalerError.predictionFailed("\(error)")
        }
        guard
            let outPB = out.featureValue(for: outputName)?.imageBufferValue,
            let image = PixelBuffer.toRGBImage(outPB)
        else {
            throw UpscalerError.badOutput
        }
        return image
    }
}
