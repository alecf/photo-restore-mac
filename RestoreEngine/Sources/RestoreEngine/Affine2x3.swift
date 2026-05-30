import CoreGraphics
import Foundation

/// A 2×3 affine transform `[a b tx; c d ty]` mapping (x,y) → (a·x + b·y + tx, c·x + d·y + ty).
/// Used for face alignment (source → 512 template) and its inverse for paste-back.
public struct Affine2x3: Sendable, Equatable {
    public var a, b, tx: Double
    public var c, d, ty: Double

    public init(a: Double, b: Double, tx: Double, c: Double, d: Double, ty: Double) {
        self.a = a; self.b = b; self.tx = tx
        self.c = c; self.d = d; self.ty = ty
    }

    public static let identity = Affine2x3(a: 1, b: 0, tx: 0, c: 0, d: 1, ty: 0)

    public func apply(_ p: CGPoint) -> CGPoint {
        CGPoint(x: a * Double(p.x) + b * Double(p.y) + tx,
                y: c * Double(p.x) + d * Double(p.y) + ty)
    }

    /// The inverse transform (nil if singular).
    public var inverse: Affine2x3? {
        let det = a * d - b * c
        guard abs(det) > 1e-12 else { return nil }
        let ia = d / det, ib = -b / det
        let ic = -c / det, id = a / det
        return Affine2x3(
            a: ia, b: ib, tx: -(ia * tx + ib * ty),
            c: ic, d: id, ty: -(ic * tx + id * ty)
        )
    }
}
