import Foundation

public enum OutputFormat: String, Sendable, CaseIterable, Codable {
    case png, jpeg, keep   // keep = JPEG for JPEG sources, PNG otherwise
}

public enum OutputError: Error, CustomStringConvertible {
    case inPlaceOverwrite(URL)
    case notWritable(URL)
    public var description: String {
        switch self {
        case .inPlaceOverwrite(let u): return "refusing to overwrite the original in place: \(u.lastPathComponent)"
        case .notWritable(let u): return "output folder isn't writable: \(u.path)"
        }
    }
}

/// Resolves where each restored image is written and enforces the data-safety rules surfaced
/// during planning: never overwrite an original in place, skip already-restored files unless
/// asked, and mirror a dropped folder's structure. Pure + deterministic so it's fully tested.
public struct OutputPolicy: Sendable {
    public var outputDirectory: URL
    public var format: OutputFormat
    public var overwrite: Bool
    /// When set (folder mode), the input's path relative to this root is mirrored under the
    /// output directory. Nil (single-file mode) flattens into the output directory.
    public var sourceRoot: URL?

    public init(outputDirectory: URL, format: OutputFormat = .keep, overwrite: Bool = false, sourceRoot: URL? = nil) {
        self.outputDirectory = outputDirectory
        self.format = format
        self.overwrite = overwrite
        self.sourceRoot = sourceRoot
    }

    public func outputURL(for input: URL) -> URL {
        let ext = self.ext(for: input)
        let base: URL
        if let root = sourceRoot, let rel = relativePath(of: input, under: root) {
            base = outputDirectory.appendingPathComponent(rel)
        } else {
            base = outputDirectory.appendingPathComponent(input.lastPathComponent)
        }
        return base.deletingPathExtension().appendingPathExtension(ext)
    }

    /// True when the resolved output path is the input itself (would clobber the original).
    public func isInPlace(for input: URL) -> Bool {
        outputURL(for: input).standardizedFileURL == input.standardizedFileURL
    }

    /// True when an output already exists and we're not overwriting (resumable batches).
    public func shouldSkip(for input: URL) -> Bool {
        !overwrite && FileManager.default.fileExists(atPath: outputURL(for: input).path)
    }

    /// Throws if the resolved output would clobber the original.
    public func validateNotInPlace(for input: URL) throws {
        if isInPlace(for: input) { throw OutputError.inPlaceOverwrite(input) }
    }

    /// Pre-flight: the output root must exist (creatable) and accept a write — catches a
    /// read-only or vanished volume before a long batch starts.
    public func validateWritable() throws {
        let fm = FileManager.default
        try? fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let probe = outputDirectory.appendingPathComponent(".photorestore-write-probe-\(UUID().uuidString)")
        guard fm.createFile(atPath: probe.path, contents: Data("ok".utf8)) else {
            throw OutputError.notWritable(outputDirectory)
        }
        try? fm.removeItem(at: probe)
    }

    // MARK: - helpers

    func ext(for input: URL) -> String {
        switch format {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .keep:
            let e = input.pathExtension.lowercased()
            return (e == "jpg" || e == "jpeg") ? "jpg" : "png"
        }
    }

    private func relativePath(of input: URL, under root: URL) -> String? {
        let inParts = input.standardizedFileURL.pathComponents
        let rootParts = root.standardizedFileURL.pathComponents
        guard inParts.count > rootParts.count, Array(inParts.prefix(rootParts.count)) == rootParts else {
            return nil
        }
        return inParts.suffix(from: rootParts.count).joined(separator: "/")
    }
}
