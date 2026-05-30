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
        XCTAssertEqual(url.absoluteString, "https://example.com/models/v1/GFPGAN.mlmodel")
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
