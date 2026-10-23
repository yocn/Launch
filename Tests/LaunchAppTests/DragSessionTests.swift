import LaunchCore
import XCTest
@testable import LaunchApp

final class DragSessionTests: XCTestCase {
    private let app = makeLaunchItems(count: 1)[0]

    private func session(origin: DragOrigin = .grid(page: 0, index: 2)) -> DragSession {
        DragSession(item: .item(app), origin: origin)
    }

    private func confirmed(_ target: DragTarget, origin: DragOrigin = .grid(page: 0, index: 2)) -> DragSession {
        var session = session(origin: origin)
        _ = session.update(hit: .target(target), outsideFolder: false, now: 0)
        _ = session.update(hit: .target(target), outsideFolder: false, now: 1)
        return session
    }

    func testInsertTargetNeedsDwell() {
        var session = session()

        _ = session.update(hit: .target(.insert(page: 0, index: 5)), outsideFolder: false, now: 0)
        _ = session.update(hit: .target(.insert(page: 0, index: 5)), outsideFolder: false, now: 0.1)
        XCTAssertNil(session.target)

        _ = session.update(hit: .target(.insert(page: 0, index: 5)), outsideFolder: false, now: 0.16)
        XCTAssertEqual(session.target, .insert(page: 0, index: 5))
    }

    func testMergeTargetNeedsShorterDwellAndChangesRestartTimer() {
        var session = session()

        _ = session.update(hit: .target(.merge(page: 0, index: 3)), outsideFolder: false, now: 0)
        _ = session.update(hit: .target(.merge(page: 0, index: 3)), outsideFolder: false, now: 0.11)
        XCTAssertEqual(session.target, .merge(page: 0, index: 3))

        _ = session.update(hit: .target(.insert(page: 0, index: 6)), outsideFolder: false, now: 0.2)
        _ = session.update(hit: .target(.insert(page: 0, index: 6)), outsideFolder: false, now: 0.3)
        XCTAssertEqual(session.target, .merge(page: 0, index: 3))
        _ = session.update(hit: .target(.insert(page: 0, index: 6)), outsideFolder: false, now: 0.36)
        XCTAssertEqual(session.target, .insert(page: 0, index: 6))
    }

    func testEdgeTurnsAfterDwellThenRepeats() {
        var session = session()

        XCTAssertEqual(session.update(hit: .edge(.next), outsideFolder: false, now: 0), [])
        XCTAssertEqual(session.update(hit: .edge(.next), outsideFolder: false, now: 0.4), [])
        XCTAssertEqual(session.update(hit: .edge(.next), outsideFolder: false, now: 0.5), [.turnPage(.next)])
        XCTAssertEqual(session.update(hit: .edge(.next), outsideFolder: false, now: 0.9), [])
        XCTAssertEqual(session.update(hit: .edge(.next), outsideFolder: false, now: 1.3), [.turnPage(.next)])
        XCTAssertEqual(session.update(hit: .none, outsideFolder: false, now: 1.4), [])
        XCTAssertEqual(session.update(hit: .edge(.next), outsideFolder: false, now: 1.5), [])
        XCTAssertEqual(session.update(hit: .edge(.next), outsideFolder: false, now: 2.0), [.turnPage(.next)])
    }

    func testLeavingFolderAfterDwell() {
        var session = session(origin: .folder(id: "f", page: 0, index: 1))

        XCTAssertEqual(session.update(hit: .none, outsideFolder: true, now: 0), [])
        XCTAssertEqual(session.update(hit: .none, outsideFolder: true, now: 0.2), [])
        XCTAssertEqual(session.update(hit: .none, outsideFolder: true, now: 0.3), [.leaveFolder])
        XCTAssertEqual(session.preview.area, .grid)
    }

    func testPreviewKeepsSourceGapUntilTargetChosen() {
        XCTAssertEqual(
            session().preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid),
            [.item(0), .item(1), .gap, .item(3), .item(4)]
        )
    }

    func testPreviewMovesGapToInsertion() {
        XCTAssertEqual(
            confirmed(.insert(page: 0, index: 0)).preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid),
            [.gap, .item(0), .item(1), .item(3), .item(4)]
        )
    }

    func testPreviewClosesSourceGapWhenTargetIsOnAnotherPage() {
        let preview = confirmed(.insert(page: 1, index: 0)).preview

        XCTAssertEqual(preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid), [.item(0), .item(1), .item(3), .item(4)])
        XCTAssertEqual(preview.entries(page: 1, itemCount: 3, capacity: 3, in: .grid), [.gap, .item(0), .item(1)])
    }

    func testMergeKeepsSourceGap() {
        XCTAssertEqual(
            confirmed(.merge(page: 0, index: 4)).preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid),
            [.item(0), .item(1), .gap, .item(3), .item(4)]
        )
    }

    func testHitMapsDisplayedCellsToTargets() {
        let preview = session().preview
        let entries = preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid)

        XCTAssertEqual(preview.hit(for: .item(3, .leading), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 2)))
        XCTAssertEqual(preview.hit(for: .item(3, .trailing), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 3)))
        XCTAssertEqual(preview.hit(for: .item(3, .center), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.merge(page: 0, index: 3)))
        XCTAssertEqual(preview.hit(for: .item(2, .center), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 2)))
        XCTAssertEqual(preview.hit(for: .end, entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 4)))
    }

    func testFolderAreaOnlyInserts() {
        let preview = session(origin: .folder(id: "f", page: 0, index: 2)).preview
        let entries = preview.entries(page: 0, itemCount: 5, capacity: 35, in: .folder)

        XCTAssertEqual(preview.hit(for: .item(3, .center), entries: entries, itemCount: 5, page: 0, in: .folder), .target(.insert(page: 0, index: 2)))
        XCTAssertEqual(preview.hit(for: .edge(.next), entries: entries, itemCount: 5, page: 0, in: .folder), DragHit.none)
    }

    func testFolderItemNeverMerges() {
        let preview = DragSession(item: .folder(ResolvedFolder(id: "f", name: "x", items: [app])), origin: .grid(page: 0, index: 0)).preview
        let entries = preview.entries(page: 0, itemCount: 3, capacity: 35, in: .grid)

        XCTAssertEqual(preview.hit(for: .item(2, .center), entries: entries, itemCount: 3, page: 0, in: .grid), .target(.insert(page: 0, index: 1)))
    }

    func testDropTreatsUnconfirmedMergeAsInsert() {
        XCTAssertEqual(session().dropTarget(for: .target(.merge(page: 0, index: 4))), .insert(page: 0, index: 3))
        XCTAssertEqual(confirmed(.merge(page: 0, index: 4)).dropTarget(for: .target(.merge(page: 0, index: 4))), .merge(page: 0, index: 4))
        XCTAssertEqual(confirmed(.insert(page: 0, index: 1)).dropTarget(for: .none), .insert(page: 0, index: 1))
    }

    private func groupSession(target: DragTarget? = nil) -> DragSession {
        var session = DragSession(item: .item(app), origin: .grid(page: 0, index: 1), group: [0: [1, 3], 1: [0]])
        if let target {
            _ = session.update(hit: .target(target), outsideFolder: false, now: 0)
            _ = session.update(hit: .target(target), outsideFolder: false, now: 1)
        }
        return session
    }

    func testGroupPreviewRemovesPickedItemsOnEveryPage() {
        let preview = groupSession().preview

        XCTAssertEqual(preview.count, 3)
        XCTAssertEqual(preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid), [.item(0), .item(2), .item(4)])
        XCTAssertEqual(preview.entries(page: 1, itemCount: 2, capacity: 35, in: .grid), [.item(1)])
    }

    func testGroupPreviewOpensOneGapPerItemAtInsertion() {
        let preview = groupSession(target: .insert(page: 0, index: 1)).preview

        XCTAssertEqual(
            preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid),
            [.item(0), .gap, .gap, .gap, .item(2), .item(4)]
        )
        XCTAssertEqual(preview.entries(page: 0, itemCount: 5, capacity: 4, in: .grid), [.item(0), .gap, .gap, .gap])
    }

    func testGroupHitSkipsPickedItemsAndGapsKeepTarget() {
        let preview = groupSession(target: .insert(page: 0, index: 1)).preview
        let entries = preview.entries(page: 0, itemCount: 5, capacity: 35, in: .grid)

        XCTAssertEqual(preview.hit(for: .item(4, .leading), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 1)))
        XCTAssertEqual(preview.hit(for: .item(5, .trailing), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 3)))
        XCTAssertEqual(preview.hit(for: .item(3, .leading), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 1)))
        XCTAssertEqual(preview.hit(for: .item(4, .center), entries: entries, itemCount: 5, page: 0, in: .grid), .target(.merge(page: 0, index: 2)))
        XCTAssertEqual(preview.hit(for: .end, entries: entries, itemCount: 5, page: 0, in: .grid), .target(.insert(page: 0, index: 3)))
    }

    func testGroupLedByFolderCanMerge() {
        let folder = ResolvedItem.folder(ResolvedFolder(id: "f", name: "x", items: [app]))
        let preview = DragSession(item: folder, origin: .grid(page: 0, index: 0), group: [0: [0, 1]]).preview
        let entries = preview.entries(page: 0, itemCount: 4, capacity: 35, in: .grid)

        XCTAssertEqual(preview.hit(for: .item(0, .center), entries: entries, itemCount: 4, page: 0, in: .grid), .target(.merge(page: 0, index: 2)))
    }

    func testGroupDropTreatsUnconfirmedMergeAsInsert() {
        XCTAssertEqual(groupSession().dropTarget(for: .target(.merge(page: 0, index: 4))), .insert(page: 0, index: 2))
    }
}
