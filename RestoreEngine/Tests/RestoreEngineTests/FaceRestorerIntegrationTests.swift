import XCTest
import CoreML
@testable import RestoreEngine

/// Guards the raw GFPGAN output, before any color match, blend, grain or paste-back can
/// hide a broken model. On the Neural Engine this GFPGAN build returns a near-uniform
/// brown square instead of a face, so faces came out flat and gray in the app while the
/// full-pipeline SSIM gate still passed. Guarded: needs GFPGAN.mlmodel in tools/models/cache.
final class FaceRestorerIntegrationTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testRestoredFaceKeepsTheFace() async throws {
        let gfpgan = repoRoot().appendingPathComponent("tools/models/cache/GFPGAN.mlmodel")
        guard FileManager.default.fileExists(atPath: gfpgan.path) else {
            throw XCTSkip("GFPGAN.mlmodel not present in tools/models/cache — run tools/models/download.py")
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
