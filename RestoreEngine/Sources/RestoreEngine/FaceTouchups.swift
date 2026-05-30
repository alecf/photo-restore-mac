import Foundation

/// The three knobs that fight the "photoshopped face" look after the GAN regenerates a face —
/// direct ports of `faces.py`'s `_match_color`, `_blend`, `_match_grain`. All operate on the
/// aligned 512 crops (restored vs the original aligned crop).
enum FaceTouchups {

    /// Give the restored face the *color* (chroma) of the source crop while keeping its own
    /// luma/detail. Neutralizes the model's invented blue eyes / red lips so B&W stays gray and
    /// sepia stays sepia. YCrCb per cv2 (BT.601).
    static func matchColor(restored: RGBImage, reference: RGBImage) -> RGBImage {
        precondition(restored.width == reference.width && restored.height == reference.height)
        var out = restored.pixels
        reference.pixels.withUnsafeBufferPointer { ref in
            for i in stride(from: 0, to: out.count, by: 3) {
                let ry = luma(out[i], out[i + 1], out[i + 2])
                let rCr = ref[i]; let rCg = ref[i + 1]; let rCb = ref[i + 2]
                // chroma from reference
                let refY = luma(rCr, rCg, rCb)
                let cr = 0.713 * (Float(rCr) - refY) + 128
                let cb = 0.564 * (Float(rCb) - refY) + 128
                // recombine restored luma + reference chroma → RGB
                let r = ry + 1.403 * (cr - 128)
                let g = ry - 0.714 * (cr - 128) - 0.344 * (cb - 128)
                let b = ry + 1.773 * (cb - 128)
                out[i] = clampByte(r); out[i + 1] = clampByte(g); out[i + 2] = clampByte(b)
            }
        }
        return RGBImage(width: restored.width, height: restored.height, pixels: out)
    }

    /// Mix the restored face over the original crop. alpha=1 fully restored, 0 original.
    static func blend(restored: RGBImage, original: RGBImage, alpha: Double) -> RGBImage {
        precondition(restored.width == original.width && restored.height == original.height)
        let a = Float(max(0, min(1, alpha)))
        var out = restored.pixels
        original.pixels.withUnsafeBufferPointer { orig in
            for i in 0..<out.count {
                let v = Float(out[i]) * a + Float(orig[i]) * (1 - a)
                out[i] = clampByte(v)
            }
        }
        return RGBImage(width: restored.width, height: restored.height, pixels: out)
    }

    /// Add film grain to `face` matched to the high-frequency noise of `reference`, applied
    /// equally to all channels (so a grayscale face stays gray). Seeded for reproducibility.
    static func matchGrain(face: RGBImage, reference: RGBImage, strength: Float = 0.5, seed: UInt64 = 0xCAFEF00D) -> RGBImage {
        let n = reference.pixelCount
        var refLuma = [Float](repeating: 0, count: n)
        reference.pixels.withUnsafeBufferPointer { p in
            var i = 0, j = 0
            while i < n { refLuma[i] = luma(p[j], p[j + 1], p[j + 2]); i += 1; j += 3 }
        }
        let blurred = Filters.gaussianBlur(refLuma, width: reference.width, height: reference.height, sigma: 1.0)
        var highFreq = [Float](repeating: 0, count: n)
        for i in 0..<n { highFreq[i] = refLuma[i] - blurred[i] }
        let std = standardDeviation(highFreq)
        let noiseStd = min(std, 20.0) * strength
        if noiseStd <= 0 { return face }

        var rng = SeededGaussian(seed: seed)
        var out = face.pixels
        var idx = 0
        for _ in 0..<n {
            let noise = rng.next(std: noiseStd)
            out[idx] = clampByte(Float(out[idx]) + noise)
            out[idx + 1] = clampByte(Float(out[idx + 1]) + noise)
            out[idx + 2] = clampByte(Float(out[idx + 2]) + noise)
            idx += 3
        }
        return RGBImage(width: face.width, height: face.height, pixels: out)
    }

    // MARK: - helpers

    private static func luma(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Float {
        0.299 * Float(r) + 0.587 * Float(g) + 0.114 * Float(b)
    }
    private static func clampByte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }

    private static func standardDeviation(_ v: [Float]) -> Float {
        guard !v.isEmpty else { return 0 }
        let mean = v.reduce(0, +) / Float(v.count)
        let varc = v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(v.count)
        return varc.squareRoot()
    }
}
