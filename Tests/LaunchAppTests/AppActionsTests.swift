import XCTest
@testable import LaunchApp

final class AppActionsTests: XCTestCase {
    func testInfoScriptEscapesPath() {
        let script = AppActions.infoScript(path: #"/Applications/A "B"\C.app"#)

        XCTAssertTrue(script.contains(#"open information window of (POSIX file "/Applications/A \"B\"\\C.app" as alias)"#))
        XCTAssertTrue(script.contains(#"tell application "Finder""#))
    }

    func testRecognizesMissingAutomationPermission() {
        XCTAssertTrue(AppActions.isNotPermitted("0:120: execution error: Not authorized to send Apple events to Finder. (-1743)"))
        XCTAssertFalse(AppActions.isNotPermitted("0:120: execution error: Finder got an error: AppleEvent timed out. (-1712)"))
    }
}
