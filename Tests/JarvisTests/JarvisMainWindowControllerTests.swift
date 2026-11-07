import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class JarvisMainWindowControllerTests: XCTestCase {
    func testOnboardingPreservesWorkspaceFrameAndRestoresItOnCompletion() async throws {
        let suite = "jarvis-onboarding-window-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let frameStore = JarvisWindowFrameStore(defaults: defaults)
        let area = try XCTUnwrap(NSScreen.main).visibleFrame
        let size = CGSize(
            width: max(JarvisMainWindowController.minimumWindowSize.width, min(1240, area.width)),
            height: max(JarvisMainWindowController.minimumWindowSize.height, min(740, area.height))
        )
        let saved = NSRect(origin: area.origin, size: size).integral
        frameStore.save(saved)
        let measuredContent = CGSize(width: 928, height: 536)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: measuredContent),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = JarvisMainWindowController(frameStore: frameStore)
        controller.attach(to: window, isOnboardingPresented: true, onboardingContentSize: measuredContent)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, measuredContent)
        let tallerContent = CGSize(width: measuredContent.width, height: measuredContent.height + 36)
        controller.attach(to: window, isOnboardingPresented: true, onboardingContentSize: tallerContent)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, tallerContent)
        window.setFrameOrigin(window.frame.origin.applying(CGAffineTransform(translationX: 5, y: 5)))
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(frameStore.load(), saved)

        controller.attach(to: window, isOnboardingPresented: false)
        XCTAssertEqual(window.frame, saved)
        XCTAssertEqual(window.minSize, JarvisMainWindowController.minimumWindowSize)
        controller.attach(to: window, isOnboardingPresented: true, onboardingContentSize: measuredContent)
        controller.attach(to: window, isOnboardingPresented: false)
        XCTAssertEqual(window.frame, saved)
    }

    func testApplyingWindowLayoutsKeepsTheMainWindowAtNormalLevel() throws {
        // AppKit constrains frames to the real screen. Use on-screen targets
        // so this stacking-policy test also works on small CI displays.
        let area = try XCTUnwrap(NSScreen.main).visibleFrame.insetBy(dx: 20, dy: 20)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 800),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        let controller = JarvisMainWindowController()
        window.level = .floating
        controller.attach(to: window)
        XCTAssertEqual(window.level, .normal)
        for frame in [
            // AppKit rounds window frames to whole points. Odd-sized screens
            // can yield half-point test targets before the controller runs.
            NSRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height / 2).integral,
            NSRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height).integral
        ] {
            XCTAssertTrue(JarvisMainWindowController.applyWindowLayoutFrame(frame, to: window))
            XCTAssertEqual(window.level, .normal)
            XCTAssertEqual(window.frame, frame)
            XCTAssertEqual(window.alphaValue, 1)
            XCTAssertFalse(window.ignoresMouseEvents)
        }
        window.close()
    }

    func testSettingsSectionsExposeStableSidebarOrder() {
        XCTAssertEqual(
            SettingsSection.allCases,
            [.general, .appearance, .wallpaperSources, .shortcuts, .model, .permissions, .privacyCache, .diagnostics, .about]
        )
        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["常规", "外观", "壁纸源", "快捷键", "模型", "权限", "隐私与缓存", "诊断", "关于"]
        )
        XCTAssertTrue(SettingsSection.allCases.allSatisfy { !$0.icon.isEmpty })
    }

    func testMinimumWindowSizeKeepsTheMainInterfaceUsable() {
        XCTAssertEqual(
            JarvisMainWindowController.minimumWindowSize.width,
            JarvisWindowLayoutMetrics.mainWindowMinimumWidth
        )
        XCTAssertEqual(
            JarvisMainWindowController.minimumWindowSize.height,
            JarvisWindowLayoutMetrics.mainWindowMinimumHeight
        )
        XCTAssertGreaterThanOrEqual(
            JarvisMainWindowController.minimumWindowSize.width,
            JarvisMetrics.sidebarMinimumWidth
                + JarvisMetrics.shellHorizontalPadding * 2
                + JarvisWebPlatformLayoutMetrics.minimumTopBarWidth
        )
        XCTAssertLessThan(JarvisMainWindowController.minimumWindowSize.width, 1380)
        XCTAssertLessThan(JarvisMainWindowController.minimumWindowSize.height, 660)
        XCTAssertGreaterThanOrEqual(
            JarvisMainWindowController.defaultWindowSize.width,
            JarvisMainWindowController.minimumWindowSize.width
        )
        XCTAssertGreaterThanOrEqual(
            JarvisMainWindowController.defaultWindowSize.height,
            JarvisMainWindowController.minimumWindowSize.height
        )
    }

    func testLaunchWindowSizeUsesSavedFrameBeforeWindowCreation() {
        let savedFrame = NSRect(x: 120, y: 180, width: 1460, height: 820)

        XCTAssertEqual(
            JarvisMainWindowController.launchWindowSize(savedFrame: savedFrame),
            savedFrame.size
        )
    }

    func testLaunchWindowSizeFallsBackForTooSmallSavedFrame() {
        let savedFrame = NSRect(x: 120, y: 180, width: 420, height: 300)

        XCTAssertEqual(
            JarvisMainWindowController.launchWindowSize(savedFrame: savedFrame),
            JarvisMainWindowController.defaultWindowSize
        )
    }

    func testResolvedLaunchFrameKeepsAnOnScreenSavedFrame() {
        let savedFrame = NSRect(x: 120, y: 180, width: 1460, height: 820)
        let frame = JarvisMainWindowController.resolvedLaunchFrame(
            savedFrame: savedFrame,
            fallbackOrigin: CGPoint(x: 10, y: 20),
            visibleFrames: [NSRect(x: 0, y: 0, width: 2000, height: 1200)]
        )

        XCTAssertEqual(frame, savedFrame)
    }

    func testResolvedLaunchFrameDropsAnOffScreenOrigin() {
        let savedFrame = NSRect(x: 4000, y: 180, width: 1460, height: 820)
        let frame = JarvisMainWindowController.resolvedLaunchFrame(
            savedFrame: savedFrame,
            fallbackOrigin: CGPoint(x: 10, y: 20),
            visibleFrames: [NSRect(x: 0, y: 0, width: 2000, height: 1200)]
        )

        XCTAssertEqual(frame, NSRect(x: 10, y: 20, width: 1460, height: 820))
    }

    func testResolvedLaunchFrameUsesTheDefaultSizeWhenNothingUsableWasSaved() {
        let fallback = CGPoint(x: 8, y: 12)
        let missing = JarvisMainWindowController.resolvedLaunchFrame(
            savedFrame: nil,
            fallbackOrigin: fallback,
            visibleFrames: [NSRect(x: 0, y: 0, width: 2000, height: 1200)]
        )
        let tooSmall = JarvisMainWindowController.resolvedLaunchFrame(
            savedFrame: NSRect(x: 120, y: 180, width: 420, height: 300),
            fallbackOrigin: fallback,
            visibleFrames: [NSRect(x: 0, y: 0, width: 2000, height: 1200)]
        )
        let expected = NSRect(origin: fallback, size: JarvisMainWindowController.defaultWindowSize)

        XCTAssertEqual(missing, expected)
        XCTAssertEqual(tooSmall, expected)
    }

    func testApplyLaunchFrameUsesTheSavedFrameWithoutAnimation() {
        let savedFrame = NSRect(x: 40, y: 60, width: 1500, height: 900)
        let window = JarvisFrameRecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )

        JarvisMainWindowController.applyLaunchFrame(savedFrame, to: window)

        XCTAssertEqual(window.frame, savedFrame)
        XCTAssertEqual(window.animationBehavior, .none)
        XCTAssertFalse(window.animatedFrameChanges.isEmpty)
        XCTAssertFalse(window.animatedFrameChanges.contains(true))
    }

    func testAttachedWindowAllowsSystemFrameChanges() async throws {
        let suite = "jarvis-window-frame-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let frameStore = JarvisWindowFrameStore(defaults: defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 800),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = JarvisMainWindowController(frameStore: frameStore)
        defer { withExtendedLifetime(controller) {} }
        controller.attach(to: window)
        let area = try XCTUnwrap(NSScreen.main).visibleFrame.insetBy(dx: 20, dy: 20)
        let target = NSRect(
            origin: area.origin,
            size: JarvisMainWindowController.minimumWindowSize
        ).integral

        // Native zoom and tiling use programmatic frame changes, rather than
        // a live-resize mouse gesture. They must survive subsequent run loops.
        window.setFrame(target, display: false)
        // AppKit notifications can reschedule the debounced save on busy CI
        // runners. Wait for persistence, rather than assuming a fixed delay.
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            try await Task.sleep(for: .milliseconds(25))
        } while frameStore.load() != target && ContinuousClock.now < deadline

        XCTAssertEqual(window.frame, target)
        XCTAssertEqual(frameStore.load(), target)
        XCTAssertEqual(window.animationBehavior, .default)
    }

    func testStandardControlsEnableNativeWindowAndPanelActions() throws {
        for window in [
            NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true),
            NSPanel(
                contentRect: .zero, styleMask: [.titled, .nonactivatingPanel],
                backing: .buffered, defer: true
            )
        ] {
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenAuxiliary, .fullScreenDisallowsTiling]

            JarvisWindowAppearance.configureStandardControls(for: window)

            XCTAssertTrue(window.styleMask.contains([.titled, .closable, .miniaturizable, .resizable]))
            XCTAssertTrue(window.collectionBehavior.contains([.fullScreenPrimary, .fullScreenAllowsTiling]))
            XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAuxiliary))
            XCTAssertFalse(window.collectionBehavior.contains(.fullScreenDisallowsTiling))
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                let button = try XCTUnwrap(window.standardWindowButton(kind))
                XCTAssertTrue(button.isEnabled)
            }
            window.close()
        }
    }

    func testClipboardPanelMinimumWidthUsesTheSameGridMetrics() {
        XCTAssertEqual(
            JarvisWindowLayoutMetrics.clipboardPanelMinimumWidth,
            ceil(
                max(
                    HistoryGridMetrics.clipboardCardWidth,
                    HistoryGridMetrics.clipboardSearchFieldWidth
                )
                    + JarvisWindowLayoutMetrics.clipboardPanelHorizontalPadding
                    + JarvisWindowLayoutMetrics.contentSafetyMargin
            )
        )
        XCTAssertGreaterThanOrEqual(
            JarvisWindowLayoutMetrics.clipboardPanelMinimumWidth,
            HistoryGridMetrics.clipboardSearchFieldWidth
        )
        XCTAssertEqual(
            JarvisWindowLayoutMetrics.clipboardPanelMinimumHeight,
            ceil(
                JarvisWindowLayoutMetrics.clipboardPanelTopPadding
                    + JarvisWindowLayoutMetrics.clipboardPanelCompactFilterBarHeight
                    + HistoryGridMetrics.imageSpacing
                    + JarvisWindowLayoutMetrics.clipboardPanelDividerHeight
                    + HistoryGridMetrics.imageSpacing
                    + max(
                        HistoryGridMetrics.clipboardCardHeight
                            + HistoryGridMetrics.clipboardContentSpacing
                            + HistoryGridMetrics.clipboardMetadataHeight,
                        JarvisWindowLayoutMetrics.emptyStateMinimumHeight
                    )
                    + HistoryGridMetrics.imageSpacing
                    + JarvisWindowLayoutMetrics.clipboardPanelFooterHeight
                    + JarvisWindowLayoutMetrics.clipboardPanelBottomPadding
                    + JarvisWindowLayoutMetrics.contentSafetyMargin
            )
        )
    }

    func testClipboardCompactHeightsMatchTheirResponsiveHeaderRows() {
        XCTAssertEqual(
            JarvisWindowLayoutMetrics.clipboardMainCompactFilterBarHeight,
            HistoryGridMetrics.topControlHeight * 3
                + HistoryGridMetrics.clipboardFilterToGridSpacing * 2
        )
        XCTAssertEqual(
            JarvisWindowLayoutMetrics.clipboardPanelCompactFilterBarHeight,
            HistoryGridMetrics.topControlHeight * 2
                + HistoryGridMetrics.clipboardFilterToGridSpacing
        )
        XCTAssertGreaterThan(
            JarvisWindowLayoutMetrics.clipboardMainCompactFilterBarHeight,
            JarvisWindowLayoutMetrics.clipboardPanelCompactFilterBarHeight
        )
    }
}

private final class JarvisFrameRecordingWindow: NSWindow {
    private(set) var animatedFrameChanges: [Bool] = []

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        animatedFrameChanges.append(animateFlag)
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
    }
}
