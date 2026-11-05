import AppKit
@testable import Jarvis
import JarvisDesignSystem
import SwiftUI
import XCTest

@MainActor
final class PanelSurfaceTests: XCTestCase {
    func testContentPanelsRenderTheSameOpaqueColorsInBothThemes() throws {
        let surfaces: [(String, AnyView)] = [
            ("内容卡片", AnyView(JarvisCard { Color.clear.frame(width: 32, height: 32) })),
            ("设置面板", AnyView(SettingsContentPanel { Color.clear.frame(width: 32, height: 32) })),
            ("模块面板", AnyView(Color.clear.frame(width: 80, height: 80).jarvisModulePanel())),
            ("内嵌面板", AnyView(Color.clear.frame(width: 80, height: 80).jarvisPanelBackground(cornerRadius: 10))),
            ("文件传输共用面板", AnyView(Color.clear.frame(width: 80, height: 80)
                    .modifier(JarvisPanelBackgroundModifier(cornerRadius: 14))))
        ]
        for (scheme, expected) in [(ColorScheme.light, "F9F9F9"), (.dark, "202020")] {
            for (name, surface) in surfaces {
                let view = ZStack {
                    // An opaque fill must not pick up the underlying color.
                    Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1)
                    surface.frame(width: 80, height: 80)
                }
                .frame(width: 100, height: 100)
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                let context = try XCTUnwrap(CGContext(
                    data: nil, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
                let offset = 50 * context.bytesPerRow + 50 * 4
                let actual = String(
                    format: "%02X%02X%02X",
                    Int(pixels[offset]),
                    Int(pixels[offset + 1]),
                    Int(pixels[offset + 2])
                )
                XCTAssertEqual(actual, expected, "\(name) · \(scheme)")
                XCTAssertEqual(pixels[offset + 3], 255, name)
            }
        }
    }

    func testWindowBackplatesMatchInSwiftUIAndAppKitAcrossThemeChanges() throws {
        for (scheme, appearanceName) in [
            (ColorScheme.light, NSAppearance.Name.aqua),
            (.dark, .darkAqua),
            (.light, .aqua),
            (.dark, .darkAqua)
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            var nativeColor: NSColor?
            var originalLightColor: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                nativeColor = JarvisSurfacePalette.windowBackgroundColor.usingColorSpace(.sRGB)
                originalLightColor = NSColor.textBackgroundColor.usingColorSpace(.sRGB)
            }
            let native = try XCTUnwrap(nativeColor)
            let expected = try scheme == .dark
                ? "181818"
                : hex(XCTUnwrap(originalLightColor))
            XCTAssertEqual(hex(native), expected)
            XCTAssertEqual(native.alphaComponent, 1)

            let renderer = ImageRenderer(content: Color.jarvisBackground
                .frame(width: 20, height: 20)
                .environment(\.colorScheme, scheme))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            let context = try XCTUnwrap(CGContext(
                data: nil, width: 20, height: 20,
                bitsPerComponent: 8, bytesPerRow: 80,
                space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 20, height: 20))
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            let offset = 10 * context.bytesPerRow + 10 * 4
            let actual = String(format: "%02X%02X%02X", Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
            XCTAssertEqual(actual, expected, "窗口底板 · \(scheme)")
            XCTAssertEqual(pixels[offset + 3], 255)
        }
    }

    private func hex(_ color: NSColor) -> String {
        String(
            format: "%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}
