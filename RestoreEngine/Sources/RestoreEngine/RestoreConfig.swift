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
