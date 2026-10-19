import CoreGraphics
import XCTest
@testable import LaunchApp

final class PageScrollInterpreterTests: XCTestCase {
    private func trackpad(_ dx: CGFloat, _ dy: CGFloat = 0, _ phase: ScrollSample.Phase, momentum: Bool = false) -> ScrollSample {
        ScrollSample(deltaX: dx, deltaY: dy, isPrecise: true, phase: phase, isMomentum: momentum, timestamp: 0)
    }

    private func wheel(_ dy: CGFloat, at time: TimeInterval) -> ScrollSample {
        ScrollSample(deltaX: 0, deltaY: dy, isPrecise: false, phase: .none, isMomentum: false, timestamp: time)
    }

    func testTrackpadSwipeTurnsOnePagePerGesture() {
        var interpreter = PageScrollInterpreter()

        XCTAssertNil(interpreter.interpret(trackpad(-10, 0, .began)))
        XCTAssertNil(interpreter.interpret(trackpad(-20, 0, .changed)))
        XCTAssertEqual(interpreter.interpret(trackpad(-20, 0, .changed)), .next)
        XCTAssertNil(interpreter.interpret(trackpad(-60, 0, .changed)))
        XCTAssertNil(interpreter.interpret(trackpad(0, 0, .ended)))
        XCTAssertEqual(interpreter.interpret(trackpad(45, 0, .began)), .previous)
    }

    func testSmallSwipeAndMomentumDoNothing() {
        var interpreter = PageScrollInterpreter()

        XCTAssertNil(interpreter.interpret(trackpad(-30, 0, .began)))
        XCTAssertNil(interpreter.interpret(trackpad(0, 0, .ended)))
        XCTAssertNil(interpreter.interpret(trackpad(-200, 0, .none, momentum: true)))
    }

    func testVerticalTrackpadScrollUsesDominantAxis() {
        var interpreter = PageScrollInterpreter()

        XCTAssertEqual(interpreter.interpret(trackpad(5, -50, .began)), .next)
    }

    func testWheelTurnsAtMostOncePerInterval() {
        var interpreter = PageScrollInterpreter()

        XCTAssertEqual(interpreter.interpret(wheel(-1, at: 0)), .next)
        XCTAssertNil(interpreter.interpret(wheel(-1, at: 0.1)))
        XCTAssertEqual(interpreter.interpret(wheel(-1, at: 0.5)), .next)
        XCTAssertEqual(interpreter.interpret(wheel(1, at: 1.0)), .previous)
    }
}
