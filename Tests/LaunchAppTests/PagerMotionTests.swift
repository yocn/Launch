import CoreGraphics
import XCTest
@testable import LaunchApp

final class PagerMotionTests: XCTestCase {
    private let frame: CGFloat = 1.0 / 120

    private func run(_ motion: inout PagerMotion, page: Int, pageCount: Int = 3, seconds: CGFloat) -> [CGFloat] {
        var positions: [CGFloat] = []
        for _ in 0 ..< Int(seconds / frame) {
            motion.advance(page: page, pageCount: pageCount, pageWidth: 1000, dt: frame)
            positions.append(motion.position)
        }
        return positions
    }

    func testDragFollowsTranslationOncePerFrame() {
        var motion = PagerMotion()
        motion.updateDrag(translation: -250)

        motion.advance(page: 0, pageCount: 3, pageWidth: 1000, dt: frame)

        XCTAssertEqual(motion.position, 0.25, accuracy: 0.0001)
        XCTAssertTrue(motion.isActive)
    }

    func testDragPastFirstPageIsResisted() {
        var motion = PagerMotion()
        motion.updateDrag(translation: 200)

        motion.advance(page: 0, pageCount: 3, pageWidth: 1000, dt: frame)

        XCTAssertEqual(motion.position, -0.06, accuracy: 0.0001)
    }

    func testReleaseSettlesOnTargetWithoutOvershootAndStops() {
        var motion = PagerMotion()
        motion.updateDrag(translation: -400)
        motion.advance(page: 0, pageCount: 3, pageWidth: 1000, dt: frame)

        motion.release(velocity: 6)
        let positions = run(&motion, page: 1, seconds: 1.0)

        XCTAssertEqual(positions.last ?? 0, 1, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(positions.max() ?? 0, 1.0001)
        XCTAssertEqual(positions, positions.sorted())
        XCTAssertFalse(motion.isActive)
    }

    func testReleaseCarriesVelocityIntoFirstFrame() {
        var motion = PagerMotion()
        motion.updateDrag(translation: -400)
        motion.advance(page: 0, pageCount: 3, pageWidth: 1000, dt: frame)

        motion.release(velocity: 3)
        motion.advance(page: 1, pageCount: 3, pageWidth: 1000, dt: frame)

        XCTAssertGreaterThan(motion.position - 0.4, 3 * frame * 0.8)
    }

    func testSettleFromRestReachesNewPage() {
        var motion = PagerMotion()
        motion.settle()

        let positions = run(&motion, page: 2, seconds: 1.0)

        XCTAssertEqual(positions.last ?? 0, 2, accuracy: 0.0001)
        XCTAssertFalse(motion.isActive)
    }

    func testJumpStopsMotionImmediately() {
        var motion = PagerMotion()
        motion.updateDrag(translation: -300)

        motion.jump(to: 2)

        XCTAssertEqual(motion.position, 2)
        XCTAssertFalse(motion.isActive)
        XCTAssertNil(motion.dragTranslation)
    }
}
