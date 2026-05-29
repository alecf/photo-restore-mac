import XCTest
@testable import RestoreEngine

final class ImageOpsTests: XCTestCase {

    func testCGImageRoundTrip() throws {
        // A small color image should survive RGBImage → CGImage → RGBImage intact.
        let w = 8, h = 8
        var px = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            px[i * 3] = UInt8(i * 3 % 256)
            px[i * 3 + 1] = UInt8(i * 5 % 256)
            px[i * 3 + 2] = UInt8(i * 7 % 256)
        }
        let img = RGBImage(width: w, height: h, pixels: px)
        let cg = try XCTUnwrap(img.makeCGImage())
        let back = RGBImage(cgImage: cg)
        XCTAssertEqual(back.width, w)
        XCTAssertEqual(back.height, h)
        // sRGB round-trip through a context is lossless for 8-bit here.
        XCTAssertEqual(back.pixels, img.pixels)
    }

    func testGrayscaleDetection() {
        let gray = RGBImage(width: 4, height: 4, fill: 90)
        XCTAssertTrue(ImageLoading.looksGrayscale(gray))

        var px = [UInt8](repeating: 100, count: 4 * 4 * 3)
        px[0] = 100; px[1] = 100; px[2] = 120  // one pixel with spread 20 > tolerance
        let colored = RGBImage(width: 4, height: 4, pixels: px)
        XCTAssertFalse(ImageLoading.looksGrayscale(colored))
    }

    func testCollapseToGrayEqualizesChannels() {
        var px = [UInt8](repeating: 0, count: 3 * 3)
        px[0] = 200; px[1] = 100; px[2] = 50   // pixel 0
        px[3] = 10;  px[4] = 20;  px[5] = 30   // pixel 1
        px[6] = 255; px[7] = 255; px[8] = 255  // pixel 2
        let out = ImageLoading.collapseToGray(RGBImage(width: 3, height: 1, pixels: px))
        for i in stride(from: 0, to: out.pixels.count, by: 3) {
            XCTAssertEqual(out.pixels[i], out.pixels[i + 1])
            XCTAssertEqual(out.pixels[i + 1], out.pixels[i + 2])
        }
        // PIL L for (200,100,50) = (200*299+100*587+50*114)/1000 = 124.2 → 124
        XCTAssertEqual(Int(out.pixels[0]), 124)
    }

    func testLanczosResizeDimensions() {
        let img = RGBImage(width: 64, height: 32, fill: 128)
        let out = Lanczos.resize(img, toWidth: 32, toHeight: 16)
        XCTAssertEqual(out.width, 32)
        XCTAssertEqual(out.height, 16)
        // A flat field stays flat through resampling.
        XCTAssertEqual(Int(out.pixels.min()!), 128, accuracy: 2)
        XCTAssertEqual(Int(out.pixels.max()!), 128, accuracy: 2)
    }

    func testMetricsIdentity() {
        let img = RGBImage(width: 16, height: 16, fill: 100)
        XCTAssertEqual(Metrics.psnr(img, img), .infinity)
        XCTAssertEqual(Metrics.ssim(img, img), 1.0, accuracy: 0.0001)
    }
}

private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertLessThanOrEqual(abs(a - b), accuracy, file: file, line: line)
}
