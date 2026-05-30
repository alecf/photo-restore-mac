import AppKit
import ImageIO
import RestoreEngine

extension RGBImage {
    /// An `NSImage` for display, downsampled so its long edge is at most `maxDimension` — we
    /// never hand SwiftUI a full-resolution (e.g. 4×-upscaled) buffer.
    func nsImage(maxDimension: Int = 1400) -> NSImage? {
        guard let cg = makeCGImage() else { return nil }
        let longest = max(cg.width, cg.height)
        guard longest > maxDimension else {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        let scale = Double(maxDimension) / Double(longest)
        let w = Int(Double(cg.width) * scale), h = Int(Double(cg.height) * scale)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: w, height: h))
    }
}

/// Lazily produces and caches downsampled thumbnails and viewer-sized "before" images straight
/// from disk via ImageIO — never decoding the full-resolution bitmap into memory.
final class ThumbnailCache {
    private let thumbs = NSCache<NSURL, NSImage>()
    private let fulls = NSCache<NSURL, NSImage>()

    func thumb(_ url: URL, maxPixel: Int = 320) -> NSImage? {
        cached(url, in: thumbs, maxPixel: maxPixel)
    }
    func full(_ url: URL, maxPixel: Int = 1400) -> NSImage? {
        cached(url, in: fulls, maxPixel: maxPixel)
    }

    private func cached(_ url: URL, in cache: NSCache<NSURL, NSImage>, maxPixel: Int) -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let img = Self.downsample(url, maxPixel: maxPixel) else { return nil }
        cache.setObject(img, forKey: url as NSURL)
        return img
    }

    private static func downsample(_ url: URL, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // honor EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
