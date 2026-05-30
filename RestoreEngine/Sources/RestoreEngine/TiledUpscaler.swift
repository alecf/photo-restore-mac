import Foundation

/// Upscales an arbitrarily-sized image with a fixed-tile super-resolution model by splitting
/// it into overlapping tiles, upscaling each, and blending the overlaps with a feathered
/// (raised-edge) weight so seams are invisible. The Python pipeline ran the SR model once on
/// the whole image; tiling is the on-device adaptation for a fixed-input Core ML model, so
/// the seam blend is load-bearing and tested.
public enum TiledUpscaler {

    /// Enlarge `image` by `upscaler.scale` via overlapping `inputSize` tiles.
    /// `overlap` is in source pixels (default 64 → 1/8 of a 512 tile).
    public static func upscale(_ image: RGBImage, using upscaler: TileUpscaler, overlap: Int = 64) throws -> RGBImage {
        let tile = upscaler.inputSize
        let scale = upscaler.scale
        let safeOverlap = min(overlap, tile / 2)

        // The model needs exactly `tile`×`tile` input; pad (edge-replicate) so every axis is
        // at least one tile, then crop the scaled result back at the end.
        let padW = max(image.width, tile)
        let padH = max(image.height, tile)
        let padded = (padW == image.width && padH == image.height)
            ? image : padReplicate(image, toWidth: padW, toHeight: padH)

        let outW = padW * scale
        let outH = padH * scale
        let tileOut = tile * scale

        var acc = [Float](repeating: 0, count: outW * outH * 3)
        var wsum = [Float](repeating: 0, count: outW * outH)

        let strideStep = max(1, tile - safeOverlap)
        let xs = tileOrigins(extent: padW, tile: tile, step: strideStep)
        let ys = tileOrigins(extent: padH, tile: tile, step: strideStep)
        let feather = max(1, safeOverlap * scale)
        let ramp = featherRamp(length: tileOut, feather: feather)

        for oy in ys {
            for ox in xs {
                let sub = crop(padded, x: ox, y: oy, width: tile, height: tile)
                let up = try upscaler.upscale(tile: sub)
                precondition(up.width == tileOut && up.height == tileOut, "upscaler returned wrong size")

                let baseX = ox * scale
                let baseY = oy * scale
                up.pixels.withUnsafeBufferPointer { src in
                    for j in 0..<tileOut {
                        let wy = ramp[j]
                        let outRow = (baseY + j) * outW
                        var t = j * tileOut * 3
                        for i in 0..<tileOut {
                            let w = wy * ramp[i]
                            let idx = outRow + baseX + i
                            let p = idx * 3
                            acc[p]     += Float(src[t])     * w
                            acc[p + 1] += Float(src[t + 1]) * w
                            acc[p + 2] += Float(src[t + 2]) * w
                            wsum[idx]  += w
                            t += 3
                        }
                    }
                }
            }
        }

        var outPixels = [UInt8](repeating: 0, count: outW * outH * 3)
        for idx in 0..<(outW * outH) {
            let w = wsum[idx] > 0 ? wsum[idx] : 1
            let p = idx * 3
            outPixels[p]     = UInt8(max(0, min(255, (acc[p]     / w).rounded())))
            outPixels[p + 1] = UInt8(max(0, min(255, (acc[p + 1] / w).rounded())))
            outPixels[p + 2] = UInt8(max(0, min(255, (acc[p + 2] / w).rounded())))
        }
        let full = RGBImage(width: outW, height: outH, pixels: outPixels)

        let targetW = image.width * scale
        let targetH = image.height * scale
        return (targetW == outW && targetH == outH)
            ? full : crop(full, x: 0, y: 0, width: targetW, height: targetH)
    }

    // MARK: - Helpers

    /// Tile origins covering [0, extent) in `step` increments, with the final origin clamped
    /// so the last tile stays in-bounds (it overlaps its neighbor — the feather blends it).
    static func tileOrigins(extent: Int, tile: Int, step: Int) -> [Int] {
        if extent <= tile { return [0] }
        var origins: [Int] = []
        var o = 0
        while o + tile < extent {
            origins.append(o)
            o += step
        }
        origins.append(extent - tile)
        return origins
    }

    /// Separable feather: ~`eps` at the tile border rising linearly to 1 by `feather` pixels in,
    /// symmetric. Downweights tile edges so overlapping tiles cross-fade.
    static func featherRamp(length: Int, feather: Int) -> [Float] {
        let eps: Float = 0.02
        var r = [Float](repeating: 1, count: length)
        for i in 0..<length {
            let edge = min(i, length - 1 - i)
            let v = (Float(edge) + 0.5) / Float(feather)
            r[i] = max(eps, min(1, v))
        }
        return r
    }

    static func crop(_ image: RGBImage, x: Int, y: Int, width: Int, height: Int) -> RGBImage {
        var out = [UInt8](repeating: 0, count: width * height * 3)
        image.pixels.withUnsafeBufferPointer { src in
            for j in 0..<height {
                let srcRow = ((y + j) * image.width + x) * 3
                let dstRow = (j * width) * 3
                for k in 0..<(width * 3) {
                    out[dstRow + k] = src[srcRow + k]
                }
            }
        }
        return RGBImage(width: width, height: height, pixels: out)
    }

    static func padReplicate(_ image: RGBImage, toWidth: Int, toHeight: Int) -> RGBImage {
        var out = [UInt8](repeating: 0, count: toWidth * toHeight * 3)
        image.pixels.withUnsafeBufferPointer { src in
            for j in 0..<toHeight {
                let sy = min(j, image.height - 1)
                for i in 0..<toWidth {
                    let sx = min(i, image.width - 1)
                    let s = (sy * image.width + sx) * 3
                    let d = (j * toWidth + i) * 3
                    out[d] = src[s]; out[d + 1] = src[s + 1]; out[d + 2] = src[s + 2]
                }
            }
        }
        return RGBImage(width: toWidth, height: toHeight, pixels: out)
    }
}
