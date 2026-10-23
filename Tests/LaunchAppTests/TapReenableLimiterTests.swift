import XCTest
@testable import LaunchApp

final class TapReenableLimiterTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testAllowsTwoReenablesWithinThirtySeconds() {
        var limiter = TapReenableLimiter()

        XCTAssertTrue(limiter.allows(at: start))
        XCTAssertTrue(limiter.allows(at: start.addingTimeInterval(5)))
        XCTAssertFalse(limiter.allows(at: start.addingTimeInterval(10)))
        XCTAssertFalse(limiter.allows(at: start.addingTimeInterval(29)))
    }

    func testReenablesOlderThanThirtySecondsNoLongerCount() {
        var limiter = TapReenableLimiter()

        XCTAssertTrue(limiter.allows(at: start))
        XCTAssertTrue(limiter.allows(at: start.addingTimeInterval(20)))
        XCTAssertTrue(limiter.allows(at: start.addingTimeInterval(31)))
        XCTAssertFalse(limiter.allows(at: start.addingTimeInterval(40)))
    }

    func testResetClearsHistory() {
        var limiter = TapReenableLimiter()
        XCTAssertTrue(limiter.allows(at: start))
        XCTAssertTrue(limiter.allows(at: start.addingTimeInterval(1)))

        limiter.reset()

        XCTAssertTrue(limiter.allows(at: start.addingTimeInterval(2)))
    }
}
