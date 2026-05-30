import XCTest
@testable import RestoreEngine

/// Deterministic nearest-neighbor upscaler — lets us test the tiling + seam-blend assembly
/// without the Core ML model. Because nearest produces identical values in overlapping
/// regions, a correct feathered assembly must reproduce a whole-image nearest upscale exactly.
private struct NearestUpscaler: TileUpscaler {
    let inputSize: Int
    let scale: Int
    func upscale(tile: RGBImage) throws -> RGBImage {
        let o = inputSize * scale
        var px = [UInt8](repeating: 0, count: o * o * 3)
        for j in 0..<o {
            for i in 0..<o {
                let s = ((j / scale) * inputSize + i / scale) * 3
                let d = (j * o + i) * 3
                px[d] = tile.pixels[s]; px[d + 1] = tile.pixels[s + 1]; px[d + 2] = tile.pixels[s + 2]
            }
        }
        return RGBImage(width: o, height: o, pixels: px)
    }
}

private func wholeNearest(_ image: RGBImage, scale: Int) -> RGBImage {
    let w = image.width * scale, h = image.height * scale
    var px = [UInt8](repeating: 0, count: w * h * 3)
    for j in 0..<h {
        for i in 0..<w {
            let s = ((j / scale) * image.width + i / scale) * 3
            let d = (j * w + i) * 3
            px[d] = image.pixels[s]; px[d + 1] = image.pixels[s + 1]; px[d + 2] = image.pixels[s + 2]
        }
    }
    return RGBImage(width: w, height: h, pixels: px)
}

private func randomImage(_ w: Int, _ h: Int, seed: UInt64) -> RGBImage {
    var state = seed
    func next() -> UInt8 { state = state &* 6364136223846793005 &+ 1442695040888963407; return UInt8((state >> 33) & 0xFF) }
    return RGBImage(width: w, height: h, pixels: (0..<(w * h * 3)).map { _ in next() })
}

final class TiledUpscalerTests: XCTestCase {

    func testOutputDimensions() throws {
        let img = RGBImage(width: 40, height: 24, fill: 100)
        let out = try TiledUpscaler.upscale(img, using: NearestUpscaler(inputSize: 16, scale: 4), overlap: 4)
        XCTAssertEqual(out.width, 160)
        XCTAssertEqual(out.height, 96)
    }

    func testFlatFieldStaysFlat() throws {
        let img = RGBImage(width: 40, height: 30, fill: 173)
        let out = try TiledUpscaler.upscale(img, using: NearestUpscaler(inputSize: 16, scale: 4), overlap: 4)
        XCTAssertTrue(out.pixels.allSatisfy { $0 == 173 }, "flat field must stay flat across seams")
    }

    /// The key correctness property: tiled assembly with feathered overlaps reproduces a
    /// whole-image nearest upscale exactly (no seam drift), across multiple tiles.
    func testTiledEqualsWholeForNearest() throws {
        let img = randomImage(37, 23, seed: 99)   // not a multiple of tile → forces clamped edge tiles
        let up = NearestUpscaler(inputSize: 8, scale: 4)
        let tiled = try TiledUpscaler.upscale(img, using: up, overlap: 2)
        let whole = wholeNearest(img, scale: 4)
        XCTAssertEqual(tiled.width, whole.width)
        XCTAssertEqual(tiled.height, whole.height)
        XCTAssertEqual(tiled.pixels, whole.pixels, "tiled assembly diverged from whole-image upscale")
    }

    func testSmallerThanTilePads() throws {
        // Image smaller than one tile must still upscale correctly (pad → upscale → crop).
        let img = randomImage(5, 3, seed: 7)
        let up = NearestUpscaler(inputSize: 8, scale: 4)
        let out = try TiledUpscaler.upscale(img, using: up, overlap: 2)
        XCTAssertEqual(out.width, 20)
        XCTAssertEqual(out.height, 12)
        XCTAssertEqual(out.pixels, wholeNearest(img, scale: 4).pixels)
    }

    func testTileOrigins() {
        XCTAssertEqual(TiledUpscaler.tileOrigins(extent: 8, tile: 8, step: 6), [0])
        XCTAssertEqual(TiledUpscaler.tileOrigins(extent: 20, tile: 8, step: 6), [0, 6, 12])
        XCTAssertEqual(TiledUpscaler.tileOrigins(extent: 12, tile: 8, step: 6), [0, 4])
    }

    func testBackgroundSkipsUpscaleWhenNotEnlarging() throws {
        // target <= source → SR skipped, plain Lanczos path (upscaler must not be called).
        let img = RGBImage(width: 64, height: 64, fill: 120)
        let out = try Background.build(img, targetW: 32, targetH: 32, upscaler: ThrowingUpscaler())
        XCTAssertEqual(out.width, 32)
        XCTAssertEqual(out.height, 32)
    }
}

/// Fails if `upscale` is ever called — proves the no-enlargement path never invokes the model.
private struct ThrowingUpscaler: TileUpscaler {
    let inputSize = 512
    let scale = 4
    func upscale(tile: RGBImage) throws -> RGBImage {
        XCTFail("upscaler must not run when target <= source")
        return tile
    }
}
