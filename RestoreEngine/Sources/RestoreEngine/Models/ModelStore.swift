import CoreML
import CryptoKit
import Foundation

/// Acquires and caches the Core ML models: download-on-first-launch with resume + SHA-256
/// verification, compile to `.mlmodelc`, and store the compiled artifact in Application
/// Support keyed by model version (so subsequent launches skip both download and the
/// multi-second compile). Storing in Application Support — not Caches — keeps the OS from
/// purging it under disk pressure and forcing a surprise re-download.
public actor ModelStore {

    public enum ModelError: Error, CustomStringConvertible {
        case offline
        case http(Int)
        case verificationFailed(model: String, expected: String, got: String)
        case compileFailed(model: String, underlying: String)
        case diskFull

        public var description: String {
            switch self {
            case .offline: return "No internet connection — models are required on first launch."
            case .http(let code): return "Model download failed (HTTP \(code))."
            case .verificationFailed(let m, _, _): return "Downloaded \(m) failed integrity check."
            case .compileFailed(let m, let u): return "Could not compile \(m): \(u)."
            case .diskFull: return "Not enough disk space to install the models."
            }
        }
    }

    private let session: URLSession
    private let modelsRoot: URL
    private let fileManager = FileManager.default

    /// - Parameter root: base directory for model storage. Defaults to
    ///   `Application Support/<bundle-id>/Models`. Tests inject a temp directory.
    public init(root: URL? = nil, session: URLSession = .shared) {
        self.session = session
        if let root {
            self.modelsRoot = root
        } else {
            let appSupport = (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )) ?? FileManager.default.temporaryDirectory
            let bundleID = Bundle.main.bundleIdentifier ?? "com.alecf.PhotoRestore"
            self.modelsRoot = appSupport.appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        }
    }

    // MARK: - Public API

    /// Whether every registered model is already compiled and cached (nothing to download).
    public func isReady() -> Bool {
        ModelRegistry.all.allSatisfy { fileManager.fileExists(atPath: compiledURL(for: $0).path) }
    }

    /// Return the compiled `.mlmodelc` URL for a model, downloading + compiling it if needed.
    public func compiledModel(
        for spec: ModelSpec,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let target = compiledURL(for: spec)
        if fileManager.fileExists(atPath: target.path) { return target }

        let raw = try await download(spec, onProgress: onProgress)
        try verify(raw, spec: spec)

        let compiled: URL
        do {
            compiled = try await MLModel.compileModel(at: raw)
        } catch {
            throw ModelError.compileFailed(model: spec.name, underlying: "\(error)")
        }

        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: target)
        try fileManager.moveItem(at: compiled, to: target)
        try? fileManager.removeItem(at: raw)   // compiled artifact is what we load; reclaim space
        return target
    }

    /// Ensure all registered models are present, reporting overall progress weighted by size.
    public func ensureAll(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        let total = Double(ModelRegistry.totalBytes)
        var completedBytes = 0.0
        for spec in ModelRegistry.all {
            let weight = Double(spec.sizeBytes)
            let base = completedBytes   // immutable capture for the @Sendable progress closure
            _ = try await compiledModel(for: spec) { fraction in
                onProgress?((base + fraction * weight) / total)
            }
            completedBytes += weight
            onProgress?(completedBytes / total)
        }
    }

    // MARK: - Paths

    func compiledURL(for spec: ModelSpec) -> URL {
        modelsRoot
            .appendingPathComponent("compiled/v\(spec.version)", isDirectory: true)
            .appendingPathComponent("\(spec.name).mlmodelc", isDirectory: true)
    }

    private func rawURL(for spec: ModelSpec) -> URL {
        modelsRoot.appendingPathComponent("raw", isDirectory: true).appendingPathComponent(spec.fileName)
    }

    // MARK: - Download (streaming, resumable, with progress)

    private func download(_ spec: ModelSpec, onProgress: (@Sendable (Double) -> Void)?) async throws -> URL {
        let dest = rawURL(for: spec)
        try fileManager.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Resume: if a partial file exists, continue from its byte offset via a Range request.
        let existing = (try? fileManager.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? nil
        let resumeFrom = existing ?? 0
        let remote = ModelRegistry.remoteURL(for: spec)

        var request = URLRequest(url: remote)
        if resumeFrom > 0 { request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range") }

        let bytesStream: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytesStream, response) = try await session.bytes(for: request)
        } catch {
            if (error as? URLError)?.code == .notConnectedToInternet { throw ModelError.offline }
            throw error
        }

        guard let http = response as? HTTPURLResponse else { throw ModelError.http(0) }
        // 206 = resumed partial; 200 = full (server ignored Range → start over).
        let appending = http.statusCode == 206 && resumeFrom > 0
        guard http.statusCode == 200 || http.statusCode == 206 else {
            throw ModelError.http(http.statusCode)
        }
        if !appending { try? fileManager.removeItem(at: dest) }
        if !fileManager.fileExists(atPath: dest.path) {
            fileManager.createFile(atPath: dest.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }
        if appending { try handle.seekToEnd() }

        let expected = Double(spec.sizeBytes)
        var written = Double(appending ? resumeFrom : 0)
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)

        do {
            for try await byte in bytesStream {
                buffer.append(byte)
                if buffer.count >= (1 << 20) {
                    try handle.write(contentsOf: buffer)
                    written += Double(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    onProgress?(min(written / expected, 1.0))
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            onProgress?(1.0)
        } catch {
            if (error as? URLError)?.code == .notConnectedToInternet { throw ModelError.offline }
            throw error
        }
        return dest
    }

    // MARK: - Verify

    func verify(_ url: URL, spec: ModelSpec) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while case let chunk = handle.readData(ofLength: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == spec.sha256 else {
            try? fileManager.removeItem(at: url)   // drop the bad file so a retry re-downloads
            throw ModelError.verificationFailed(model: spec.name, expected: spec.sha256, got: digest)
        }
    }
}
