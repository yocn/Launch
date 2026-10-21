import AppKit
import SwiftUI
import XCTest
@testable import LaunchApp

@MainActor
final class BackdropBlurTests: XCTestCase {
    func testLayerOnlyBlursAndSaturates() throws {
        let layer = try XCTUnwrap(BackdropBlur.makeLayer())

        XCTAssertEqual(String(describing: type(of: layer)), "CABackdropLayer")
        let filters = try XCTUnwrap(layer.filters as? [NSObject])
        XCTAssertEqual(filters.compactMap { $0.value(forKey: "name") as? String }, ["colorSaturate", "gaussianBlur"])
        XCTAssertEqual(filters[0].value(forKey: "inputAmount") as? Double, BackdropBlur.saturation)
        XCTAssertEqual(filters[1].value(forKey: "inputRadius") as? Double, BackdropBlur.radius)
        XCTAssertNil(layer.backgroundColor)
    }

    func testViewFillsBoundsWithBackdrop() throws {
        let view = BackdropBlurNSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.layout()

        let backdrop = try XCTUnwrap(view.layer?.sublayers?.first)
        XCTAssertEqual(String(describing: type(of: backdrop)), "CABackdropLayer")
        XCTAssertEqual(backdrop.frame, view.bounds)
    }
}
