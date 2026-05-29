import CoreGraphics
import Foundation

/// An 8-bit RGB image as a tightly packed, interleaved byte buffer (`R,G,B,R,G,B,…`).
///
/// This mirrors the Python pipeline's `numpy` `H×W×3 uint8` representation so the
/// classical stages (contrast, color-match, grain) port one-to-one and stay easy to
/// reason about and test. Conversions to/from `CGImage` go through an `RGBA8` context
/// (alpha ignored) so we never depend on CoreGraphics supporting a 24-bit RGB context.
public struct RGBImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Interleaved RGB, `count == width * height * 3`.
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 3, "pixel buffer size mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: fill, count: width * height * 3)
    }

    public var pixelCount: Int { width * height }
}

// MARK: - CGImage interop

extension RGBImage {
    /// Build an `RGBImage` by rendering a `CGImage` into an sRGB `RGBA8` context and
    /// dropping the alpha channel. Orientation is the caller's responsibility.
    public init(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        rgba.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
            ctx?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        var src = 0
        var dst = 0
        let total = width * height
        for _ in 0..<total {
            rgb[dst] = rgba[src]
            rgb[dst + 1] = rgba[src + 1]
            rgb[dst + 2] = rgba[src + 2]
            src += 4
            dst += 3
        }
        self.init(width: width, height: height, pixels: rgb)
    }

    /// Produce a `CGImage` from the RGB buffer (alpha forced opaque).
    public func makeCGImage() -> CGImage? {
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 255, count: bytesPerRow * height)
        var src = 0
        var dst = 0
        let total = width * height
        for _ in 0..<total {
            rgba[dst] = pixels[src]
            rgba[dst + 1] = pixels[src + 1]
            rgba[dst + 2] = pixels[src + 2]
            // rgba[dst + 3] already 255
            src += 3
            dst += 4
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return rgba.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            return ctx.makeImage()
        }
    }
}
