import Foundation
@testable import RestoreEngine

/// Image-similarity metrics for parity gates. PSNR is exact; SSIM here is computed over
/// 8×8 windows on luminance (mean SSIM), which is enough to gate stage parity against the
/// Python reference. Lives in the test target — not shipped.
enum Metrics {

    static func luminance(_ image: RGBImage) -> [Float] {
        var lum = [Float](repeating: 0, count: image.pixelCount)
        image.pixels.withUnsafeBufferPointer { p in
            var i = 0, j = 0
            while i < image.pixelCount {
                lum[i] = 0.299 * Float(p[j]) + 0.587 * Float(p[j + 1]) + 0.114 * Float(p[j + 2])
                i += 1; j += 3
            }
        }
        return lum
    }

    /// Peak signal-to-noise ratio in dB over all RGB channels. `.infinity` if identical.
    static func psnr(_ a: RGBImage, _ b: RGBImage) -> Double {
        precondition(a.width == b.width && a.height == b.height, "size mismatch")
        var sum = 0.0
        for i in 0..<a.pixels.count {
            let d = Double(a.pixels[i]) - Double(b.pixels[i])
            sum += d * d
        }
        let mse = sum / Double(a.pixels.count)
        if mse == 0 { return .infinity }
        return 10.0 * log10((255.0 * 255.0) / mse)
    }

    /// Mean SSIM over non-overlapping 8×8 luminance windows.
    static func ssim(_ a: RGBImage, _ b: RGBImage) -> Double {
        precondition(a.width == b.width && a.height == b.height, "size mismatch")
        let w = a.width, h = a.height
        let la = luminance(a), lb = luminance(b)
        let c1 = pow(0.01 * 255.0, 2.0), c2 = pow(0.03 * 255.0, 2.0)
        let win = 8
        var total = 0.0
        var windows = 0
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                let ww = min(win, w - x), wh = min(win, h - y)
                let n = Double(ww * wh)
                var ma = 0.0, mb = 0.0
                for yy in 0..<wh {
                    let row = (y + yy) * w + x
                    for xx in 0..<ww {
                        ma += Double(la[row + xx]); mb += Double(lb[row + xx])
                    }
                }
                ma /= n; mb /= n
                var va = 0.0, vb = 0.0, cov = 0.0
                for yy in 0..<wh {
                    let row = (y + yy) * w + x
                    for xx in 0..<ww {
                        let da = Double(la[row + xx]) - ma
                        let db = Double(lb[row + xx]) - mb
                        va += da * da; vb += db * db; cov += da * db
                    }
                }
                va /= n; vb /= n; cov /= n
                let s = ((2 * ma * mb + c1) * (2 * cov + c2)) / ((ma * ma + mb * mb + c1) * (va + vb + c2))
                total += s
                windows += 1
                x += win
            }
            y += win
        }
        return windows == 0 ? 1.0 : total / Double(windows)
    }
}
