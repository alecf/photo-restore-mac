import CoreGraphics
import Foundation

/// Composites a restored 512 face crop back onto the (already-upscaled, target-size)
/// background, using the feathered mask and the alignment transform's inverse — the analog of
/// facexlib's `paste_faces_to_input_image`. Faces were aligned at source resolution, so the
/// paste maps through the source→target scale ratio.
public enum PasteBack {

    public static func composite(
        background: RGBImage,
        restored512 crop: RGBImage,
        mask512 mask: [Float],
        align: Affine2x3,
        scaleRatio ratio: Double,
        cropSize: Int = 512
    ) -> RGBImage {
        precondition(mask.count == cropSize * cropSize)
        // Map a target pixel → crop coordinates: source = target / ratio, crop = align(source).
        let toCrop = Affine2x3(
            a: align.a / ratio, b: align.b / ratio, tx: align.tx,
            c: align.c / ratio, d: align.d / ratio, ty: align.ty
        )
        let bw = background.width, bh = background.height
        var out = background.pixels
        let maxC = Double(cropSize - 1)

        crop.pixels.withUnsafeBufferPointer { src in
            for ty in 0..<bh {
                for tx in 0..<bw {
                    let c = toCrop.apply(CGPoint(x: Double(tx), y: Double(ty)))
                    let cx = Double(c.x), cy = Double(c.y)
                    if cx < 0 || cy < 0 || cx > maxC || cy > maxC { continue }

                    let x0 = Int(cx.rounded(.down)), y0 = Int(cy.rounded(.down))
                    let x1 = min(x0 + 1, cropSize - 1), y1 = min(y0 + 1, cropSize - 1)
                    let dx = cx - Double(x0), dy = cy - Double(y0)
                    let w00 = (1 - dx) * (1 - dy), w10 = dx * (1 - dy)
                    let w01 = (1 - dx) * dy, w11 = dx * dy

                    let m = bilinear(mask, cropSize, x0, y0, x1, y1, w00, w10, w01, w11)
                    if m <= 0.001 { continue }

                    let d = (ty * bw + tx) * 3
                    for ch in 0..<3 {
                        let p00 = (y0 * cropSize + x0) * 3 + ch, p10 = (y0 * cropSize + x1) * 3 + ch
                        let p01 = (y1 * cropSize + x0) * 3 + ch, p11 = (y1 * cropSize + x1) * 3 + ch
                        let face = Double(src[p00]) * w00 + Double(src[p10]) * w10
                                 + Double(src[p01]) * w01 + Double(src[p11]) * w11
                        let blended = face * Double(m) + Double(out[d + ch]) * (1 - Double(m))
                        out[d + ch] = UInt8(max(0, min(255, blended.rounded())))
                    }
                }
            }
        }
        return RGBImage(width: bw, height: bh, pixels: out)
    }

    private static func bilinear(_ m: [Float], _ size: Int, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int,
                                 _ w00: Double, _ w10: Double, _ w01: Double, _ w11: Double) -> Float {
        Float(Double(m[y0 * size + x0]) * w00 + Double(m[y0 * size + x1]) * w10
            + Double(m[y1 * size + x0]) * w01 + Double(m[y1 * size + x1]) * w11)
    }
}
