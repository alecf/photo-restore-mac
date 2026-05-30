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
/// `baseURL` is the one deployment knob: point it at the hosting bucket (Cloudflare R2 /
/// S3). It's a `var` so tests can redirect it at a local `file://` directory. The files
/// themselves are the U2-validated, SHA-256-pinned artifacts (re-hosted out of the signed
/// app bundle so they don't bloat it or the notarization upload).
public enum ModelRegistry {

    /// Hosting base URL. TODO: set to the real R2 bucket once provisioned, e.g.
    /// `https://<bucket>.r2.cloudflarestorage.com/photo-restore/models/v1/`.
    public nonisolated(unsafe) static var baseURL = URL(
        string: "https://models.photorestore.invalid/v1/"
    )!

    public static let realESRGAN = ModelSpec(
        name: "realesrgan-x4plus",
        fileName: "RealESRGAN4x.mlmodel",
        sha256: "6107dc417de87bf974e5b225a2632e2c78f2849265dc897981f482e922050ec9",
        sizeBytes: 66_857_221,
        version: "1"
    )
    public static let gfpgan = ModelSpec(
        name: "gfpgan-v1.4",
        fileName: "GFPGAN.mlmodel",
        sha256: "218a39c226adecb2ccbc1e358023b80a5cf2510be85dfc3ab0da698fad51391a",
        sizeBytes: 337_392_296,
        version: "1"
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

    public static func remoteURL(for spec: ModelSpec) -> URL {
        baseURL.appendingPathComponent(spec.fileName)
    }
}
