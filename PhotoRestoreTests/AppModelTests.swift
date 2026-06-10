import XCTest
import RestoreEngine
@testable import PhotoRestore

@MainActor
final class AppModelTests: XCTestCase {

    private func makeItem(
        id: UUID = UUID(), input: URL = URL(fileURLWithPath: "/tmp/a.png"),
        status: BatchItemStatus = .queued, appliedConfig: RestoreConfig? = nil
    ) -> UIItem {
        UIItem(id: id, input: input, status: status, afterPreview: nil, appliedConfig: appliedConfig)
    }

    // MARK: - sizeTarget

    func testSizeTargetKeepIsSame() {
        let model = AppModel()
        model.sizeChoice = .keep
        XCTAssertEqual(model.sizeTarget(), .same)
    }

    func testSizeTargetScaleFactors() {
        let model = AppModel()
        model.sizeChoice = .x2
        XCTAssertEqual(model.sizeTarget(), .scale(factor: 2))
        model.sizeChoice = .x3
        XCTAssertEqual(model.sizeTarget(), .scale(factor: 3))
        model.sizeChoice = .x4
        XCTAssertEqual(model.sizeTarget(), .scale(factor: 4))
    }

    func testSizeTargetCustomEmptyIsSame() {
        let model = AppModel()
        model.sizeChoice = .custom
        model.customWidth = ""
        model.customHeight = ""
        XCTAssertEqual(model.sizeTarget(), .same)
    }

    func testSizeTargetCustomWidthOnly() {
        let model = AppModel()
        model.sizeChoice = .custom
        model.customWidth = "1920"
        model.customHeight = ""
        XCTAssertEqual(model.sizeTarget(), .size(width: 1920, height: nil))
    }

    func testSizeTargetCustomBothDimensions() {
        let model = AppModel()
        model.sizeChoice = .custom
        model.customWidth = "1920"
        model.customHeight = "1080"
        XCTAssertEqual(model.sizeTarget(), .size(width: 1920, height: 1080))
    }

    // MARK: - currentConfig / divergences

    func testCurrentConfigMapsSettings() {
        let model = AppModel()
        model.sizeChoice = .x2
        model.faceEnabled = false
        model.restorationIntensity = 0.3
        model.matchColor = false
        model.matchGrain = false
        model.skipLargeFaces = false
        model.autoContrast = false

        let config = model.currentConfig()
        XCTAssertEqual(config.target, .scale(factor: 2))
        XCTAssertFalse(config.doFace)
        XCTAssertEqual(config.faceBlend, 0.3)
        XCTAssertFalse(config.matchFaceColor)
        XCTAssertFalse(config.faceGrain)
        XCTAssertEqual(config.faceRestoreThreshold, 0)
        XCTAssertFalse(config.doContrast)
    }

    func testDivergencesReflectCurrentSettings() {
        let model = AppModel()
        XCTAssertEqual(model.divergences(for: nil), [])

        model.faceEnabled = false
        XCTAssertEqual(model.divergences(for: nil), ["Faces off"])
    }

    // MARK: - canReRestore

    func testCanReRestore() {
        let model = AppModel()
        var item = makeItem(status: .queued)
        XCTAssertFalse(model.canReRestore(item))

        item.status = .done
        item.appliedConfig = model.currentConfig()
        XCTAssertFalse(model.canReRestore(item))

        model.faceEnabled = false
        XCTAssertTrue(model.canReRestore(item))
    }

    // MARK: - move

    func testMoveReordersItems() {
        let model = AppModel()
        let a = UUID(), b = UUID(), c = UUID()
        model.items = [makeItem(id: a), makeItem(id: b), makeItem(id: c)]

        model.move(id: c, before: a)

        XCTAssertEqual(model.items.map(\.id), [c, a, b])
    }

    func testMoveToEndWhenTargetMissing() {
        let model = AppModel()
        let a = UUID(), b = UUID(), missing = UUID()
        model.items = [makeItem(id: a), makeItem(id: b)]

        model.move(id: a, before: missing)

        XCTAssertEqual(model.items.map(\.id), [b, a])
    }

    // MARK: - expand

    func testExpandFindsImagesSortedAndIgnoresNonImages() throws {
        let model = AppModel()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let imgB = tmp.appendingPathComponent("b.png")
        let imgA = tmp.appendingPathComponent("a.png")
        let txt = tmp.appendingPathComponent("notes.txt")
        try ImageSaving.save(RGBImage(width: 2, height: 2, fill: 1), to: imgB)
        try ImageSaving.save(RGBImage(width: 2, height: 2, fill: 1), to: imgA)
        try "hello".write(to: txt, atomically: true, encoding: .utf8)

        XCTAssertEqual(model.expand([tmp]), [imgA, imgB])
    }

    func testExpandRespectsIncludeSubfoldersToggle() throws {
        let model = AppModel()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sub = tmp.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let top = tmp.appendingPathComponent("top.png")
        let nested = sub.appendingPathComponent("nested.png")
        try ImageSaving.save(RGBImage(width: 2, height: 2, fill: 1), to: top)
        try ImageSaving.save(RGBImage(width: 2, height: 2, fill: 1), to: nested)

        model.includeSubfolders = false
        XCTAssertEqual(model.expand([tmp]), [top])

        model.includeSubfolders = true
        XCTAssertEqual(model.expand([tmp]), [nested, top])
    }

    func testExpandDedupesAgainstExistingItems() throws {
        let model = AppModel()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let imgA = tmp.appendingPathComponent("a.png")
        let imgB = tmp.appendingPathComponent("b.png")
        try ImageSaving.save(RGBImage(width: 2, height: 2, fill: 1), to: imgA)
        try ImageSaving.save(RGBImage(width: 2, height: 2, fill: 1), to: imgB)

        model.items = [makeItem(input: imgA)]

        XCTAssertEqual(model.expand([tmp]), [imgB])
    }

    // MARK: - apply (event stream -> UI state)

    func testApplyItemStartedSetsProcessingAndSelection() {
        let model = AppModel()
        let id = UUID()
        model.items = [makeItem(id: id, status: .queued)]
        model.selectedID = nil

        model.apply(.itemStarted(id: id))

        XCTAssertEqual(model.items[0].status, .processing)
        XCTAssertEqual(model.selectedID, id)
    }

    func testApplyItemFinishedSetsDoneAndConfig() {
        let model = AppModel()
        let id = UUID()
        let url = URL(fileURLWithPath: "/tmp/a.png")
        model.items = [makeItem(id: id, input: url, status: .processing)]
        let config = RestoreConfig(faceBlend: 0.5)

        model.apply(.itemFinished(id: id, output: url, config: config))

        XCTAssertEqual(model.items[0].status, .done)
        XCTAssertEqual(model.items[0].appliedConfig, config)
    }

    func testApplyItemFailedAndSkipped() {
        let model = AppModel()
        let id1 = UUID(), id2 = UUID()
        model.items = [
            makeItem(id: id1, status: .processing),
            makeItem(id: id2, status: .processing),
        ]

        model.apply(.itemFailed(id: id1, reason: "boom"))
        model.apply(.itemSkipped(id: id2, reason: "exists"))

        XCTAssertEqual(model.items[0].status, .failed("boom"))
        XCTAssertEqual(model.items[1].status, .skipped("exists"))
    }

    func testApplyBatchProgressAndFinished() {
        let model = AppModel()
        model.isRunning = true

        model.apply(.batchProgress(completed: 2, total: 5))
        XCTAssertEqual(model.completed, 2)
        XCTAssertEqual(model.total, 5)

        model.apply(.batchFinished)
        XCTAssertFalse(model.isRunning)
    }
}
