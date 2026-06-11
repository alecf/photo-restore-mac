import XCTest
@testable import RestoreEngine

final class FaceMaskTests: XCTestCase {

    /// CelebAMask-HQ / BiSeNet classes that should count as "face" for paste-back: skin +
    /// facial features, but not background, neck, cloth, hair, or hat.
    private let expectedFaceClasses: Set<Int32> = [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13]

    func testFaceClassesMatchExpectedSet() {
        // For a 1x1 map, `feathered` reduces to "is this class a face class?" since the
        // Gaussian blur of a single pixel (with edge clamping) preserves its value exactly.
        for cls: Int32 in 0...18 {
            let mask = FaceMask.feathered(classMap: [cls], width: 1, height: 1)
            let isFace = expectedFaceClasses.contains(cls)
            XCTAssertEqual(mask[0], isFace ? 1 : 0, accuracy: 1e-5, "class \(cls)")
        }
    }

    func testAllBackgroundProducesEmptyMask() {
        let classMap = [Int32](repeating: 0, count: 25)
        let mask = FaceMask.feathered(classMap: classMap, width: 5, height: 5)
        XCTAssertEqual(mask, [Float](repeating: 0, count: 25))
    }

    func testFaceRegionFeathersToward1() {
        // A single face-class pixel in the center of a 9x9 map, away from edges so the
        // Gaussian kernel isn't clamped: the blurred mask should sum to ~1 and peak at
        // the center.
        let n = 9
        var classMap = [Int32](repeating: 0, count: n * n)
        let center = (n / 2) * n + (n / 2)
        classMap[center] = 1 // skin

        let mask = FaceMask.feathered(classMap: classMap, width: n, height: n, featherSigma: 1)

        XCTAssertEqual(mask.reduce(0, +), 1, accuracy: 1e-5)
        XCTAssertGreaterThan(mask[center], 0)
        XCTAssertEqual(mask[0], 0) // far corner unaffected by a sigma=1 blur
    }
}
