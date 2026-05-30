import XCTest
@testable import RestoreEngine

final class OutputPolicyTests: XCTestCase {

    func testSingleFileOutputNameAndExtension() {
        let outDir = URL(fileURLWithPath: "/out")
        XCTAssertEqual(
            OutputPolicy(outputDirectory: outDir, format: .png).outputURL(for: URL(fileURLWithPath: "/in/photo.jpeg")).path,
            "/out/photo.png")
        XCTAssertEqual(
            OutputPolicy(outputDirectory: outDir, format: .jpeg).outputURL(for: URL(fileURLWithPath: "/in/photo.png")).path,
            "/out/photo.jpg")
    }

    func testKeepFormatMapsBySource() {
        let p = OutputPolicy(outputDirectory: URL(fileURLWithPath: "/out"), format: .keep)
        XCTAssertEqual(p.outputURL(for: URL(fileURLWithPath: "/in/a.jpg")).lastPathComponent, "a.jpg")
        XCTAssertEqual(p.outputURL(for: URL(fileURLWithPath: "/in/b.JPEG")).lastPathComponent, "b.jpg")
        XCTAssertEqual(p.outputURL(for: URL(fileURLWithPath: "/in/c.heic")).lastPathComponent, "c.png")
        XCTAssertEqual(p.outputURL(for: URL(fileURLWithPath: "/in/d.tiff")).lastPathComponent, "d.png")
    }

    func testInPlaceDetection() {
        // Output dir == input dir, same extension → in place (data-loss guard).
        let p = OutputPolicy(outputDirectory: URL(fileURLWithPath: "/photos"), format: .keep)
        XCTAssertTrue(p.isInPlace(for: URL(fileURLWithPath: "/photos/x.jpg")))
        // Format change yields a distinct filename → not in place.
        let p2 = OutputPolicy(outputDirectory: URL(fileURLWithPath: "/photos"), format: .png)
        XCTAssertFalse(p2.isInPlace(for: URL(fileURLWithPath: "/photos/x.jpg")))
        XCTAssertThrowsError(try p.validateNotInPlace(for: URL(fileURLWithPath: "/photos/x.jpg")))
    }

    func testFolderMirroring() {
        let p = OutputPolicy(outputDirectory: URL(fileURLWithPath: "/out"), format: .png,
                             sourceRoot: URL(fileURLWithPath: "/src"))
        XCTAssertEqual(p.outputURL(for: URL(fileURLWithPath: "/src/sub/deep/x.jpg")).path, "/out/sub/deep/x.png")
    }

    func testValidateWritableSucceedsForTempDir() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("opw-\(UUID())")
        try OutputPolicy(outputDirectory: dir).validateWritable()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testShouldSkipWhenExistsAndNotOverwriting() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ops-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let input = URL(fileURLWithPath: "/in/photo.jpg")
        let p = OutputPolicy(outputDirectory: dir, format: .png, overwrite: false)
        try Data("x".utf8).write(to: p.outputURL(for: input))   // pre-existing output
        XCTAssertTrue(p.shouldSkip(for: input))
        XCTAssertFalse(OutputPolicy(outputDirectory: dir, format: .png, overwrite: true).shouldSkip(for: input))
    }
}
