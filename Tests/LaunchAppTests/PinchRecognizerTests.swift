import CoreGraphics
import XCTest
@testable import LaunchApp

final class PinchRecognizerTests: XCTestCase {
    // 以 (0.5, 0.5) 为中心、半径为 radius 均匀分布的 count 个触点
    private func touches(_ count: Int, radius: CGFloat) -> [CGPoint] {
        (0 ..< count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            return CGPoint(x: 0.5 + radius * cos(angle), y: 0.5 + radius * sin(angle))
        }
    }

    func testRecognizesInwardPinchOnce() {
        var recognizer = PinchRecognizer()
        recognizer.gesture = .threeFingers

        XCTAssertNil(recognizer.update(touches: touches(3, radius: 0.3)))
        XCTAssertNil(recognizer.update(touches: touches(3, radius: 0.25)))
        XCTAssertEqual(recognizer.update(touches: touches(3, radius: 0.21)), .pinchIn)
        XCTAssertNil(recognizer.update(touches: touches(3, radius: 0.1)))
        recognizer.end()
        XCTAssertNil(recognizer.update(touches: touches(3, radius: 0.3)))
        XCTAssertEqual(recognizer.update(touches: touches(3, radius: 0.12)), .pinchIn)
    }

    func testSmallDriftBelowTheThresholdDoesNotTrigger() {
        var recognizer = PinchRecognizer()
        recognizer.gesture = .fourOrFiveFingers
        XCTAssertNil(recognizer.update(touches: touches(4, radius: 0.3)))
        // 收拢到 80% 以内的手指漂移不算捏合
        XCTAssertNil(recognizer.update(touches: touches(4, radius: 0.24)))
        XCTAssertEqual(recognizer.update(touches: touches(4, radius: 0.22)), .pinchIn)
    }

    func testIgnoresSpreadingAndOtherFingerCounts() {
        var recognizer = PinchRecognizer()
        recognizer.gesture = .threeFingers
        XCTAssertNil(recognizer.update(touches: touches(3, radius: 0.15)))
        // 向外张开不会被当作向内捏合
        XCTAssertEqual(recognizer.update(touches: touches(3, radius: 0.35)), .spreadOut)
        recognizer.end()

        XCTAssertNil(recognizer.update(touches: touches(4, radius: 0.3)))
        XCTAssertNil(recognizer.update(touches: touches(4, radius: 0.1)))
    }

    func testFourOrFiveAcceptsBothAndRestartsWhenCountChanges() {
        var recognizer = PinchRecognizer()
        recognizer.gesture = .fourOrFiveFingers

        XCTAssertNil(recognizer.update(touches: touches(4, radius: 0.3)))
        XCTAssertNil(recognizer.update(touches: touches(5, radius: 0.25)))
        XCTAssertEqual(recognizer.update(touches: touches(5, radius: 0.1)), .pinchIn)
    }

    func testOffNeverFires() {
        var recognizer = PinchRecognizer()
        XCTAssertNil(recognizer.update(touches: touches(3, radius: 0.3)))
        XCTAssertNil(recognizer.update(touches: touches(3, radius: 0.05)))
    }

    func testSpreadOutNeedsTheMirrorDistanceAndFiresOnce() {
        var recognizer = PinchRecognizer()
        recognizer.gesture = .fourOrFiveFingers
        XCTAssertNil(recognizer.update(touches: touches(4, radius: 0.2)))
        // 张开到 1.33 倍以内的漂移不算
        XCTAssertNil(recognizer.update(touches: touches(4, radius: 0.25)))
        XCTAssertEqual(recognizer.update(touches: touches(4, radius: 0.28)), .spreadOut)
        XCTAssertNil(recognizer.update(touches: touches(4, radius: 0.4)))
        XCTAssertNil(recognizer.update(touches: touches(4, radius: 0.05)))
    }
}
