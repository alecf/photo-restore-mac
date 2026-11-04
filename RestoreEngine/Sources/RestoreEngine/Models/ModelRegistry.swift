import Foundation

/// One downloadable Core ML model artifact. SHA-256 is the authoritative integrity check
/// (pinned in U2 against the validated files); `version` keys the on-disk compiled cache so
/// a model can be updated independently of the app.
public struct ModelSpec: Sendable, Equatable {
    public let name: String
    public let fileName: String      // e.g. "RealESRGAN4x.mlmodel"
    public let sha256: String
    public let sizeBytes: Int
    public let version: String

    public init(name: String, fileName: String, sha256: String, sizeBytes: Int, version: String) {
        self.name = name
        self.fileName = fileName
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
        self.version = version
    }
}

/// The set of models the app fetches on first launch, and where to fetch them from.
///
/// `baseURL` is the one deployment knob. The files are assets on a GitHub release of this
/// repo (see `tools/models/HOSTING.md`), kept out of the signed app bundle so they don't bloat
/// it or the notarization upload. It's a `var` so tests can redirect it at a local `file://`
/// directory. Every file is SHA-256-pinned here.
public enum ModelRegistry {

    /// Hosting base URL: the `models-v2` release's asset downloads.
    public nonisolated(unsafe) static var baseURL = URL(
        string: "https://github.com/alecf/photo-restore-mac/releases/download/models-v2/"
    )!

    public static let realESRGAN = ModelSpec(
        name: "realesrgan-x4plus",
        fileName: "RealESRGAN4x.mlmodel",
        sha256: "6107dc417de87bf974e5b225a2632e2c78f2849265dc897981f482e922050ec9",
        sizeBytes: 66_857_221,
        version: "1"
    )
    /// GFPGAN rewritten to run on the Neural Engine, with fp16 weights. Built from the original
    /// `GFPGAN.mlmodel` by `tools/models/rewrite_gfpgan_ane.py` (deterministic: same bytes).
    public static let gfpgan = ModelSpec(
        name: "gfpgan-v1.4",
        fileName: "GFPGAN-ANE.mlmodel",
        sha256: "ac1034e13cb4082fe663ee79b50df905659449c602fa37e35a8d66d2d6df799f",
        sizeBytes: 173_946_571,
        version: "2"
    )
    public static let faceParsing = ModelSpec(
        name: "face-parsing",
        fileName: "FaceParsing.mlmodel",
        sha256: "e7ebd6cc3f53486becc0dbf3b74027bc045aa4158402936ea09c3625682be6bb",
        sizeBytes: 53_182_369,
        version: "1"
    )

    public static let all: [ModelSpec] = [realESRGAN, gfpgan, faceParsing]

    public static var totalBytes: Int { all.reduce(0) { $0 + $1.sizeBytes } }

    /// The file names "Install from Folder" expects, for messages: "A, B and C".
    public static var fileNamesList: String {
        let names = all.map(\.fileName)
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    public static func remoteURL(for spec: ModelSpec) -> URL {
        baseURL.appendingPathComponent(spec.fileName)
    }
}
