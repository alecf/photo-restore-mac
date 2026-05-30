import XCTest
@testable import RestoreEngine

/// Verifies the local side-load path the app's SetupView uses: import the validated .mlmodel
/// files from a folder, compile + cache them, and report ready. Guarded — skipped unless the
/// U2 model cache is present. As a useful side effect it populates the same Application Support
/// location the app reads, so a manual launch lands in the ready state.
final class ModelImportIntegrationTests: XCTestCase {

    private func cacheDir() -> URL? {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/models/cache")
        let names = ModelRegistry.all.map { $0.fileName }
        let present = names.allSatisfy { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
        return present ? dir : nil
    }

    func testImportFromLocalFolderMakesReady() async throws {
        guard let cache = cacheDir() else {
            throw XCTSkip("model cache not present — run tools/models/download.py")
        }
        // Use the app's default store location so this also primes a real launch.
        let store = ModelStore()
        let ready = try await store.importLocalModels(from: cache)
        XCTAssertEqual(Set(ready), Set(ModelRegistry.all.map(\.name)))
        let isReady = await store.isReady()
        XCTAssertTrue(isReady)

        // Compiled artifacts must be loadable into a working engine.
        let urls = await store.compiledURLs()
        let engine = try InferenceEngine.make(esrganURL: urls.esrgan, gfpganURL: urls.gfpgan, parseURL: urls.parse)
        await engine.warmUp()
    }
}
