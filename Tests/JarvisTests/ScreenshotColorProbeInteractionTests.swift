import AppKit
import ImageIO
@testable import Jarvis
import UniformTypeIdentifiers
import XCTest

@MainActor
final class ScreenshotColorProbeInteractionTests: XCTestCase {
    private func canvas() throws -> (NSPanel, NSView, ScreenshotEditorModel, Data) {
        _ = NSApplication.shared
        let size = CGSize(width: 100, height: 100)
        // Use explicit sRGB pixels rather than a display-profile lockFocus context.
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        try context.setFillColor(XCTUnwrap(CGColor(colorSpace: space, components: [1, 0, 0, 1])))
        context.fill(CGRect(origin: .zero, size: size))
        let cgImage = try XCTUnwrap(context.makeImage())
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let data = encoded as Data
        let image = NSImage(cgImage: cgImage, size: size)
        let editor = ScreenshotEditorModel(
            image: image, data: data, outputData: data, canvasSize: size,
            outputRect: CGRect(origin: .zero, size: size)
        )
        editor.selectTool(.eyedropper)
        let window = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        let view = NSView(frame: container.bounds)
        container.addSubview(view)
        window.contentView = container
        return (window, view, editor, data)
    }

    func testClickWhilePreparingCopiesTheRequestedPixel() async throws {
        try await checkPendingCopy(cancel: false)
    }

    func testLeavingColorPickingCancelsAPendingCopy() async throws {
        try await checkPendingCopy(cancel: true)
    }

    private func checkPendingCopy(cancel: Bool) async throws {
        let (window, view, editor, data) = try canvas()
        defer { window.close() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("unchanged", forType: .string)
        let ready = expectation(description: "Background pixel preparation completes")
        let probe = ScreenshotColorProbe(data: data, pasteboard: pasteboard) { ready.fulfill() }
        XCTAssertTrue(probe.update(in: view, editor: editor, scale: 1, copy: true, locationInWindow: CGPoint(x: 25, y: 25)))
        XCTAssertEqual(pasteboard.string(forType: .string), "unchanged")
        if cancel {
            editor.selectTool(nil)
        }
        await fulfillment(of: [ready], timeout: 3)
        XCTAssertEqual(pasteboard.string(forType: .string), cancel ? "unchanged" : "#FF0000")
    }

    func testReadyClickCopiesImmediatelyAndUsesALayerBackedOverlay() async throws {
        let (window, view, editor, data) = try canvas()
        defer { window.close() }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let ready = expectation(description: "Background pixel preparation completes")
        let probe = ScreenshotColorProbe(data: data, pasteboard: pasteboard) { ready.fulfill() }
        await fulfillment(of: [ready], timeout: 3)
        XCTAssertTrue(probe.update(in: view, editor: editor, scale: 1, copy: true, locationInWindow: CGPoint(x: 25, y: 25)))
        XCTAssertEqual(pasteboard.string(forType: .string), "#FF0000")
        let badge = try XCTUnwrap(view.superview?.subviews.first { $0 !== view })
        XCTAssertTrue(badge.wantsLayer, "移动浮层不应让下方截图画布重新绘制")
        XCTAssertFalse(badge.isHidden)
        probe.hide()
        XCTAssertTrue(badge.isHidden)
    }
}
