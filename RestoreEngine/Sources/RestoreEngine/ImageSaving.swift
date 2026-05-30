import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageSavingError: Error { case encodeFailed(URL) }

/// Writes an `RGBImage` to disk as PNG or JPEG (type inferred from the destination extension),
/// creating intermediate directories. EXIF carry-over is a later refinement.
public enum ImageSaving {
    public static func save(_ image: RGBImage, to url: URL, quality: Int = 95) throws {
        guard let cg = image.makeCGImage() else { throw ImageSavingError.encodeFailed(url) }
        let ext = url.pathExtension.lowercased()
        let isJPEG = (ext == "jpg" || ext == "jpeg")
        let type = (isJPEG ? UTType.jpeg : UTType.png).identifier as CFString

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw ImageSavingError.encodeFailed(url)
        }
        var options: [CFString: Any] = [:]
        if isJPEG { options[kCGImageDestinationLossyCompressionQuality] = Double(quality) / 100.0 }
        CGImageDestinationAddImage(dest, cg, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageSavingError.encodeFailed(url) }
    }
}
