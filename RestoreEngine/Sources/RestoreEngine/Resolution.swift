import Foundation

/// Pure resolution math: turn a `--scale`/`--size`-style request into exact target
/// dimensions, always preserving aspect ratio. Direct port of the Python CLI's
/// `resolution.py` (the most correctness-sensitive logic), kept dependency-free.
public enum Resolution {

    public struct ResolutionError: Error, CustomStringConvertible, Equatable {
        public let message: String
        public var description: String { message }
    }

    /// A resolved request for output size, independent of any input image.
    public enum Target: Sendable, Equatable {
        case same
        case scale(factor: Double)
        /// Fit inside a bounding box; either dimension may be absent.
        case size(width: Int?, height: Int?)
    }

    /// Parse `--scale`: `same`, `2x`, `3`, `4x`, `1.5x`.
    public static func parseScale(_ value: String) throws -> Target {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        if v == "same" { return .same }
        // ^(\d+(\.\d+)?)x?$
        var s = Substring(v)
        if s.hasSuffix("x") { s = s.dropLast() }
        guard !s.isEmpty, let factor = Double(s), isPlainNumber(String(s)) else {
            throw ResolutionError(message: "invalid scale \(value.debugDescription): expected 'same' or a factor like '2x', '3', '4x'")
        }
        guard factor > 0 else {
            throw ResolutionError(message: "invalid scale \(value.debugDescription): factor must be positive")
        }
        return .scale(factor: factor)
    }

    /// Parse `--size`: `WxH` (fit inside box), `Wx` (width only), `xH` (height only).
    public static func parseSize(_ value: String) throws -> Target {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = v.split(separator: "x", omittingEmptySubsequences: false)
        // Must contain exactly one 'x' → two parts.
        guard parts.count == 2 else {
            throw ResolutionError(message: sizeError(value))
        }
        let wStr = String(parts[0])
        let hStr = String(parts[1])
        let width = wStr.isEmpty ? nil : Int(wStr)
        let height = hStr.isEmpty ? nil : Int(hStr)
        // Reject non-numeric (Int() returned nil for a non-empty part).
        if (!wStr.isEmpty && width == nil) || (!hStr.isEmpty && height == nil) {
            throw ResolutionError(message: sizeError(value))
        }
        if width == nil && height == nil {
            throw ResolutionError(message: sizeError(value))
        }
        for dim in [width, height] {
            if let dim, dim <= 0 {
                throw ResolutionError(message: "invalid size \(value.debugDescription): dimensions must be positive")
            }
        }
        return .size(width: width, height: height)
    }

    /// Resolve a `Target` against an actual image size to exact output dimensions.
    /// Aspect ratio is always preserved; a `size` box fits the image *inside* it.
    public static func resolveDimensions(_ target: Target, origW: Int, origH: Int) throws -> (width: Int, height: Int) {
        guard origW > 0, origH > 0 else {
            throw ResolutionError(message: "invalid source dimensions: \(origW)x\(origH)")
        }
        switch target {
        case .same:
            return (origW, origH)
        case .scale(let factor):
            return (roundDim(Double(origW) * factor), roundDim(Double(origH) * factor))
        case .size(let width, let height):
            var factors: [Double] = []
            if let width { factors.append(Double(width) / Double(origW)) }
            if let height { factors.append(Double(height) / Double(origH)) }
            let factor = factors.min()!
            return (roundDim(Double(origW) * factor), roundDim(Double(origH) * factor))
        }
    }

    /// Whether the target is larger than the source on either axis. When false the
    /// super-resolution model is skipped entirely (Lanczos-only path).
    public static func needsEnlargement(origW: Int, origH: Int, targetW: Int, targetH: Int) -> Bool {
        targetW > origW || targetH > origH
    }

    // MARK: - Internals

    /// Match Python's `round()` (banker's rounding / round-half-to-even), then floor at 1.
    private static func roundDim(_ value: Double) -> Int {
        max(1, Int(value.rounded(.toNearestOrEven)))
    }

    private static func isPlainNumber(_ s: String) -> Bool {
        // Disallow signs / exponents that Double() would accept but the CLI regex would not.
        s.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func sizeError(_ value: String) -> String {
        "invalid size \(value.debugDescription): expected 'WxH', 'Wx', or 'xH' (e.g. '2000x2000', '2000x', 'x1500')"
    }
}
