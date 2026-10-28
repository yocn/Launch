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

        XCTAssertFalse(recognizer.update(touches: touches(3, radius: 0.3)))
        XCTAssertFalse(recognizer.update(touches: touches(3, radius: 0.25)))
        XCTAssertTrue(recognizer.update(touches: touches(3, radius: 0.21)))
        XCTAssertFalse(recognizer.update(touches: touches(3, radius: 0.1)))
        recognizer.end()
        XCTAssertFalse(recognizer.update(touches: touches(3, radius: 0.3)))
        XCTAssertTrue(recognizer.update(touches: touches(3, radius: 0.12)))
    }

    func testSmallDriftBelowTheThresholdDoesNotTrigger() {
        var recognizer = PinchRecognizer()
        recognizer.gesture = .fourOrFiveFingers
        XCTAssertFalse(recognizer.update(touches: touches(4, radius: 0.3)))
        // 收拢到 80% 以内的手指漂移不算捏合
        XCTAssertFalse(recognizer.update(touches: touches(4, radius: 0.24)))
        XCTAssertTrue(recognizer.update(touches: touches(4, radius: 0.22)))
    }

    func testIgnoresSpreadingAndOtherFingerCounts() {
        var recognizer = PinchRecognizer()
        recognizer.gesture = .threeFingers
        XCTAssertFalse(recognizer.update(touches: touches(3, radius: 0.15)))
        XCTAssertFalse(recognizer.update(touches: touches(3, radius: 0.35)))
        recognizer.end()

        XCTAssertFalse(recognizer.update(touches: touches(4, radius: 0.3)))
        XCTAssertFalse(recognizer.update(touches: touches(4, radius: 0.1)))
    }

    func testFourOrFiveAcceptsBothAndRestartsWhenCountChanges() {
        var recognizer = PinchRecognizer()
        recognizer.gesture = .fourOrFiveFingers

        XCTAssertFalse(recognizer.update(touches: touches(4, radius: 0.3)))
        XCTAssertFalse(recognizer.update(touches: touches(5, radius: 0.25)))
        XCTAssertTrue(recognizer.update(touches: touches(5, radius: 0.1)))
    }

    func testOffNeverFires() {
        var recognizer = PinchRecognizer()
        XCTAssertFalse(recognizer.update(touches: touches(3, radius: 0.3)))
        XCTAssertFalse(recognizer.update(touches: touches(3, radius: 0.05)))
    }
}
