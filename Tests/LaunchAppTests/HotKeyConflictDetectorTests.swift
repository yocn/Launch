import XCTest
@testable import LaunchApp

final class HotKeyConflictDetectorTests: XCTestCase {
    private let optionSpace = HotKeyCombination(keyCode: 49, modifiers: 2048)
    private let launchOSOptionSpace = #"{"carbonModifiers":2048,"carbonKeyCode":49}"#

    @MainActor
    func testConflictWhenLaunchOSRunsWithSameShortcut() {
        let detector = makeDetector(running: true, value: launchOSOptionSpace)

        XCTAssertTrue(detector.conflictsWithLaunchOS(optionSpace))
    }

    @MainActor
    func testNoConflictWhenLaunchOSIsNotRunning() {
        let detector = makeDetector(running: false, value: launchOSOptionSpace)

        XCTAssertFalse(detector.conflictsWithLaunchOS(optionSpace))
    }

    @MainActor
    func testNoConflictWhenShortcutsDiffer() {
        let detector = makeDetector(
            running: true,
            value: #"{"carbonModifiers":256,"carbonKeyCode":49}"#
        )

        XCTAssertFalse(detector.conflictsWithLaunchOS(optionSpace))
    }

    @MainActor
    func testNoConflictWhenPreferenceIsMissingOrMalformed() {
        XCTAssertFalse(makeDetector(running: true, value: nil).conflictsWithLaunchOS(optionSpace))
        XCTAssertFalse(makeDetector(running: true, value: "not json").conflictsWithLaunchOS(optionSpace))
    }

    @MainActor
    func testNoConflictWithoutOwnShortcut() {
        let detector = makeDetector(running: true, value: launchOSOptionSpace)

        XCTAssertFalse(detector.conflictsWithLaunchOS(nil))
    }

    @MainActor
    private func makeDetector(running: Bool, value: String?) -> HotKeyConflictDetector {
        HotKeyConflictDetector(
            isLaunchOSRunning: { running },
            launchOSShortcutValue: { value }
        )
    }
}
