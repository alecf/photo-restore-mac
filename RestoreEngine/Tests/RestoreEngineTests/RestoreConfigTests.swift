import XCTest
@testable import RestoreEngine

final class RestoreConfigTests: XCTestCase {

    func testDefaultConfigHasNoDivergences() {
        XCTAssertEqual(RestoreConfig().divergences(), [])
    }

    func testSizeDivergence() {
        XCTAssertEqual(
            RestoreConfig(target: .scale(factor: 2)).divergences(),
            ["Size: 2×"])
        XCTAssertEqual(
            RestoreConfig(target: .scale(factor: 1.5)).divergences(),
            ["Size: 1.5×"])
        XCTAssertEqual(
            RestoreConfig(target: .size(width: 1920, height: nil)).divergences(),
            ["Size: ≤ 1920×"])
        XCTAssertEqual(
            RestoreConfig(target: .size(width: nil, height: 1080)).divergences(),
            ["Size: ≤ ×1080"])
    }

    func testFacesOffSuppressesFaceSubsettings() {
        // When faces are off, face-only settings (even if non-default) shouldn't be reported.
        let config = RestoreConfig(doFace: false, faceBlend: 0.5, matchFaceColor: false)
        XCTAssertEqual(config.divergences(), ["Faces off"])
    }

    func testFaceSubsettingDivergences() {
        XCTAssertEqual(
            RestoreConfig(faceBlend: 0.5).divergences(),
            ["Intensity 50%"])
        XCTAssertEqual(
            RestoreConfig(matchFaceColor: false).divergences(),
            ["Color-match off"])
        XCTAssertEqual(
            RestoreConfig(faceGrain: false).divergences(),
            ["Grain off"])
        XCTAssertEqual(
            RestoreConfig(faceRestoreThreshold: 0).divergences(),
            ["Restore all faces"])
        XCTAssertEqual(
            RestoreConfig(faceRestoreThreshold: 1000).divergences(),
            ["Skip faces > 1000px"])
    }

    func testContrastAndDeviceDivergences() {
        XCTAssertEqual(
            RestoreConfig(doContrast: false).divergences(),
            ["Auto-contrast off"])
        XCTAssertEqual(
            RestoreConfig(device: .gpu).divergences(),
            ["Device: gpu"])
    }

    func testMultipleDivergencesAreOrderedAndCombined() {
        let config = RestoreConfig(target: .scale(factor: 4), faceBlend: 1.0, device: .cpu)
        XCTAssertEqual(
            config.divergences(),
            ["Size: 4×", "Intensity 100%", "Device: cpu"])
    }
}
