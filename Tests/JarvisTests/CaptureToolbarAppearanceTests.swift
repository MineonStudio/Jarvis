import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

@MainActor
final class CaptureToolbarAppearanceTests: XCTestCase {
    private func panel() -> NSPanel {
        _ = NSApplication.shared
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        return panel
    }

    func testNewFloatingWindowsUseTheAppPreference() {
        let appearance = CaptureToolbarAppearance()
        appearance.update(.dark)
        let window = panel()
        defer { window.close() }
        appearance.register(window)
        XCTAssertEqual(window.appearance?.name, .darkAqua)

        appearance.update(.light)
        let menu = panel()
        defer { menu.close() }
        appearance.register(menu)
        XCTAssertEqual(window.appearance?.name, .aqua)
        XCTAssertEqual(menu.appearance?.name, .aqua)
    }

    func testRecordingLauncherRegistersItsWindow() throws {
        let recorder = ScreenRecordingCoordinator()
        let controller = ScreenRecordingPanelController(recorder: recorder)
        defer {
            controller.hide()
            CaptureToolbarAppearance.shared.update(.system)
        }
        CaptureToolbarAppearance.shared.update(.dark)
        controller.showLauncher()
        let window = try XCTUnwrap(NSApp.windows.first {
            $0.contentView is NSHostingView<ScreenRecordingToolbar>
        })
        XCTAssertEqual(window.appearance?.name, .darkAqua)
        CaptureToolbarAppearance.shared.update(.light)
        XCTAssertEqual(window.appearance?.name, .aqua)
        CaptureToolbarAppearance.shared.update(.system)
        XCTAssertNil(window.appearance)
    }

    func testThemeChangesReachSwiftUIAndNativeOptionsInAnExistingWindow() {
        let appearance = CaptureToolbarAppearance()
        let window = panel()
        defer { window.close() }
        let hosting = NSHostingView(rootView: Text("录制").foregroundStyle(.primary))
        let options = NSButton(title: "选项", target: nil, action: nil)
        let container = NSView()
        container.addSubview(hosting)
        container.addSubview(options)
        window.contentView = container
        appearance.register(window)

        for (theme, name) in [(JarvisTheme.dark, NSAppearance.Name.darkAqua), (.light, .aqua)] {
            appearance.update(theme)
            XCTAssertEqual(hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
            XCTAssertEqual(options.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
        }

        let originalSystemAppearance = NSApp.appearance
        defer { NSApp.appearance = originalSystemAppearance }
        appearance.update(.system)
        XCTAssertNil(window.appearance, "跟随系统应清除固定外观，让 AppKit 继续响应系统切换")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSApp.appearance = NSAppearance(named: name)
            XCTAssertEqual(options.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
            XCTAssertEqual(hosting.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), name)
        }
    }
}
