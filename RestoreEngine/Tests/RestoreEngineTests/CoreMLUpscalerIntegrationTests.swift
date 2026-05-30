import XCTest
import CoreML
import ImageIO
import UniformTypeIdentifiers
@testable import RestoreEngine

/// Exercises the real Core ML Real-ESRGAN model through the Swift inference path
/// (RGBImage → CVPixelBuffer → MLModel → CVPixelBuffer → RGBImage). Guarded: skipped unless
/// the U2-downloaded model is present locally (it's gitignored, ~67 MB). When `/tmp/pr-ref/`
/// from U2 exists, also dumps the Swift output there for an ad-hoc cross-runtime parity check.
final class CoreMLUpscalerIntegrationTests: XCTestCase {

    private func repoRoot() -> URL {
        // .../RestoreEngine/Tests/RestoreEngineTests/<thisFile> → up 4 = repo root.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func localModelURL() -> URL? {
        let url = repoRoot().appendingPathComponent("tools/models/cache/RealESRGAN4x.mlmodel")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func loadCrop512() throws -> RGBImage {
        // Prefer the U2 aligned-face crop for a directly-comparable result; else center-crop.
        let u2crop = URL(fileURLWithPath: "/tmp/pr-ref/crop512.png")
        if FileManager.default.fileExists(atPath: u2crop.path) {
            return try ImageLoading.load(url: u2crop).image
        }
        let input = try ImageLoading.load(url: XCTUnwrap(
            Bundle.module.url(forResource: "input_sample", withExtension: "jpg", subdirectory: "Fixtures"))).image
        let side = 512
        let x = max(0, (input.width - side) / 2), y = max(0, (input.height - side) / 2)
        let resized = (input.width < side || input.height < side)
            ? Lanczos.resize(input, toWidth: side, toHeight: side) : input
        return TiledUpscaler.crop(resized, x: min(x, resized.width - side), y: min(y, resized.height - side),
                                  width: side, height: side)
    }

    func testRealESRGANUpscalesA512Tile() async throws {
        guard let modelURL = localModelURL() else {
            throw XCTSkip("Real-ESRGAN model not present (tools/models/cache) — run tools/models/download.py")
        }
        let compiled = try await MLModel.compileModel(at: modelURL)
        let upscaler = try CoreMLUpscaler(compiledModelURL: compiled)

        let crop = try loadCrop512()
        XCTAssertEqual(crop.width, 512)
        let out = try upscaler.upscale(tile: crop)

        XCTAssertEqual(out.width, 2048)
        XCTAssertEqual(out.height, 2048)

        // Non-degenerate: real detail, not a flat fill.
        let mean = out.pixels.reduce(0) { $0 + Int($1) } / out.pixels.count
        XCTAssertGreaterThan(mean, 10)
        XCTAssertLessThan(mean, 245)
        XCTAssertGreaterThan(Set(out.pixels).count, 50, "output should have real tonal range")

        // The model must do more than a naive resize: it should differ meaningfully from a
        // plain Lanczos 4x of the same crop.
        let naive = Lanczos.resize(crop, toWidth: 2048, toHeight: 2048)
        var diff = 0.0
        for i in stride(from: 0, to: out.pixels.count, by: 997) {
            diff += abs(Double(out.pixels[i]) - Double(naive.pixels[i]))
        }
        diff /= Double(out.pixels.count / 997)
        XCTAssertGreaterThan(diff, 1.0, "SR output should differ from naive Lanczos")

        // Dump for ad-hoc cross-runtime parity vs the U2 PyTorch reference, when available.
        if FileManager.default.fileExists(atPath: "/tmp/pr-ref/crop512.png"),
           let cg = out.makeCGImage() {
            let dest = URL(fileURLWithPath: "/tmp/pr-ref/realesrgan_swift.png")
            if let dst = CGImageDestinationCreateWithURL(dest as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dst, cg, nil)
                CGImageDestinationFinalize(dst)
            }
        }
    }
}
