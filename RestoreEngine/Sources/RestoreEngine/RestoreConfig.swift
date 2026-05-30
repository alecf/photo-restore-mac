import Foundation

/// Restoration strength (face model). v1 ships `conservative` (GFPGAN) only; the
/// `balanced` (CodeFormer) case is the seam for the deferred follow-up.
public enum RestoreStrength: String, Sendable, CaseIterable, Codable {
    case conservative
    case balanced
}

public enum ComputeDevice: String, Sendable, CaseIterable, Codable {
    case auto
    case gpu
    case cpu
}

/// All knobs for one restoration run — a `Sendable` value snapshotted per image at
/// enqueue time. Mirrors the Python `Config`; defaults match the CLI.
public struct RestoreConfig: Sendable, Equatable {
    public var target: Resolution.Target
    public var strength: RestoreStrength
    public var fidelity: Double?            // CodeFormer fidelity for `.balanced`
    public var doFace: Bool
    public var doContrast: Bool
    public var faceBlend: Double            // 1.0 = fully restored, 0.0 = original
    public var faceRestoreThreshold: Int    // skip faces larger than this (source px); 0 = all
    public var faceGrain: Bool
    public var matchFaceColor: Bool
    public var device: ComputeDevice

    public init(
        target: Resolution.Target = .same,
        strength: RestoreStrength = .conservative,
        fidelity: Double? = nil,
        doFace: Bool = true,
        doContrast: Bool = true,
        faceBlend: Double = 0.8,
        faceRestoreThreshold: Int = 500,
        faceGrain: Bool = true,
        matchFaceColor: Bool = true,
        device: ComputeDevice = .auto
    ) {
        self.target = target
        self.strength = strength
        self.fidelity = fidelity
        self.doFace = doFace
        self.doContrast = doContrast
        self.faceBlend = faceBlend
        self.faceRestoreThreshold = faceRestoreThreshold
        self.faceGrain = faceGrain
        self.matchFaceColor = matchFaceColor
        self.device = device
    }
}

extension RestoreConfig {
    /// Human-readable settings that differ from the defaults — for showing "what was used"
    /// compactly (only the divergences, never a full dump). Empty == all defaults.
    public func divergences(from defaults: RestoreConfig = RestoreConfig()) -> [String] {
        var out: [String] = []
        if target != defaults.target { out.append("Size: \(RestoreConfig.describe(target))") }
        if doFace != defaults.doFace { out.append(doFace ? "Faces on" : "Faces off") }
        if doFace {
            if faceBlend != defaults.faceBlend { out.append("Intensity \(Int((faceBlend * 100).rounded()))%") }
            if matchFaceColor != defaults.matchFaceColor { out.append(matchFaceColor ? "Color-match on" : "Color-match off") }
            if faceGrain != defaults.faceGrain { out.append(faceGrain ? "Grain on" : "Grain off") }
            if faceRestoreThreshold != defaults.faceRestoreThreshold {
                out.append(faceRestoreThreshold <= 0 ? "Restore all faces" : "Skip faces > \(faceRestoreThreshold)px")
            }
        }
        if doContrast != defaults.doContrast { out.append(doContrast ? "Auto-contrast on" : "Auto-contrast off") }
        if device != defaults.device { out.append("Device: \(device.rawValue)") }
        return out
    }

    static func describe(_ target: Resolution.Target) -> String {
        switch target {
        case .same: return "Keep original"
        case .scale(let f):
            let s = f == f.rounded() ? String(Int(f)) : String(f)
            return "\(s)×"
        case .size(let w, let h):
            return "≤ \(w.map(String.init) ?? "")×\(h.map(String.init) ?? "")"
        }
    }
}
