import CoreVideo
import CoreGraphics
import Foundation

/// Bridges `RGBImage` to/from `CVPixelBuffer` for Core ML image inputs/outputs. Core ML
/// image features are 32-bit BGRA pixel buffers; the model handles the BGRA→RGB mapping.
enum PixelBuffer {

    static func make(from image: RGBImage) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, image.width, image.height,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb
        )
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let dst = base.assumingMemoryBound(to: UInt8.self)

        image.pixels.withUnsafeBufferPointer { src in
            for y in 0..<image.height {
                var s = y * image.width * 3
                var d = y * bytesPerRow
                for _ in 0..<image.width {
                    // BGRA
                    dst[d] = src[s + 2]
                    dst[d + 1] = src[s + 1]
                    dst[d + 2] = src[s]
                    dst[d + 3] = 255
                    s += 3
                    d += 4
                }
            }
        }
        return buffer
    }

    static func toRGBImage(_ buffer: CVPixelBuffer) -> RGBImage? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let src = base.assumingMemoryBound(to: UInt8.self)

        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        // 32BGRA and 32ARGB are the formats Core ML image outputs use; handle both.
        let bgra = format == kCVPixelFormatType_32BGRA
        for y in 0..<height {
            var s = y * bytesPerRow
            var d = (y * width) * 3
            for _ in 0..<width {
                if bgra {
                    rgb[d] = src[s + 2]      // R
                    rgb[d + 1] = src[s + 1]  // G
                    rgb[d + 2] = src[s]      // B
                } else { // 32ARGB
                    rgb[d] = src[s + 1]
                    rgb[d + 1] = src[s + 2]
                    rgb[d + 2] = src[s + 3]
                }
                s += 4
                d += 3
            }
        }
        return RGBImage(width: width, height: height, pixels: rgb)
    }
}
