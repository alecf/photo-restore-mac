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

    /// Drain events until the batch finishes (or a generous cap, so a bug fails fast not hangs).
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
        let coord = BatchCoordinator(engine: FakeRestorer())
        let policy = OutputPolicy(outputDirectory: outDir, format: .png)
        await coord.enqueue([a, b], config: RestoreConfig(doFace: false), output: policy)
        await coord.start()
        _ = await drain(coord)

        let items = await coord.allItems
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.status == .done })
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("a.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("b.png").path))
    }

    func testOneBadImageDoesNotStopTheBatch() async throws {
        let inDir = try tempDir(), outDir = try tempDir()
        let good = try writePNG("good.png", in: inDir)
        let bad = inDir.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)   // undecodable → load throws
        let good2 = try writePNG("good2.png", in: inDir)

        let coord = BatchCoordinator(engine: FakeRestorer())
        await coord.enqueue([good, bad, good2], config: RestoreConfig(doFace: false),
                            output: OutputPolicy(outputDirectory: outDir, format: .png))
        await coord.start()
        _ = await drain(coord)

        let items = await coord.allItems
        XCTAssertEqual(items.filter { $0.status == .done }.count, 2)
        let failed = items.first { if case .failed = $0.status { return true }; return false }
        XCTAssertEqual(failed?.input.lastPathComponent, "bad.png")
    }

    func testInPlaceItemIsSkipped() async throws {
        let dir = try tempDir()
        let a = try writePNG("a.png", in: dir)
        let coord = BatchCoordinator(engine: FakeRestorer())
        // Output dir == input dir, keep format (same ext) → in-place → skipped, not processed.
        await coord.enqueue([a], config: RestoreConfig(doFace: false),
                            output: OutputPolicy(outputDirectory: dir, format: .keep))
        await coord.start()
        _ = await drain(coord)
        let items = await coord.allItems
        if case .skipped = items[0].status {} else { XCTFail("expected skipped, got \(items[0].status)") }
    }

    func testExistingOutputSkippedUnlessOverwrite() async throws {
        let inDir = try tempDir(), outDir = try tempDir()
        let a = try writePNG("a.png", in: inDir)
        let policy = OutputPolicy(outputDirectory: outDir, format: .png, overwrite: false)
        try Data("existing".utf8).write(to: policy.outputURL(for: a))  // pre-existing output

        let coord = BatchCoordinator(engine: FakeRestorer())
        await coord.enqueue([a], config: RestoreConfig(doFace: false), output: policy)
        await coord.start()
        _ = await drain(coord)
        let items = await coord.allItems
        if case .skipped = items[0].status {} else { XCTFail("expected skipped (exists), got \(items[0].status)") }
    }

    func testEmitsStartedAndFinishedEvents() async throws {
        let inDir = try tempDir(), outDir = try tempDir()
        let a = try writePNG("a.png", in: inDir)
        let coord = BatchCoordinator(engine: FakeRestorer())
        await coord.enqueue([a], config: RestoreConfig(doFace: false),
                            output: OutputPolicy(outputDirectory: outDir, format: .png))
        await coord.start()
        let events = await drain(coord)

        XCTAssertTrue(events.contains { if case .itemStarted = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .itemFinished = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .batchFinished = $0 { return true }; return false })
    }
}
