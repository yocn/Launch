import XCTest
@testable import LaunchApp

@MainActor
private final class ManualScheduler {
    var delays: [TimeInterval] = []
    var actions: [@MainActor @Sendable () -> Void] = []

    func run() {
        let current = actions
        actions = []
        current.forEach { $0() }
    }
}

@MainActor
private final class Counter {
    var values: [String] = []
}

@MainActor
final class DelayedDismissalTests: XCTestCase {
    private func make(_ scheduler: ManualScheduler) -> DelayedDismissal {
        DelayedDismissal { delay, action in
            scheduler.delays.append(delay)
            scheduler.actions.append(action)
        }
    }

    func testRunsActionAfterDelay() {
        let scheduler = ManualScheduler()
        let counter = Counter()
        let dismissal = make(scheduler)

        dismissal.start(after: 0.22) { counter.values.append("hide") }
        XCTAssertTrue(dismissal.isPending)
        scheduler.run()

        XCTAssertEqual(counter.values, ["hide"])
        XCTAssertFalse(dismissal.isPending)
        XCTAssertEqual(scheduler.delays, [0.22])
    }

    func testCancelPreventsAction() {
        let scheduler = ManualScheduler()
        let counter = Counter()
        let dismissal = make(scheduler)

        dismissal.start(after: 0.22) { counter.values.append("hide") }
        dismissal.cancel()
        scheduler.run()

        XCTAssertEqual(counter.values, [])
        XCTAssertFalse(dismissal.isPending)
    }

    func testRestartRunsOnlyLatest() {
        let scheduler = ManualScheduler()
        let counter = Counter()
        let dismissal = make(scheduler)

        dismissal.start(after: 0.22) { counter.values.append("first") }
        dismissal.start(after: 0.22) { counter.values.append("second") }
        scheduler.run()

        XCTAssertEqual(counter.values, ["second"])
    }
}
