import Foundation

/// Classical (no-ML) contrast/levels normalization — direct port of `contrast.py`.
///
/// The stretch is computed on luminance and applied as a single shared curve to all
/// channels, so colors aren't pulled apart and grayscale stays grayscale (it can't
/// colorize). Runs before the ML stages; on faded scans it's often the biggest win.
public enum Contrast {

    /// Auto-contrast an RGB image, preserving hue. `cutoff` is the percent of the
    /// lightest/darkest pixels clipped before stretching.
    public static func normalize(_ image: RGBImage, cutoff: Double = 0.5) -> RGBImage {
        let n = image.pixelCount
        guard n > 0 else { return image }

        var lum = [Float](repeating: 0, count: n)
        image.pixels.withUnsafeBufferPointer { p in
            var i = 0
            var j = 0
            while i < n {
                let r = Float(p[j]), g = Float(p[j + 1]), b = Float(p[j + 2])
                lum[i] = 0.299 * r + 0.587 * g + 0.114 * b
                i += 1
                j += 3
            }
        }

        let lo = percentile(lum, cutoff)
        let hi = percentile(lum, 100.0 - cutoff)
        if hi <= lo { return image }

        let scale = Float(255.0) / (hi - lo)
        var out = image.pixels
        for idx in 0..<out.count {
            // Match numpy: clip then astype(uint8) truncates toward zero.
            let v = (Float(out[idx]) - lo) * scale
            out[idx] = UInt8(max(0, min(255, v)))
        }
        return RGBImage(width: image.width, height: image.height, pixels: out)
    }

    /// numpy `percentile` with the default `linear` interpolation between ranks.
    static func percentile(_ values: [Float], _ q: Double) -> Float {
        let sorted = values.sorted()
        let n = sorted.count
        if n == 0 { return 0 }
        if n == 1 { return sorted[0] }
        let rank = (q / 100.0) * Double(n - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Swift.min(lo + 1, n - 1)
        let frac = Float(rank - Double(lo))
        return sorted[lo] + frac * (sorted[hi] - sorted[lo])
    }
}
