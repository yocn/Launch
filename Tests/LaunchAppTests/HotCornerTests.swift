import CoreGraphics
import XCTest
@testable import LaunchApp

final class HotCornerTests: XCTestCase {
    private let screens = [
        CGRect(x: 0, y: 0, width: 1512, height: 982),
        CGRect(x: -1920, y: -98, width: 1920, height: 1080),
    ]

    func testCornerOnAnyScreen() {
        XCTAssertTrue(HotCorner.bottomLeft.contains(CGPoint(x: 0.5, y: 0.5), screens: screens))
        XCTAssertTrue(HotCorner.bottomLeft.contains(CGPoint(x: -1920, y: -98), screens: screens))
        XCTAssertTrue(HotCorner.topRight.contains(CGPoint(x: 1512, y: 982), screens: screens))
        XCTAssertTrue(HotCorner.topLeft.contains(CGPoint(x: -1919, y: 981), screens: screens))
        XCTAssertFalse(HotCorner.bottomLeft.contains(CGPoint(x: 10, y: 10), screens: screens))
        XCTAssertFalse(HotCorner.off.contains(CGPoint(x: 0, y: 0), screens: screens))
    }

    func testTriggersOnlyWhenEntering() {
        var detector = HotCornerDetector()
        detector.corner = .bottomLeft

        XCTAssertFalse(detector.update(CGPoint(x: 400, y: 400), screens: screens))
        XCTAssertTrue(detector.update(CGPoint(x: 0, y: 0), screens: screens))
        XCTAssertFalse(detector.update(CGPoint(x: 1, y: 0), screens: screens))
        XCTAssertFalse(detector.update(CGPoint(x: 50, y: 50), screens: screens))
        XCTAssertTrue(detector.update(CGPoint(x: 0, y: 1), screens: screens))
    }

    func testConflicts() {
        let dock: [String: Int] = ["wvous-br-corner": 14, "wvous-tl-corner": 1]

        XCTAssertTrue(HotCornerConflicts.system(.bottomRight) { dock[$0] })
        XCTAssertFalse(HotCornerConflicts.system(.topLeft) { dock[$0] })
        XCTAssertFalse(HotCornerConflicts.system(.bottomLeft) { dock[$0] })
        XCTAssertEqual(HotCornerConflicts.launchOSCorner(4), .bottomRight)
        XCTAssertNil(HotCornerConflicts.launchOSCorner(0))
    }
}
