import XCTest
import CoreGraphics
@testable import RestoreEngine

/// U5 parity gate: the Swift Vision alignment must reproduce facexlib's alignment closely
/// enough that GFPGAN restores well from it. Validated by **landmark agreement** (the
/// meaningful, shift-robust measure) plus a loose crop-SSIM sanity that it's the same face
/// and framing. Strict crop SSIM is deliberately NOT the gate: windowed SSIM is extremely
/// sensitive to sub-pixel offsets on high-detail regions (hair), so two visually-identical
/// alignments can score 0.6 — and GFPGAN tolerates the few-px Vision-vs-RetinaFace difference
/// (confirmed by the U6 restoration). facexlib reference landmarks captured from its
/// RetinaFace detector on the same inputs.
final class FaceParityTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"),
                      "missing fixture \(name).\(ext)")
    }

    private func checkParity(
        input: String, inputExt: String, reference: String,
        facexlibLandmarks: [CGPoint], maxLandmarkDistance: Double
    ) throws {
        let image = try ImageLoading.load(url: fixture(input, inputExt)).image
        let faces = try FaceDetector.detect(in: image)
        try XCTSkipIf(faces.isEmpty, "\(input): Vision found no face on this machine")

        let face = faces.max(by: { $0.sizePx < $1.sizePx })!

        // 1) Landmark agreement with facexlib (the real alignment-quality signal).
        var maxDist = 0.0
        for (a, b) in zip(face.landmarks5, facexlibLandmarks) {
            let d = hypot(Double(a.x - b.x), Double(a.y - b.y))
            maxDist = max(maxDist, d)
        }
        XCTAssertLessThanOrEqual(maxDist, maxLandmarkDistance,
            "\(input): max landmark distance \(maxDist)px from facexlib exceeds \(maxLandmarkDistance)px")

        // 2) Loose crop sanity: same face/framing (not pixel-exact — see class note).
        let swiftCrop = FaceAligner.warp(image, transform: face.alignTransform, size: 512)
        let ref = try ImageLoading.load(url: fixture(reference, "png")).image
        XCTAssertEqual(swiftCrop.width, 512)
        let s = Metrics.ssim(swiftCrop, ref)
        print("face parity [\(input)]: maxLandmarkDist=\(String(format: "%.1f", maxDist))px  cropSSIM=\(String(format: "%.3f", s))")
        XCTAssertGreaterThanOrEqual(s, 0.55, "\(input): crop SSIM \(s) too low — alignment likely wrong, not just offset")
    }

    func test77ishAlignsLikeFacexlib() throws {
        try checkParity(input: "input_77ish", inputExt: "jpeg", reference: "facexlib_77ish",
            facexlibLandmarks: [CGPoint(x: 234.1, y: 329.1), CGPoint(x: 311.7, y: 338.3),
                                CGPoint(x: 274.8, y: 375.7), CGPoint(x: 227.7, y: 397.5),
                                CGPoint(x: 299.2, y: 405.7)],
            maxLandmarkDistance: 10)
    }

    func testScreenshotAlignsLikeFacexlib() throws {
        try checkParity(input: "input_screenshot", inputExt: "png", reference: "facexlib_screenshot",
            facexlibLandmarks: [CGPoint(x: 128.3, y: 111.3), CGPoint(x: 157.3, y: 111.5),
                                CGPoint(x: 146.3, y: 132.4), CGPoint(x: 127.1, y: 142.4),
                                CGPoint(x: 155.5, y: 142.8)],
            maxLandmarkDistance: 10)
    }

    func testGrifAlignsLikeFacexlib() throws {
        try checkParity(input: "input_grif", inputExt: "png", reference: "facexlib_grif",
            facexlibLandmarks: [CGPoint(x: 374.5, y: 310.1), CGPoint(x: 492.9, y: 329.4),
                                CGPoint(x: 453.4, y: 389.1), CGPoint(x: 371.7, y: 444.6),
                                CGPoint(x: 465.4, y: 459.5)],
            maxLandmarkDistance: 15)  // looser: Vision nose-centroid vs RetinaFace nose-tip
    }
}
