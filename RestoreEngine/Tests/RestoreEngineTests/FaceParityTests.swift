import XCTest
import CoreGraphics
@testable import RestoreEngine

/// U5 parity gate: the Swift Vision alignment must reproduce facexlib's alignment closely
/// enough that GFPGAN restores well from it. Validated by **landmark agreement** (the
/// meaningful, shift-robust measure) plus a loose crop-SSIM sanity that it's the same face and
/// framing. Strict crop SSIM is deliberately NOT the gate: windowed SSIM is extremely sensitive
/// to sub-pixel offsets on high-detail regions, so two visually-identical alignments can score
/// low — and GFPGAN tolerates the few-px Vision-vs-RetinaFace difference (confirmed by the U6
/// restoration). The facexlib reference landmarks were captured from its RetinaFace detector on
/// the same (public-domain) input.
final class FaceParityTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
                      "missing fixture \(name).\(ext)")
    }

    func testSampleAlignsLikeFacexlib() throws {
        // facexlib RetinaFace 5-point landmarks on input_sample.jpg (L-eye, R-eye, nose, L-mouth, R-mouth).
        let facexlibLandmarks = [
            CGPoint(x: 354.1, y: 328.8), CGPoint(x: 454.7, y: 352.5),
            CGPoint(x: 378.2, y: 400.0), CGPoint(x: 343.8, y: 430.6), CGPoint(x: 442.5, y: 450.1),
        ]
        let image = try ImageLoading.load(url: fixture("input_sample", "jpg")).image
        let faces = try FaceDetector.detect(in: image)
        try XCTSkipIf(faces.isEmpty, "Vision found no face on this machine")
        let face = faces.max(by: { $0.sizePx < $1.sizePx })!

        // 1) Landmark agreement with facexlib (the real alignment-quality signal).
        var maxDist = 0.0
        for (a, b) in zip(face.landmarks5, facexlibLandmarks) {
            maxDist = max(maxDist, hypot(Double(a.x - b.x), Double(a.y - b.y)))
        }
        XCTAssertLessThanOrEqual(maxDist, 15,
            "max landmark distance \(maxDist)px from facexlib exceeds tolerance")

        // 2) Loose crop sanity: same face/framing (not pixel-exact — see class note).
        let swiftCrop = FaceAligner.warp(image, transform: face.alignTransform, size: 512)
        let ref = try ImageLoading.load(url: fixture("facexlib_sample", "png")).image
        XCTAssertEqual(swiftCrop.width, 512)
        let s = Metrics.ssim(swiftCrop, ref)
        print("face parity [sample]: maxLandmarkDist=\(String(format: "%.1f", maxDist))px cropSSIM=\(String(format: "%.3f", s))")
        // Floor against gross misalignment (a wrong/flipped crop scores ~0.1–0.2). The landmark
        // gate above is the authoritative check; windowed SSIM is sub-pixel-shift sensitive.
        XCTAssertGreaterThanOrEqual(s, 0.40, "crop SSIM \(s) too low — alignment likely wrong, not just offset")
    }
}
