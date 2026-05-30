import CoreGraphics
import Foundation

/// Aligns a detected face to the fixed 512×512 template GFPGAN/CodeFormer expect, the same
/// way facexlib does: fit a 4-DOF similarity transform (scale + rotation + translation) from
/// the 5 landmark points to the template, then warp the source into a 512 crop. Keeping the
/// transform lets the restored crop be pasted back via its inverse (U6).
public enum FaceAligner {

    /// facexlib's 5-point template at 512: left-eye, right-eye, nose, left-mouth, right-mouth.
    public static let template512: [CGPoint] = [
        CGPoint(x: 192.98138, y: 239.94708),
        CGPoint(x: 318.90277, y: 240.19360),
        CGPoint(x: 256.63416, y: 314.01935),
        CGPoint(x: 201.26117, y: 371.41043),
        CGPoint(x: 313.08905, y: 371.15118),
    ]

    /// Border fill for areas outside the source (matches facexlib's gray).
    static let borderRGB: (UInt8, UInt8, UInt8) = (135, 133, 132)

    /// Least-squares 4-DOF similarity transform mapping `src` → `dst` (the
    /// `cv2.estimateAffinePartial2D` model: no shear, no reflection).
    public static func similarity(from src: [CGPoint], to dst: [CGPoint]) -> Affine2x3 {
        precondition(src.count == dst.count && !src.isEmpty)
        // Unknowns θ = [a, b, tx, ty] with rows per point:
        //   [ sx, -sy, 1, 0 ]·θ = dx
        //   [ sy,  sx, 0, 1 ]·θ = dy
        // Solve the 4×4 normal equations AᵀA θ = Aᵀb.
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
        var atb = [Double](repeating: 0, count: 4)
        func accumulate(_ row: [Double], _ rhs: Double) {
            for i in 0..<4 {
                atb[i] += row[i] * rhs
                for j in 0..<4 { ata[i][j] += row[i] * row[j] }
            }
        }
        for k in 0..<src.count {
            let sx = Double(src[k].x), sy = Double(src[k].y)
            accumulate([sx, -sy, 1, 0], Double(dst[k].x))
            accumulate([sy, sx, 0, 1], Double(dst[k].y))
        }
        let theta = solve4x4(ata, atb)
        let a = theta[0], b = theta[1], tx = theta[2], ty = theta[3]
        // dst_x = a·sx − b·sy + tx ; dst_y = b·sx + a·sy + ty
        return Affine2x3(a: a, b: -b, tx: tx, c: b, d: a, ty: ty)
    }

    /// Warp `image` into a `size`×`size` crop using `transform` (source → template), bilinear,
    /// filling out-of-bounds samples with the border color.
    public static func warp(_ image: RGBImage, transform: Affine2x3, size: Int = 512) -> RGBImage {
        guard let inv = transform.inverse else {
            return RGBImage(width: size, height: size, fill: borderRGB.1)
        }
        var out = [UInt8](repeating: 0, count: size * size * 3)
        let w = image.width, h = image.height
        image.pixels.withUnsafeBufferPointer { src in
            for oy in 0..<size {
                for ox in 0..<size {
                    let s = inv.apply(CGPoint(x: Double(ox), y: Double(oy)))
                    let fx = Double(s.x), fy = Double(s.y)
                    let d = (oy * size + ox) * 3
                    if fx < 0 || fy < 0 || fx > Double(w - 1) || fy > Double(h - 1) {
                        out[d] = borderRGB.0; out[d + 1] = borderRGB.1; out[d + 2] = borderRGB.2
                        continue
                    }
                    let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
                    let x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1)
                    let dx = fx - Double(x0), dy = fy - Double(y0)
                    let w00 = (1 - dx) * (1 - dy), w10 = dx * (1 - dy)
                    let w01 = (1 - dx) * dy, w11 = dx * dy
                    let p00 = (y0 * w + x0) * 3, p10 = (y0 * w + x1) * 3
                    let p01 = (y1 * w + x0) * 3, p11 = (y1 * w + x1) * 3
                    for ch in 0..<3 {
                        let v = Double(src[p00 + ch]) * w00 + Double(src[p10 + ch]) * w10
                              + Double(src[p01 + ch]) * w01 + Double(src[p11 + ch]) * w11
                        out[d + ch] = UInt8(max(0, min(255, v.rounded())))
                    }
                }
            }
        }
        return RGBImage(width: size, height: size, pixels: out)
    }

    // MARK: - 4×4 linear solve (Gaussian elimination with partial pivoting)

    private static func solve4x4(_ A: [[Double]], _ b: [Double]) -> [Double] {
        var m = A.map { $0 }
        var v = b
        for col in 0..<4 {
            var pivot = col
            for r in (col + 1)..<4 where abs(m[r][col]) > abs(m[pivot][col]) { pivot = r }
            m.swapAt(col, pivot); v.swapAt(col, pivot)
            let diag = m[col][col]
            guard abs(diag) > 1e-15 else { continue }
            for r in 0..<4 where r != col {
                let f = m[r][col] / diag
                if f == 0 { continue }
                for c in col..<4 { m[r][c] -= f * m[col][c] }
                v[r] -= f * v[col]
            }
        }
        var x = [Double](repeating: 0, count: 4)
        for i in 0..<4 where abs(m[i][i]) > 1e-15 { x[i] = v[i] / m[i][i] }
        return x
    }
}
