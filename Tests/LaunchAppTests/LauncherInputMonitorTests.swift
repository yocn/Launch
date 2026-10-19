import AppKit
import XCTest
@testable import LaunchApp

final class LauncherInputMonitorTests: XCTestCase {
    func testScrollSampleUsesReceiptTimeForSyntheticEvents() throws {
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: -1,
            wheel2: 0,
            wheel3: 0
        ))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))

        let sample = ScrollSample(event: event)

        XCTAssertEqual(event.timestamp, 0)
        XCTAssertGreaterThan(sample.timestamp, 0)
        XCTAssertEqual(sample.deltaY, -1)
        XCTAssertFalse(sample.isPrecise)
    }
}
