import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

@MainActor
private final class DeliveryRecorder {
    private(set) var deliveries: [[CatalogApp]] = []

    func record(_ apps: [CatalogApp]) {
        deliveries.append(apps)
    }
}

final class CatalogWatcherTests: XCTestCase {
    @MainActor
    func testStartDeliversInitialScan() async throws {
        let root = try makeTemporaryDirectory()
        let recorder = DeliveryRecorder()
        let watcher = CatalogWatcher(
            roots: [root],
            scan: { _ in makeApps(count: 1) },
            onChange: { recorder.record($0) }
        )

        watcher.start()

        let delivered = try await waitUntil { !recorder.deliveries.isEmpty }
        XCTAssertTrue(delivered)
        XCTAssertEqual(recorder.deliveries.first?.count, 1)
        withExtendedLifetime(watcher) {}
    }

    @MainActor
    func testDirectoryChangeTriggersRescan() async throws {
        let root = try makeTemporaryDirectory()
        let recorder = DeliveryRecorder()
        let watcher = CatalogWatcher(
            roots: [root],
            scan: { _ in [] },
            onChange: { recorder.record($0) }
        )

        watcher.start()
        let initialDelivered = try await waitUntil { recorder.deliveries.count == 1 }
        XCTAssertTrue(initialDelivered)
        try Data().write(to: root.appending(path: "Added.app"))

        let rescanned = try await waitUntil { recorder.deliveries.count >= 2 }
        XCTAssertTrue(rescanned)
        withExtendedLifetime(watcher) {}
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: () -> Bool
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                return false
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return true
    }
}
