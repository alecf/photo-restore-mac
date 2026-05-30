import XCTest
@testable import RestoreEngine

/// Identity restorer — returns the input image, emits a preview. No models needed.
private struct FakeRestorer: ImageRestoring {
    func restore(_ loaded: LoadedImage, config: RestoreConfig,
                 onEvent: (@Sendable (RestorePipeline.Event) -> Void)?) async throws -> RGBImage {
        onEvent?(.stageStarted(.contrast))
        onEvent?(.preview(.contrast, loaded.image))
        return loaded.image
    }
}

final class BatchCoordinatorTests: XCTestCase {

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(UUID())")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func writePNG(_ name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try ImageSaving.save(RGBImage(width: 24, height: 24, fill: 140), to: url)
        return url
    }

    private func makeCoordinator(outputDir: URL, format: OutputFormat = .png, overwrite: Bool = false) async -> BatchCoordinator {
        let c = BatchCoordinator(engine: FakeRestorer())
        await c.updateSettings(config: RestoreConfig(doFace: false),
                               policy: OutputPolicy(outputDirectory: outputDir, format: format, overwrite: overwrite))
        return c
    }

    private func drain(_ coord: BatchCoordinator) async -> [BatchEvent] {
        var events: [BatchEvent] = []
        for await e in coord.events {
            events.append(e)
            if case .batchFinished = e { break }
            if events.count > 10_000 { break }
        }
        return events
    }

    func testProcessesAllItems() async throws {
        let inDir = try tempDir(), outDir = try tempDir()
        let a = try writePNG("a.png", in: inDir)
        let b = try writePNG("b.png", in: inDir)
        let coord = await makeCoordinator(outputDir: outDir)
        await coord.enqueue([a, b])
        await coord.start()
        _ = await drain(coord)

        let items = await coord.allItems
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.status == .done })
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("a.png").path))
    }

    func testFinishedReportsConfigUsed() async throws {
        let inDir = try tempDir(), outDir = try tempDir()
        let a = try writePNG("a.png", in: inDir)
        let coord = await makeCoordinator(outputDir: outDir)
        await coord.enqueue([a])
        await coord.start()
        let events = await drain(coord)
        let finished = events.compactMap { e -> RestoreConfig? in
            if case .itemFinished(_, _, let cfg) = e { return cfg }; return nil
        }
        XCTAssertEqual(finished.first?.doFace, false, "reported config should match live settings")
    }

    func testOneBadImageDoesNotStopTheBatch() async throws {
        let inDir = try tempDir(), outDir = try tempDir()
        let good = try writePNG("good.png", in: inDir)
        let bad = inDir.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        let good2 = try writePNG("good2.png", in: inDir)

        let coord = await makeCoordinator(outputDir: outDir)
        await coord.enqueue([good, bad, good2])
        await coord.start()
        _ = await drain(coord)

        let items = await coord.allItems
        XCTAssertEqual(items.filter { $0.status == .done }.count, 2)
        XCTAssertTrue(items.contains { if case .failed = $0.status { return $0.input.lastPathComponent == "bad.png" }; return false })
    }

    func testInPlaceItemIsSkipped() async throws {
        let dir = try tempDir()
        let a = try writePNG("a.png", in: dir)
        let coord = await makeCoordinator(outputDir: dir, format: .keep)  // output == input dir, same ext
        await coord.enqueue([a])
        await coord.start()
        _ = await drain(coord)
        if case .skipped = (await coord.allItems)[0].status {} else { XCTFail("expected skipped") }
    }

    func testReRestoreRequeuesAndRuns() async throws {
        let inDir = try tempDir(), outDir = try tempDir()
        let a = try writePNG("a.png", in: inDir)
        let coord = await makeCoordinator(outputDir: outDir, overwrite: true)
        await coord.enqueue([a])
        await coord.start()
        _ = await drain(coord)
        let id = (await coord.allItems)[0].id

        await coord.reRestore(id: id)
        let requeued = await coord.allItems
        XCTAssertEqual(requeued[0].status, .queued)
        await coord.start()
        _ = await drain(coord)
        let done = await coord.allItems
        XCTAssertEqual(done[0].status, .done)
    }

    func testRemoveAndReorder() async throws {
        let inDir = try tempDir(), outDir = try tempDir()
        let a = try writePNG("a.png", in: inDir)
        let b = try writePNG("b.png", in: inDir)
        let c = try writePNG("c.png", in: inDir)
        let coord = await makeCoordinator(outputDir: outDir)
        let added = await coord.enqueue([a, b, c])
        let ids = added.map(\.id)

        await coord.remove(id: ids[1])  // remove b
        let afterRemove = await coord.allItems
        XCTAssertEqual(afterRemove.map(\.id), [ids[0], ids[2]])

        await coord.reorder([ids[2], ids[0]])
        let afterReorder = await coord.allItems
        XCTAssertEqual(afterReorder.map(\.id), [ids[2], ids[0]])
    }
}
