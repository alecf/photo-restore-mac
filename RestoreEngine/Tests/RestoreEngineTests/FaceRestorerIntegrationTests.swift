import XCTest
import CoreML
@testable import RestoreEngine

/// Guards the raw GFPGAN output, before any color match, blend, grain or paste-back can hide a
/// broken model. The original GFPGAN build overflows fp16 on the Neural Engine and returns a
/// near-uniform brown square, while the full-pipeline SSIM gate still passed. The shipped model
/// is rewritten to avoid that, and the production restorer runs it on the Neural Engine
/// (`.all`), so this checks the real configuration.
/// Guarded: needs GFPGAN-ANE.mlmodel in tools/models/cache (tools/models/rewrite_gfpgan_ane.py).
final class FaceRestorerIntegrationTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testRestoredFaceKeepsTheFace() async throws {
        let gfpgan = repoRoot().appendingPathComponent("tools/models/cache/\(ModelRegistry.gfpgan.fileName)")
        guard FileManager.default.fileExists(atPath: gfpgan.path) else {
            throw XCTSkip("\(ModelRegistry.gfpgan.fileName) not in tools/models/cache — run tools/models/rewrite_gfpgan_ane.py")
        }
        let restorer = try CoreMLFaceRestorer(compiledModelURL: try await MLModel.compileModel(at: gfpgan))

        let url = try XCTUnwrap(Bundle.module.url(forResource: "input_sample", withExtension: "jpg", subdirectory: "Fixtures"))
        let image = Contrast.normalize(try ImageLoading.load(url: url).image)
        let face = try XCTUnwrap(try FaceDetector.detect(in: image).first, "Vision found no face in the fixture")
        let crop = FaceAligner.warp(image, transform: face.alignTransform, size: 512)

        let restored = try restorer.restore(crop)
        let cropSD = stdDev(crop), restoredSD = stdDev(restored)
        let s = Metrics.ssim(restored, crop)
        print("face restorer: crop sd=\(f(cropSD)) restored sd=\(f(restoredSD)) SSIM vs crop=\(f(s))")

        // A real restoration keeps the face's tonal range; the broken output is a flat square.
        XCTAssertGreaterThan(restoredSD, cropSD * 0.6, "restored face lost its contrast: model output is near-flat")
        // ...and it is still recognisably the same face.
        XCTAssertGreaterThanOrEqual(s, 0.5, "restored face no longer resembles the input crop")
    }

    private func stdDev(_ img: RGBImage) -> Double {
        let n = Double(img.pixels.count)
        let mean = img.pixels.reduce(0.0) { $0 + Double($1) } / n
        return (img.pixels.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / n).squareRoot()
    }
    private func f(_ v: Double) -> String { String(format: "%.3f", v) }
}
