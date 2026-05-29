import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image plus the provenance we need to save it faithfully — mirrors the Python
/// `LoadedImage`. Loading goes through ImageIO's `CGImageSource`, which natively decodes
/// JPEG/PNG/TIFF/HEIC and most camera RAW formats, so iPhone photos "just work" (the
/// thing the Python CLI couldn't do).
public struct LoadedImage: Sendable {
    public let image: RGBImage
    /// True if the source is really grayscale (a scanned B&W photo), so we can collapse
    /// the output back to gray and guarantee "never colorize."
    public let isGrayscale: Bool
    public let sourceUTType: String?
}

public enum ImageLoadingError: Error, CustomStringConvertible {
    case cannotDecode(URL)
    public var description: String {
        switch self {
        case .cannotDecode(let url): return "could not decode image: \(url.lastPathComponent)"
        }
    }
}

public enum ImageLoading {

    /// Max per-pixel channel spread (0–255) for an RGB image to still count as a B&W scan.
    static let grayTolerance = 6

    private static let ciContext = CIContext(options: nil)

    /// Whether ImageIO can decode this URL at all (covers HEIC, RAW, and the standard set).
    /// Cheap header probe — does not decode pixels.
    public static func canDecode(url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceGetCount(src) > 0 && CGImageSourceGetType(src) != nil
    }

    public static func load(url: URL) throws -> LoadedImage {
        guard
            let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: false] as CFDictionary)
        else {
            throw ImageLoadingError.cannotDecode(url)
        }

        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let oriented = applyOrientation(cg, orientation: orientation)

        let rgb = RGBImage(cgImage: oriented)
        let utType = CGImageSourceGetType(src) as String?
        return LoadedImage(image: rgb, isGrayscale: looksGrayscale(rgb), sourceUTType: utType)
    }

    /// Honor (then drop) EXIF orientation by baking it into the pixels, via Core Image's
    /// orientation transform — robust across all 8 EXIF orientation cases.
    static func applyOrientation(_ cg: CGImage, orientation: UInt32) -> CGImage {
        if orientation == 1 { return cg }
        let ci = CIImage(cgImage: cg).oriented(forExifOrientation: Int32(orientation))
        return ciContext.createCGImage(ci, from: ci.extent) ?? cg
    }

    /// True if an RGB image is visually grayscale (a B&W scan stored as RGB): every pixel's
    /// max−min channel spread is within tolerance.
    public static func looksGrayscale(_ image: RGBImage) -> Bool {
        var maxSpread = 0
        image.pixels.withUnsafeBufferPointer { p in
            let total = image.pixelCount
            var j = 0
            for _ in 0..<total {
                let r = Int(p[j]), g = Int(p[j + 1]), b = Int(p[j + 2])
                let hi = Swift.max(r, g, b)
                let lo = Swift.min(r, g, b)
                let spread = hi - lo
                if spread > maxSpread {
                    maxSpread = spread
                    if maxSpread > grayTolerance { break }
                }
                j += 3
            }
        }
        return maxSpread <= grayTolerance
    }

    /// Collapse to gray by setting all channels to ITU-R 601-2 luma (matches PIL `convert("L")`),
    /// guaranteeing no model-introduced tint survives. Output stays RGB-shaped for the pipeline.
    public static func collapseToGray(_ image: RGBImage) -> RGBImage {
        var out = image.pixels
        let total = image.pixelCount
        var j = 0
        for _ in 0..<total {
            let r = Int(out[j]), g = Int(out[j + 1]), b = Int(out[j + 2])
            // PIL L: (R*299 + G*587 + B*114) / 1000, truncated.
            let l = UInt8((r * 299 + g * 587 + b * 114) / 1000)
            out[j] = l; out[j + 1] = l; out[j + 2] = l
            j += 3
        }
        return RGBImage(width: image.width, height: image.height, pixels: out)
    }
}
