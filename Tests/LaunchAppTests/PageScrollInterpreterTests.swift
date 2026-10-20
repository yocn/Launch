import CoreGraphics
import XCTest
@testable import LaunchApp

final class PageScrollInterpreterTests: XCTestCase {
    private func trackpad(
        _ dx: CGFloat,
        _ dy: CGFloat = 0,
        _ phase: ScrollSample.Phase,
        at time: TimeInterval = 0,
        momentum: Bool = false
    ) -> ScrollSample {
        ScrollSample(deltaX: dx, deltaY: dy, isPrecise: true, phase: phase, isMomentum: momentum, timestamp: time)
    }

    private func wheel(_ dy: CGFloat, at time: TimeInterval) -> ScrollSample {
        ScrollSample(deltaX: 0, deltaY: dy, isPrecise: false, phase: .none, isMomentum: false, timestamp: time)
    }

    func testHorizontalTrackpadSwipeFollowsAndPredictsRelease() {
        var interpreter = PageScrollInterpreter()

        XCTAssertEqual(interpreter.interpret(trackpad(-10, 0, .began, at: 0)), .drag(-10))
        XCTAssertEqual(interpreter.interpret(trackpad(-20, 0, .changed, at: 0.01)), .drag(-30))
        XCTAssertEqual(interpreter.interpret(trackpad(-20, 0, .changed, at: 0.02)), .drag(-50))
        guard case .endDrag(let predicted, _)? = interpreter.interpret(trackpad(0, 0, .ended, at: 0.03)) else {
            return XCTFail("expected endDrag")
        }

        XCTAssertEqual(predicted, -50 - 40 / 0.03 * 0.2, accuracy: 0.01)
    }

    func testTinySwipeAndMomentumDoNothing() {
        var interpreter = PageScrollInterpreter()

        XCTAssertNil(interpreter.interpret(trackpad(-3, 0, .began)))
        XCTAssertNil(interpreter.interpret(trackpad(0, 0, .ended)))
        XCTAssertNil(interpreter.interpret(trackpad(-200, 0, .none, momentum: true)))
    }

    func testVerticalTrackpadScrollTurnsOncePerGesture() {
        var interpreter = PageScrollInterpreter()

        XCTAssertEqual(interpreter.interpret(trackpad(5, -50, .began)), .turn(.next))
        XCTAssertNil(interpreter.interpret(trackpad(0, -80, .changed)))
        XCTAssertNil(interpreter.interpret(trackpad(0, 0, .ended)))
        XCTAssertEqual(interpreter.interpret(trackpad(0, 45, .began)), .turn(.previous))
    }

    func testPhaselessPreciseBurstsTurnOncePerBurst() {
        var interpreter = PageScrollInterpreter()
        let burst: [CGFloat] = [0, -5, -8, -8, -7, -6, -5, -4]
        var actions: [ScrollAction] = []

        for start in [0.0, 1.0] {
            for (index, deltaY) in burst.enumerated() {
                let sample = ScrollSample(
                    deltaX: 0,
                    deltaY: deltaY,
                    isPrecise: true,
                    phase: .none,
                    isMomentum: false,
                    timestamp: start + Double(index) * 0.008
                )
                if let action = interpreter.interpret(sample) {
                    actions.append(action)
                }
            }
        }

        XCTAssertEqual(actions, [.turn(.next), .turn(.next)])
    }

    func testWheelTurnsAtMostOncePerInterval() {
        var interpreter = PageScrollInterpreter()

        XCTAssertEqual(interpreter.interpret(wheel(-1, at: 0)), .turn(.next))
        XCTAssertNil(interpreter.interpret(wheel(-1, at: 0.1)))
        XCTAssertEqual(interpreter.interpret(wheel(-1, at: 0.5)), .turn(.next))
        XCTAssertEqual(interpreter.interpret(wheel(1, at: 1.0)), .turn(.previous))
    }
}
