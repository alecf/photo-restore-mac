import Foundation

/// Small separable image filters used by the face stages (grain extraction, mask feathering).
enum Filters {

    static func gaussianKernel(sigma: Double) -> [Float] {
        let radius = max(1, Int((sigma * 3).rounded()))
        let k = (-radius...radius).map { Float(exp(-Double($0 * $0) / (2 * sigma * sigma))) }
        let sum = k.reduce(0, +)
        return k.map { $0 / sum }
    }

    /// Separable Gaussian blur on a single-channel Float buffer, clamping at edges.
    static func gaussianBlur(_ src: [Float], width: Int, height: Int, sigma: Double) -> [Float] {
        let k = gaussianKernel(sigma: sigma)
        let r = k.count / 2
        var tmp = [Float](repeating: 0, count: src.count)
        var out = [Float](repeating: 0, count: src.count)

        // Horizontal
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var acc: Float = 0
                for t in -r...r {
                    let xx = min(max(x + t, 0), width - 1)
                    acc += src[row + xx] * k[t + r]
                }
                tmp[row + x] = acc
            }
        }
        // Vertical
        for y in 0..<height {
            for x in 0..<width {
                var acc: Float = 0
                for t in -r...r {
                    let yy = min(max(y + t, 0), height - 1)
                    acc += tmp[yy * width + x] * k[t + r]
                }
                out[y * width + x] = acc
            }
        }
        return out
    }
}

/// A tiny deterministic Gaussian noise generator (Box–Muller over a SplitMix64 stream). The
/// Python `_match_grain` is unseeded; we seed it so previews and outputs are reproducible.
struct SeededGaussian {
    private var state: UInt64
    private var spare: Float?
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    private mutating func nextUniform() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) * (1.0 / 9007199254740992.0)  // [0,1)
    }

    mutating func next(std: Float) -> Float {
        if let s = spare { spare = nil; return s * std }
        let u1 = max(nextUniform(), 1e-12), u2 = nextUniform()
        let mag = (-2.0 * log(u1)).squareRoot()
        let z0 = mag * cos(2 * .pi * u2)
        let z1 = mag * sin(2 * .pi * u2)
        spare = Float(z1)
        return Float(z0) * std
    }
}
