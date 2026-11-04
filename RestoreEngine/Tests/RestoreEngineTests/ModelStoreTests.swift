import XCTest
import CryptoKit
@testable import RestoreEngine

final class ModelRegistryTests: XCTestCase {

    func testRegistryHasThreeModels() {
        XCTAssertEqual(ModelRegistry.all.count, 3)
        XCTAssertEqual(ModelRegistry.totalBytes,
                       ModelRegistry.all.reduce(0) { $0 + $1.sizeBytes })
    }

    func testRemoteURLAppendsFileName() {
        let original = ModelRegistry.baseURL
        defer { ModelRegistry.baseURL = original }
        ModelRegistry.baseURL = URL(string: "https://example.com/models/v1/")!
        let url = ModelRegistry.remoteURL(for: ModelRegistry.gfpgan)
        XCTAssertEqual(url.absoluteString, "https://example.com/models/v1/GFPGAN-ANE.mlmodel")
    }
}

final class ModelStoreTests: XCTestCase {

    private func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("modelstore-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testIsReadyFalseWhenEmpty() async throws {
        let store = ModelStore(root: try makeTempRoot())
        let ready = await store.isReady()
        XCTAssertFalse(ready)
    }

    func testCompiledURLEncodesVersionAndName() async throws {
        let root = try makeTempRoot()
        let store = ModelStore(root: root)
        let url = await store.compiledURL(for: ModelRegistry.realESRGAN)
        XCTAssertTrue(url.path.contains("/compiled/v1/"))
        XCTAssertTrue(url.lastPathComponent == "realesrgan-x4plus.mlmodelc")
    }

    func testVerifyPassesForMatchingHash() async throws {
        let root = try makeTempRoot()
        let store = ModelStore(root: root)
        let payload = Data("the quick brown fox".utf8)
        let file = root.appendingPathComponent("good.bin")
        try payload.write(to: file)
        let spec = ModelSpec(name: "t", fileName: "good.bin", sha256: sha256(of: payload),
                             sizeBytes: payload.count, version: "1")
        try await store.verify(file, spec: spec)   // must not throw
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    /// A raw file already at full size (the app quit after downloading, before verifying) must
    /// go straight to verify + compile. A Range request past its end would get HTTP 416.
    func testFullyDownloadedFileSkipsTheNetwork() async throws {
        let root = try makeTempRoot()
        let store = ModelStore(root: root)
        let payload = Data("not really a model".utf8)
        let spec = ModelSpec(name: "t", fileName: "t.mlmodel", sha256: sha256(of: payload),
                             sizeBytes: payload.count, version: "1")
        let raw = root.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try payload.write(to: raw.appendingPathComponent(spec.fileName))

        let original = ModelRegistry.baseURL
        defer { ModelRegistry.baseURL = original }
        ModelRegistry.baseURL = URL(string: "https://unreachable.invalid/")!
        do {
            _ = try await store.compiledModel(for: spec)
            XCTFail("expected the compile step to reject the fake model")
        } catch ModelStore.ModelError.compileFailed {
            // Verified and handed to the compiler without touching the network.
        }
    }

    /// A full-size file with the wrong contents (stale, from an older model with the same name)
    /// must be thrown away and downloaded again, not reported as an integrity failure.
    func testStaleFullSizeFileIsDownloadedAgain() async throws {
        let root = try makeTempRoot()
        let store = ModelStore(root: root)
        let spec = ModelSpec(name: "t", fileName: "t.mlmodel", sha256: String(repeating: "0", count: 64),
                             sizeBytes: 5, version: "1")
        let raw = root.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let file = raw.appendingPathComponent(spec.fileName)
        try Data("stale".utf8).write(to: file)

        let original = ModelRegistry.baseURL
        defer { ModelRegistry.baseURL = original }
        ModelRegistry.baseURL = URL(string: "https://unreachable.invalid/")!
        do {
            _ = try await store.compiledModel(for: spec)
            XCTFail("expected the download to fail: the host doesn't resolve")
        } catch ModelStore.ModelError.verificationFailed {
            XCTFail("a stale file should trigger a new download, not an integrity error")
        } catch {
            // Reached the network, so the stale file was dropped and a download was attempted.
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testRemoveStaleModelsKeepsOnlyCurrentVersions() async throws {
        let root = try makeTempRoot()
        let store = ModelStore(root: root)
        let fm = FileManager.default
        func makeDir(_ url: URL) throws { try fm.createDirectory(at: url, withIntermediateDirectories: true) }

        let current = await store.compiledURL(for: ModelRegistry.gfpgan)
        let compiled = root.appendingPathComponent("compiled", isDirectory: true)
        let oldGFPGAN = compiled.appendingPathComponent("v1/\(ModelRegistry.gfpgan.name).mlmodelc", isDirectory: true)
        let keptV1 = await store.compiledURL(for: ModelRegistry.realESRGAN)   // still version 1
        let goneVersion = compiled.appendingPathComponent("v0/removed-model.mlmodelc", isDirectory: true)
        for dir in [current, oldGFPGAN, keptV1, goneVersion] { try makeDir(dir) }

        let raw = root.appendingPathComponent("raw", isDirectory: true)
        try makeDir(raw)
        let oldRaw = raw.appendingPathComponent("GFPGAN.mlmodel")
        let partial = raw.appendingPathComponent(ModelRegistry.gfpgan.fileName)   // a resumable download
        try Data("x".utf8).write(to: oldRaw)
        try Data("x".utf8).write(to: partial)

        await store.removeStaleModels()

        XCTAssertTrue(fm.fileExists(atPath: current.path))
        XCTAssertTrue(fm.fileExists(atPath: keptV1.path))
        XCTAssertFalse(fm.fileExists(atPath: oldGFPGAN.path))
        XCTAssertFalse(fm.fileExists(atPath: goneVersion.deletingLastPathComponent().path), "empty version folder")
        XCTAssertFalse(fm.fileExists(atPath: oldRaw.path))
        XCTAssertTrue(fm.fileExists(atPath: partial.path))
    }

    func testVerifyFailsAndDeletesOnMismatch() async throws {
        let root = try makeTempRoot()
        let store = ModelStore(root: root)
        let file = root.appendingPathComponent("bad.bin")
        try Data("corrupt".utf8).write(to: file)
        let spec = ModelSpec(name: "t", fileName: "bad.bin", sha256: String(repeating: "0", count: 64),
                             sizeBytes: 7, version: "1")
        do {
            try await store.verify(file, spec: spec)
            XCTFail("expected verification to throw")
        } catch ModelStore.ModelError.verificationFailed {
            // The bad file must be removed so a retry re-downloads cleanly.
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
    }
}
