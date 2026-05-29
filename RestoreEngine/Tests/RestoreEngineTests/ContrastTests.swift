import XCTest
@testable import RestoreEngine

final class ContrastTests: XCTestCase {

    /// A grayscale gradient spanning a compressed range [64,192] should stretch to span
    /// nearly the full [0,255] range after normalization.
    func testStretchesCompressedRange() {
        let w = 256, h = 16
        var px = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let v = UInt8(64 + Int(Double(x) / Double(w - 1) * 128.0))
                let i = (y * w + x) * 3
                px[i] = v; px[i + 1] = v; px[i + 2] = v
            }
        }
        let out = Contrast.normalize(RGBImage(width: w, height: h, pixels: px))
        let minV = out.pixels.min()!
        let maxV = out.pixels.max()!
        XCTAssertEqual(Int(minV), 0, "darkest pixel should clip to 0")
        XCTAssertGreaterThanOrEqual(Int(maxV), 250, "brightest pixel should approach 255")
    }

    /// Normalization must preserve grayscale (all channels stay equal — it can't colorize).
    func testPreservesGrayscale() {
        let w = 64, h = 8
        var px = [UInt8](repeating: 0, count: w * h * 3)
        for x in 0..<(w * h) {
            let v = UInt8(40 + (x % 100))
            px[x * 3] = v; px[x * 3 + 1] = v; px[x * 3 + 2] = v
        }
        let out = Contrast.normalize(RGBImage(width: w, height: h, pixels: px))
        for i in stride(from: 0, to: out.pixels.count, by: 3) {
            XCTAssertEqual(out.pixels[i], out.pixels[i + 1])
            XCTAssertEqual(out.pixels[i + 1], out.pixels[i + 2])
        }
    }

    /// An already-flat image (hi <= lo) is returned unchanged.
    func testFlatImageUnchanged() {
        let img = RGBImage(width: 4, height: 4, fill: 128)
        let out = Contrast.normalize(img)
        XCTAssertEqual(out.pixels, img.pixels)
    }

    func testPercentileLinearInterpolation() {
        // values 0..10, 50th percentile (linear) = 5.0
        let vals: [Float] = (0...10).map { Float($0) }
        XCTAssertEqual(Contrast.percentile(vals, 50), 5.0, accuracy: 0.0001)
        XCTAssertEqual(Contrast.percentile(vals, 0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(Contrast.percentile(vals, 100), 10.0, accuracy: 0.0001)
    }
}
