import AppKit
import XCTest
@testable import LaunchApp

final class OptionHoldTrackerTests: XCTestCase {
    func testOptionAloneBeginsAndReleaseEnds() {
        var tracker = OptionHoldTracker()
        tracker.reset(optionDown: false)

        XCTAssertEqual(tracker.update([.option]), .began)
        XCTAssertNil(tracker.update([.option]))
        XCTAssertEqual(tracker.update([]), .ended)
    }

    func testOptionHeldWhenOpeningMustBeReleasedFirst() {
        var tracker = OptionHoldTracker()
        tracker.reset(optionDown: true)

        XCTAssertNil(tracker.update([.option, .shift]))
        XCTAssertNil(tracker.update([]))
        XCTAssertEqual(tracker.update([.option]), .began)
    }

    func testOtherModifiersDoNotBeginAndEndHold() {
        var tracker = OptionHoldTracker()
        tracker.reset(optionDown: false)

        XCTAssertNil(tracker.update([.option, .command]))
        XCTAssertNil(tracker.update([]))
        XCTAssertEqual(tracker.update([.option]), .began)
        XCTAssertEqual(tracker.update([.option, .shift]), .ended)
    }

    func testDeviceFlagsAreIgnored() {
        var tracker = OptionHoldTracker()
        tracker.reset(optionDown: false)

        XCTAssertEqual(tracker.update([.option, .capsLock, .function]), .began)
    }
}
