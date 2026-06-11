import XCTest
import CoreGraphics
@testable import RestoreEngine

final class FaceAlignerTests: XCTestCase {

    func testSimilarityRecoversKnownTransform() {
        // Build dst by applying a known similarity (scale 2, rotate 30°, translate) to src;
        // the fitted transform must map src back onto dst essentially exactly.
        let src: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                              CGPoint(x: 0, y: 1), CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 1)]
        let s = 2.0, theta = Double.pi / 6
        let a = s * cos(theta), b = s * sin(theta)
        let known = Affine2x3(a: a, b: -b, tx: 5, c: b, d: a, ty: -3)
        let dst = src.map { known.apply($0) }

        let fit = FaceAligner.similarity(from: src, to: dst)
        for k in 0..<src.count {
            let p = fit.apply(src[k])
            XCTAssertEqual(Double(p.x), Double(dst[k].x), accuracy: 1e-6)
            XCTAssertEqual(Double(p.y), Double(dst[k].y), accuracy: 1e-6)
        }
    }

    func testInverseRoundTrip() {
        let m = Affine2x3(a: 1.3, b: -0.4, tx: 12, c: 0.4, d: 1.3, ty: -7)
        let inv = m.inverse!
        let p = CGPoint(x: 42, y: 17)
        let r = inv.apply(m.apply(p))
        XCTAssertEqual(Double(r.x), 42, accuracy: 1e-9)
        XCTAssertEqual(Double(r.y), 17, accuracy: 1e-9)
    }

    func testWarpIdentityPreservesPixels() {
        // Identity transform, output size == input size → bilinear sampling at integer coords
        // returns the source pixels unchanged.
        let n = 32
        var px = [UInt8](repeating: 0, count: n * n * 3)
        for y in 0..<n {
            for x in 0..<n {
                let i = (y * n + x) * 3
                px[i] = UInt8(x * 8 % 256); px[i + 1] = UInt8(y * 8 % 256); px[i + 2] = 100
            }
        }
        let img = RGBImage(width: n, height: n, pixels: px)
        let out = FaceAligner.warp(img, transform: .identity, size: n)
        XCTAssertEqual(out.pixels, img.pixels)
    }

    func testInverseOfSingularMatrixIsNil() {
        // det = a*d - b*c = 1*4 - 2*2 = 0
        let singular = Affine2x3(a: 1, b: 2, tx: 0, c: 2, d: 4, ty: 0)
        XCTAssertNil(singular.inverse)
    }

    func testWarpFillsBorderOutsideSource() {
        // Shift the source far out of view → the whole crop should be the border color.
        let img = RGBImage(width: 16, height: 16, fill: 200)
        let shifted = Affine2x3(a: 1, b: 0, tx: 10_000, c: 0, d: 1, ty: 10_000)
        let out = FaceAligner.warp(img, transform: shifted, size: 8)
        XCTAssertEqual(Int(out.pixels[0]), 135)
        XCTAssertEqual(Int(out.pixels[1]), 133)
        XCTAssertEqual(Int(out.pixels[2]), 132)
    }
}
