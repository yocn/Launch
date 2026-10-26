import AppKit
import XCTest
@testable import LaunchApp

@MainActor
final class StatusIconTrimTests: XCTestCase {
    func testTransparentMarginIsCroppedAndSoftShadowIgnored() throws {
        let size = 100
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.2))
        context.fill(CGRect(x: 5, y: 5, width: 90, height: 90))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 20, y: 30, width: 50, height: 40))
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: NSSize(width: size, height: size))

        let trimmed = try XCTUnwrap(StatusItemController.trimmingTransparentMargin(image).cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(trimmed.width, 50)
        XCTAssertEqual(trimmed.height, 40)
    }
}
