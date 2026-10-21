import Foundation
import LaunchCore
import XCTest
@testable import LaunchApp

// 扫描在监听器自己的串行队列上执行
private final class ScanCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

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
        let counter = ScanCounter()
        let watcher = CatalogWatcher(
            roots: [root],
            coalesceDelay: 0.1,
            scan: { _ in makeApps(count: counter.next()) },
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
    func testBurstOfRescansScansOnce() async throws {
        let counter = ScanCounter()
        let recorder = DeliveryRecorder()
        let watcher = CatalogWatcher(
            roots: [try makeTemporaryDirectory()],
            coalesceDelay: 0.2,
            scan: { _ in makeApps(count: counter.next()) },
            onChange: { recorder.record($0) }
        )
        watcher.start()
        _ = try await waitUntil { recorder.deliveries.count == 1 }

        for _ in 0 ..< 10 {
            watcher.rescan()
        }

        let delivered = try await waitUntil { recorder.deliveries.count == 2 }
        XCTAssertTrue(delivered)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(counter.count, 2)
        XCTAssertEqual(recorder.deliveries.count, 2)
        withExtendedLifetime(watcher) {}
    }

    @MainActor
    func testUnchangedScanIsNotDelivered() async throws {
        let counter = ScanCounter()
        let recorder = DeliveryRecorder()
        let watcher = CatalogWatcher(
            roots: [try makeTemporaryDirectory()],
            coalesceDelay: 0.05,
            scan: { _ in
                _ = counter.next()
                return makeApps(count: 2)
            },
            onChange: { recorder.record($0) }
        )
        watcher.start()
        _ = try await waitUntil { recorder.deliveries.count == 1 }

        watcher.rescan()

        let scanned = try await waitUntil { counter.count == 2 }
        XCTAssertTrue(scanned)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(recorder.deliveries.count, 1)
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
