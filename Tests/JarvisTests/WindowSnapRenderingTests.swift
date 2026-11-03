import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class WindowSnapRenderingTests: XCTestCase {
    func testEightBlocksAreVisibleWithoutLabelsInBothAppearances() throws {
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let screen = try XCTUnwrap(NSScreen.main)
            let overlay = WindowSnapOverlayController(animationsEnabled: false)
            defer { overlay.hide() }
            overlay.update(pointer: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), on: screen)
            let geometry = try XCTUnwrap(overlay.geometry)
            for group in WindowSnapGroup.allCases {
                let view = try XCTUnwrap(overlay.optionPanels[group]?.contentView)
                view.appearance = NSAppearance(named: appearance)
                let bitmap = try render(view)
                let root = geometry.localRect(for: group)
                let hoverColor = try compositedHoverColor(in: view, bitmap: bitmap)
                for placement in group.placements {
                    let block = geometry.localRect(for: placement).offsetBy(dx: -root.minX, dy: -root.minY)
                    let color = try pixel(at: CGPoint(x: block.midX, y: block.midY), bitmap: bitmap, size: view.bounds.size)
                    assertColor(color, matches: hoverColor)
                }
                let margin = try pixel(at: CGPoint(x: view.bounds.midX, y: 4), bitmap: bitmap, size: view.bounds.size)
                XCTAssertLessThan(margin.alphaComponent, 0.1, "No layout names should be drawn below the panel")
            }
            try export(renderRow(overlay), named: name)
        }
    }

    func testOnlyTheSelectedBlockUsesAccentAndOtherGroupsStayUnchanged() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = WindowSnapOverlayController(animationsEnabled: false)
        defer { overlay.hide() }
        let center = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        overlay.update(pointer: center, on: screen)
        let geometry = try XCTUnwrap(overlay.geometry)
        for panel in overlay.optionPanels.values {
            panel.contentView?.appearance = NSAppearance(named: .aqua)
        }
        for placement in WindowSnapPlacement.allCases {
            overlay.update(pointer: center, on: screen)
            let otherGroup: WindowSnapGroup = placement.group == .leftRight ? .corners : .leftRight
            let other = try XCTUnwrap(overlay.optionPanels[otherGroup]?.contentView)
            let previous = try render(other).representation(using: .png, properties: [:])
            let initial = geometry.localRect(for: placement)
            let pointer = CGPoint(x: geometry.frame.minX + initial.midX, y: geometry.frame.minY + initial.midY)
            overlay.update(pointer: pointer, on: screen)
            let view = try XCTUnwrap(overlay.optionPanels[placement.group]?.contentView)
            let bitmap = try render(view)
            let root = geometry.localRect(for: placement.group)
            let hoverColor = try compositedHoverColor(in: view, bitmap: bitmap)
            for item in placement.group.placements {
                let block = geometry.localRect(for: item).offsetBy(dx: -root.minX, dy: -root.minY)
                let color = try pixel(at: CGPoint(x: block.midX, y: block.midY), bitmap: bitmap, size: view.bounds.size)
                assertColor(color, matches: item == placement ? NSColor.controlAccentColor : hoverColor)
            }
            XCTAssertEqual(previous, try render(other).representation(using: .png, properties: [:]))
            XCTAssertEqual(overlay.drop(at: pointer)?.0, placement)
        }
        try export(renderRow(overlay), named: "selected")
    }

    private func pixel(at point: CGPoint, bitmap: NSBitmapImageRep, size: CGSize) throws -> NSColor {
        let x = Int(point.x / size.width * CGFloat(bitmap.pixelsWide))
        let y = Int((size.height - point.y) / size.height * CGFloat(bitmap.pixelsHigh))
        return try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }

    private func compositedHoverColor(in view: NSView, bitmap: NSBitmapImageRep) throws -> NSColor {
        let surface = WindowSnapBarGeometry.surfaceRect(in: view.bounds)
        let backdrop = try pixel(at: CGPoint(x: surface.minX + 4, y: surface.midY), bitmap: bitmap, size: view.bounds.size)
        var foreground: NSColor?
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            foreground = JarvisMotion.hoverPillNSColor.usingColorSpace(.sRGB)
        }
        let tint = try XCTUnwrap(foreground)
        let alpha = tint.alphaComponent
        let backdropWeight = backdrop.alphaComponent * (1 - alpha)
        let outputAlpha = alpha + backdropWeight
        return NSColor(
            srgbRed: (tint.redComponent * alpha + backdrop.redComponent * backdropWeight) / outputAlpha,
            green: (tint.greenComponent * alpha + backdrop.greenComponent * backdropWeight) / outputAlpha,
            blue: (tint.blueComponent * alpha + backdrop.blueComponent * backdropWeight) / outputAlpha,
            alpha: outputAlpha
        )
    }

    private func assertColor(_ color: NSColor, matches expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let expected = expected.usingColorSpace(.sRGB) else { return XCTFail("Color has no RGB components", file: file, line: line) }
        XCTAssertEqual(color.redComponent, expected.redComponent, accuracy: 0.03, file: file, line: line)
        XCTAssertEqual(color.greenComponent, expected.greenComponent, accuracy: 0.03, file: file, line: line)
        XCTAssertEqual(color.blueComponent, expected.blueComponent, accuracy: 0.03, file: file, line: line)
    }

    /// Contact sheet of the actual independent panel renders, with transparent gaps.
    private func renderRow(_ overlay: WindowSnapOverlayController) throws -> NSBitmapImageRep {
        let geometry = try XCTUnwrap(overlay.geometry)
        let size = geometry.frame.size
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: 2, y: 2)
        for group in WindowSnapGroup.allCases {
            let view = try XCTUnwrap(overlay.optionPanels[group]?.contentView)
            let image = NSImage(size: view.bounds.size)
            try image.addRepresentation(render(view))
            image.draw(in: geometry.localRect(for: group))
        }
        return bitmap
    }

    private func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func export(_ bitmap: NSBitmapImageRep, named name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["JARVIS_SNAP_RENDER_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent("window-layout-\(name).png"))
    }
}
