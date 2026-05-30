import Foundation

/// Builds the whole image at the target size — the super-resolution model when enlarging,
/// otherwise a plain resize. Mirrors the Python `_build_background`: run SR at its native
/// factor only when the target is larger than the source, then Lanczos to the exact target.
public enum Background {

    public static func build(
        _ image: RGBImage,
        targetW: Int,
        targetH: Int,
        upscaler: TileUpscaler
    ) throws -> RGBImage {
        if Resolution.needsEnlargement(origW: image.width, origH: image.height, targetW: targetW, targetH: targetH) {
            let enlarged = try TiledUpscaler.upscale(image, using: upscaler)
            if enlarged.width == targetW && enlarged.height == targetH { return enlarged }
            return Lanczos.resize(enlarged, toWidth: targetW, toHeight: targetH)
        }
        if image.width == targetW && image.height == targetH { return image }
        return Lanczos.resize(image, toWidth: targetW, toHeight: targetH)
    }
}
