import XCTest
@testable import RestoreEngine

final class ResolutionTests: XCTestCase {

    func testSameKeepsDimensions() throws {
        let t = try Resolution.parseScale("same")
        XCTAssertEqual(t, .same)
        let (w, h) = try Resolution.resolveDimensions(t, origW: 1234, origH: 567)
        XCTAssertEqual(w, 1234)
        XCTAssertEqual(h, 567)
    }

    func testScaleFactors() throws {
        XCTAssertEqual(try Resolution.parseScale("2x"), .scale(factor: 2))
        XCTAssertEqual(try Resolution.parseScale("3"), .scale(factor: 3))
        XCTAssertEqual(try Resolution.parseScale("1.5x"), .scale(factor: 1.5))

        let (w, h) = try Resolution.resolveDimensions(.scale(factor: 2), origW: 100, origH: 50)
        XCTAssertEqual(w, 200)
        XCTAssertEqual(h, 100)
    }

    func testScaleBankersRounding() throws {
        // 101 * 1.5 = 151.5 → round-half-to-even → 152 (matches Python round()).
        let (w, _) = try Resolution.resolveDimensions(.scale(factor: 1.5), origW: 101, origH: 101)
        XCTAssertEqual(w, 152)
    }

    func testSizeFitInsideBox() throws {
        let t = try Resolution.parseSize("2000x2000")
        XCTAssertEqual(t, .size(width: 2000, height: 2000))
        // 3000x2000 fit inside 2000x2000 → factor 2000/3000 → 2000 x 1333.
        let (w, h) = try Resolution.resolveDimensions(t, origW: 3000, origH: 2000)
        XCTAssertEqual(w, 2000)
        XCTAssertEqual(h, 1333)
    }

    func testSizeSingleAxis() throws {
        XCTAssertEqual(try Resolution.parseSize("1600x"), .size(width: 1600, height: nil))
        XCTAssertEqual(try Resolution.parseSize("x1500"), .size(width: nil, height: 1500))
        let (w, h) = try Resolution.resolveDimensions(.size(width: 1600, height: nil), origW: 3200, origH: 2400)
        XCTAssertEqual(w, 1600)
        XCTAssertEqual(h, 1200)
    }

    func testNeedsEnlargement() {
        XCTAssertTrue(Resolution.needsEnlargement(origW: 100, origH: 100, targetW: 200, targetH: 100))
        XCTAssertFalse(Resolution.needsEnlargement(origW: 100, origH: 100, targetW: 100, targetH: 100))
        XCTAssertFalse(Resolution.needsEnlargement(origW: 100, origH: 100, targetW: 50, targetH: 50))
    }

    func testInvalidInputsThrow() {
        XCTAssertThrowsError(try Resolution.parseScale("huge"))
        XCTAssertThrowsError(try Resolution.parseScale("-2x"))
        XCTAssertThrowsError(try Resolution.parseScale("0"))
        XCTAssertThrowsError(try Resolution.parseSize("2000"))      // no 'x'
        XCTAssertThrowsError(try Resolution.parseSize("x"))         // both empty
        XCTAssertThrowsError(try Resolution.parseSize("axb"))       // non-numeric
        XCTAssertThrowsError(try Resolution.parseSize("0x0"))       // non-positive
    }
}
