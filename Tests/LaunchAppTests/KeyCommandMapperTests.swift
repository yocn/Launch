import AppKit
import XCTest
@testable import LaunchApp

final class KeyCommandMapperTests: XCTestCase {
    private let arrowFlags: NSEvent.ModifierFlags = [.numericPad, .function]

    private func map(_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags = [], composing: Bool = false) -> LauncherCommand? {
        KeyCommandMapper.command(keyCode: keyCode, modifiers: modifiers, isComposingText: composing)
    }

    func testArrowsMoveSelectionEvenWithDeviceFlags() {
        XCTAssertEqual(map(123, arrowFlags), .move(.left))
        XCTAssertEqual(map(124, arrowFlags), .move(.right))
        XCTAssertEqual(map(125, arrowFlags), .move(.down))
        XCTAssertEqual(map(126, arrowFlags), .move(.up))
    }

    func testReturnAndEnterActivate() {
        XCTAssertEqual(map(36), .activate)
        XCTAssertEqual(map(76, [.numericPad]), .activate)
    }

    func testCommandArrowsTurnPages() {
        XCTAssertEqual(map(123, arrowFlags.union(.command)), .previousPage)
        XCTAssertEqual(map(124, arrowFlags.union(.command)), .nextPage)
        XCTAssertNil(map(126, arrowFlags.union(.command)))
    }

    func testComposingTextPassesKeysToInputMethod() {
        XCTAssertNil(map(124, arrowFlags, composing: true))
        XCTAssertNil(map(36, composing: true))
    }

    func testOtherModifiersAndKeysPassThrough() {
        XCTAssertNil(map(124, arrowFlags.union(.shift)))
        XCTAssertNil(map(124, arrowFlags.union(.option)))
        XCTAssertNil(map(0))
    }

    func testCommandZUndoesLayoutOnlyWhenAllowed() {
        XCTAssertEqual(
            KeyCommandMapper.command(keyCode: 6, modifiers: [.command], isComposingText: false, canUndoLayout: true),
            .undoLayoutEdit
        )
        XCTAssertNil(KeyCommandMapper.command(keyCode: 6, modifiers: [.command], isComposingText: false, canUndoLayout: false))
        XCTAssertNil(KeyCommandMapper.command(keyCode: 6, modifiers: [.command], isComposingText: true, canUndoLayout: true))
    }
}
