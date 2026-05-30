import XCTest
@testable import RestoreEngine

final class FaceTouchupsTests: XCTestCase {

    func testMatchColorKeepsGrayscaleGray() {
        // A "restored" face with invented color, given a grayscale reference, must come back gray
        // (luma from restored, chroma from the gray reference → no chroma).
        var restoredPx = [UInt8](repeating: 0, count: 4 * 3)
        for i in 0..<4 { restoredPx[i * 3] = 200; restoredPx[i * 3 + 1] = 50; restoredPx[i * 3 + 2] = 80 }
        let restored = RGBImage(width: 4, height: 1, pixels: restoredPx)
        let grayRef = RGBImage(width: 4, height: 1, pixels: [UInt8](repeating: 120, count: 4 * 3))

        let out = FaceTouchups.matchColor(restored: restored, reference: grayRef)
        for i in stride(from: 0, to: out.pixels.count, by: 3) {
            XCTAssertEqual(Int(out.pixels[i]), Int(out.pixels[i + 1]), accuracy: 2)
            XCTAssertEqual(Int(out.pixels[i + 1]), Int(out.pixels[i + 2]), accuracy: 2)
        }
    }

    func testBlendEndpoints() {
        let a = RGBImage(width: 2, height: 1, pixels: [255, 255, 255, 0, 0, 0])
        let b = RGBImage(width: 2, height: 1, pixels: [0, 0, 0, 255, 255, 255])
        XCTAssertEqual(FaceTouchups.blend(restored: a, original: b, alpha: 1.0).pixels, a.pixels)
        XCTAssertEqual(FaceTouchups.blend(restored: a, original: b, alpha: 0.0).pixels, b.pixels)
        let mid = FaceTouchups.blend(restored: a, original: b, alpha: 0.5)
        XCTAssertEqual(Int(mid.pixels[0]), 128, accuracy: 1)
    }

    func testGrainIsDeterministicAndBounded() {
        let face = RGBImage(width: 32, height: 32, fill: 128)
        // textured reference so high-freq std > 0 → grain is applied
        var refPx = [UInt8](repeating: 0, count: 32 * 32 * 3)
        for i in 0..<(32 * 32) { let v = UInt8((i * 37) % 256); refPx[i*3]=v; refPx[i*3+1]=v; refPx[i*3+2]=v }
        let ref = RGBImage(width: 32, height: 32, pixels: refPx)

        let g1 = FaceTouchups.matchGrain(face: face, reference: ref, seed: 42)
        let g2 = FaceTouchups.matchGrain(face: face, reference: ref, seed: 42)
        XCTAssertEqual(g1.pixels, g2.pixels, "same seed → identical grain")
        // grain applied equally to all channels → output stays gray
        for i in stride(from: 0, to: g1.pixels.count, by: 3) {
            XCTAssertEqual(g1.pixels[i], g1.pixels[i + 1])
            XCTAssertEqual(g1.pixels[i + 1], g1.pixels[i + 2])
        }
        XCTAssertNotEqual(g1.pixels, face.pixels, "grain should change a flat face")
    }

    func testFeatheredMaskHighInsideLowOutside() {
        // A central face block → mask ~1 in the center, ~0 far outside, feathered between.
        let n = 64
        var cls = [Int32](repeating: 0, count: n * n)
        for y in 20..<44 { for x in 20..<44 { cls[y * n + x] = 1 } }  // class 1 = skin
        let mask = FaceMask.feathered(classMap: cls, width: n, height: n, featherSigma: 4)
        XCTAssertGreaterThan(mask[32 * n + 32], 0.9, "center should be solidly face")
        XCTAssertLessThan(mask[2 * n + 2], 0.05, "far corner should be background")
    }

    func testGaussianBlurPreservesMean() {
        let n = 16
        let src = (0..<(n * n)).map { Float(($0 * 7) % 100) }
        let blurred = Filters.gaussianBlur(src, width: n, height: n, sigma: 2)
        let m0 = src.reduce(0, +) / Float(src.count)
        let m1 = blurred.reduce(0, +) / Float(blurred.count)
        XCTAssertEqual(m0, m1, accuracy: 1.0, "blur should roughly preserve mean")
    }
}

private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(a - b), accuracy, file: file, line: line)
}
