import XCTest
import CoreML
import ImageIO
import UniformTypeIdentifiers
@testable import RestoreEngine

/// End-to-end U6 gate: the full Swift pipeline (contrast → upscale-skip-at-same-size → Vision
/// align → GFPGAN restore → color/blend/grain → parse-mask paste-back → grayscale collapse)
/// produces a faithful restoration. Guarded: needs all three models in tools/models/cache
/// (gitignored). Validated by quality, not strict pixel-parity vs the Python CLI — the adopted
/// GFPGAN is a different (equally valid) generative build (see tools/models/VALIDATION.md).
final class RestorePipelineIntegrationTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
    private func cache(_ file: String) -> URL? {
        let u = repoRoot().appendingPathComponent("tools/models/cache/\(file)")
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
    private func fixture(_ n: String, _ e: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: n, withExtension: e, subdirectory: "Fixtures"))
    }

    func testFullConservativePipelineOn77ish() async throws {
        guard let esrgan = cache("RealESRGAN4x.mlmodel"),
              let gfpgan = cache("GFPGAN.mlmodel"),
              let parse = cache("FaceParsing.mlmodel") else {
            throw XCTSkip("models not present in tools/models/cache — run tools/models/download.py")
        }
        let upscaler = try CoreMLUpscaler(compiledModelURL: try await MLModel.compileModel(at: esrgan))
        let restorer = try CoreMLFaceRestorer(compiledModelURL: try await MLModel.compileModel(at: gfpgan))
        let parser = try CoreMLFaceParser(compiledModelURL: try await MLModel.compileModel(at: parse))
        let pipeline = RestorePipeline(upscaler: upscaler, restorer: restorer, parser: parser)

        let loaded = try ImageLoading.load(url: fixture("input_77ish", "jpeg"))
        var stages: [RestorePipeline.Stage] = []
        let out = try pipeline.restore(loaded, config: RestoreConfig()) { event in
            if case .stageStarted(let s) = event { stages.append(s) }
        }

        // Same-size restoration → output matches source dimensions.
        XCTAssertEqual(out.width, loaded.image.width)
        XCTAssertEqual(out.height, loaded.image.height)
        XCTAssertTrue(stages.contains(.contrast) && stages.contains(.faces), "stages ran: \(stages)")

        // A restoration actually happened: the face region differs from the (contrast-only) input.
        let contrastOnly = Contrast.normalize(loaded.image)
        XCTAssertNotEqual(out.pixels, contrastOnly.pixels, "pipeline should change the image (face restored)")

        // Quality/regression guard vs the Python CLI's conservative output (different GFPGAN
        // build, so a loose gate — full-image SSIM is dominated by the matching background).
        let ref = try ImageLoading.load(url: fixture("output_77ish", "jpeg")).image
        if out.width == ref.width && out.height == ref.height {
            let s = Metrics.ssim(out, ref)
            print("pipeline parity [77ish, conservative]: full-image SSIM=\(String(format: "%.3f", s)) vs Python CLI")
            XCTAssertGreaterThanOrEqual(s, 0.80, "full-image restoration diverges too far from the CLI reference")
        }

        // Dump for visual confirmation.
        if let cg = out.makeCGImage() {
            let dest = URL(fileURLWithPath: "/tmp/pipeline_77ish_swift.png")
            if let dst = CGImageDestinationCreateWithURL(dest as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dst, cg, nil); CGImageDestinationFinalize(dst)
            }
        }
    }
}
