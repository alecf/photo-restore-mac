import CoreML
import Foundation

/// GFPGAN v1.4 face restorer: a 512×512 RGB aligned crop → a 512×512 restored crop (Core ML).
public final class CoreMLFaceRestorer: @unchecked Sendable {
    private let model: MLModel
    private let inputName: String
    private let outputName: String

    public init(compiledModelURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.model = try MLModel(contentsOf: compiledModelURL, configuration: config)
        let desc = model.modelDescription
        self.inputName = desc.inputDescriptionsByName["x_1"]?.name
            ?? desc.inputDescriptionsByName.keys.first ?? "x_1"
        self.outputName = desc.outputDescriptionsByName["activation_out"]?.name
            ?? desc.outputDescriptionsByName.keys.first ?? "activation_out"
    }

    public func restore(_ crop: RGBImage) throws -> RGBImage {
        guard let pb = PixelBuffer.make(from: crop) else { throw UpscalerError.pixelBufferCreationFailed }
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pb)])
        let out = try model.prediction(from: provider)
        guard let outPB = out.featureValue(for: outputName)?.imageBufferValue,
              let image = PixelBuffer.toRGBImage(outPB) else { throw UpscalerError.badOutput }
        return image
    }
}

/// BiSeNet face-parsing: a 512×512 RGB crop → a 512×512 class map (Int32 per pixel).
public final class CoreMLFaceParser: @unchecked Sendable {
    private let model: MLModel
    private let inputName: String
    private let outputName: String

    public init(compiledModelURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.model = try MLModel(contentsOf: compiledModelURL, configuration: config)
        let desc = model.modelDescription
        self.inputName = desc.inputDescriptionsByName["input"]?.name
            ?? desc.inputDescriptionsByName.keys.first ?? "input"
        self.outputName = desc.outputDescriptionsByName["argmax_out"]?.name
            ?? desc.outputDescriptionsByName.keys.first ?? "argmax_out"
    }

    public func parse(_ crop: RGBImage, size: Int = 512) throws -> [Int32] {
        guard let pb = PixelBuffer.make(from: crop) else { throw UpscalerError.pixelBufferCreationFailed }
        let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pb)])
        let out = try model.prediction(from: provider)
        guard let ma = out.featureValue(for: outputName)?.multiArrayValue else { throw UpscalerError.badOutput }

        let count = size * size
        var result = [Int32](repeating: 0, count: count)
        switch ma.dataType {
        case .int32:
            let ptr = ma.dataPointer.bindMemory(to: Int32.self, capacity: ma.count)
            for i in 0..<min(count, ma.count) { result[i] = ptr[i] }
        case .float32:
            let ptr = ma.dataPointer.bindMemory(to: Float.self, capacity: ma.count)
            for i in 0..<min(count, ma.count) { result[i] = Int32(ptr[i].rounded()) }
        default:
            for i in 0..<min(count, ma.count) { result[i] = ma[i].int32Value }
        }
        return result
    }
}
