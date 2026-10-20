import XCTest
@testable import LaunchApp

final class AppActionsTests: XCTestCase {
    func testInfoScriptEscapesPath() {
        let script = AppActions.infoScript(path: #"/Applications/A "B"\C.app"#)

        XCTAssertTrue(script.contains(#"open information window of (POSIX file "/Applications/A \"B\"\\C.app" as alias)"#))
        XCTAssertTrue(script.contains(#"tell application "Finder""#))
    }
}
