import XCTest
@testable import RestoreEngine

final class PasteBackTests: XCTestCase {

    func testZeroMaskPreservesBackground() {
        let bg = RGBImage(width: 2, height: 2, fill: 100)
        let crop = RGBImage(width: 2, height: 2, fill: 200)
        let mask = [Float](repeating: 0, count: 4)

        let out = PasteBack.composite(
            background: bg, restored512: crop, mask512: mask,
            align: .identity, scaleRatio: 1, cropSize: 2)

        XCTAssertEqual(out.pixels, bg.pixels)
    }

    func testFullMaskIdentityCopiesCrop() {
        let bg = RGBImage(width: 2, height: 2, fill: 100)
        let crop = RGBImage(width: 2, height: 2, fill: 200)
        let mask = [Float](repeating: 1, count: 4)

        let out = PasteBack.composite(
            background: bg, restored512: crop, mask512: mask,
            align: .identity, scaleRatio: 1, cropSize: 2)

        XCTAssertEqual(out.pixels, crop.pixels)
    }

    func testPartialMaskBlendsBackgroundAndCrop() {
        let bg = RGBImage(width: 2, height: 2, fill: 100)
        let crop = RGBImage(width: 2, height: 2, fill: 200)
        let mask = [Float](repeating: 0.5, count: 4)

        let out = PasteBack.composite(
            background: bg, restored512: crop, mask512: mask,
            align: .identity, scaleRatio: 1, cropSize: 2)

        // 200*0.5 + 100*0.5 == 150 for every channel/pixel.
        XCTAssertEqual(out.pixels, [UInt8](repeating: 150, count: out.pixels.count))
    }

    func testSmallCropOnlyAffectsMappedRegion() {
        // A 4x4 background with a 2x2 crop pasted via the identity transform: only the
        // top-left 2x2 region (within crop bounds) is replaced; the rest of the background
        // is left untouched.
        let bg = RGBImage(width: 4, height: 4, fill: 100)
        let crop = RGBImage(width: 2, height: 2, fill: 200)
        let mask = [Float](repeating: 1, count: 4)

        let out = PasteBack.composite(
            background: bg, restored512: crop, mask512: mask,
            align: .identity, scaleRatio: 1, cropSize: 2)

        for y in 0..<4 {
            for x in 0..<4 {
                let d = (y * 4 + x) * 3
                let expected: UInt8 = (x < 2 && y < 2) ? 200 : 100
                XCTAssertEqual(out.pixels[d], expected, "pixel (\(x),\(y))")
                XCTAssertEqual(out.pixels[d + 1], expected, "pixel (\(x),\(y))")
                XCTAssertEqual(out.pixels[d + 2], expected, "pixel (\(x),\(y))")
            }
        }
    }

    func testZeroMaskRegionLeavesNeighboringMaskedRegionIntact() {
        // mask = 0 in the top-left corner, 1 elsewhere; identity transform, same sizes.
        let bg = RGBImage(width: 2, height: 2, fill: 50)
        let crop = RGBImage(width: 2, height: 2, fill: 250)
        let mask: [Float] = [0, 1, 1, 1]

        let out = PasteBack.composite(
            background: bg, restored512: crop, mask512: mask,
            align: .identity, scaleRatio: 1, cropSize: 2)

        XCTAssertEqual(out.pixels[0], 50)   // (0,0): mask 0 -> background
        XCTAssertEqual(out.pixels[3], 250)  // (1,0): mask 1 -> crop
        XCTAssertEqual(out.pixels[6], 250)  // (0,1): mask 1 -> crop
        XCTAssertEqual(out.pixels[9], 250)  // (1,1): mask 1 -> crop
    }
}
