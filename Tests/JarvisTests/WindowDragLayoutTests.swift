import AppKit
@testable import Jarvis
import XCTest

final class WindowSnapGeometryTests: XCTestCase {
    func testEightPlacementsRespectTheChosenDisplayAndUsableArea() {
        let screen = CGRect(x: -1920, y: 1150, width: 1920, height: 1000)
        XCTAssertEqual(WindowSnapPlacement.halfLeft.frame(in: screen), CGRect(x: -1920, y: 1150, width: 960, height: 1000))
        XCTAssertEqual(WindowSnapPlacement.halfTop.frame(in: screen), CGRect(x: -1920, y: 1650, width: 1920, height: 500))
        XCTAssertEqual(WindowSnapPlacement.lowerRight.frame(in: screen), CGRect(x: -960, y: 1150, width: 960, height: 500))
        let corners: [WindowSnapPlacement] = [.upperLeft, .upperRight, .lowerLeft, .lowerRight]
        XCTAssertEqual(corners.map { $0.frame(in: screen) }.reduce(CGRect.null) { $0.union($1) }, screen)
        for placement in WindowSnapPlacement.allCases {
            XCTAssertTrue(screen.contains(placement.frame(in: screen)))
        }
    }

    func testHitTestingUsesPointerInsideCardAndRejectsGapsAndOutside() {
        let bar = WindowSnapBarGeometry(visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1050))
        for placement in WindowSnapPlacement.allCases {
            let card = bar.localRect(for: placement).offsetBy(dx: bar.frame.minX, dy: bar.frame.minY)
            XCTAssertEqual(bar.placement(at: CGPoint(x: card.midX, y: card.midY)), placement)
        }
        XCTAssertNil(bar.placement(at: CGPoint(x: bar.frame.minX - 1, y: bar.frame.midY)))
        XCTAssertNil(bar.placement(at: CGPoint(x: bar.frame.midX, y: bar.frame.maxY + 1)))
        let left = bar.localRect(for: WindowSnapGroup.leftRight)
        XCTAssertNil(bar.placement(at: CGPoint(x: bar.frame.minX + left.maxX + 4, y: bar.frame.minY + left.midY)))
    }

    func testThreeGroupsShareOneRowAndContainEightLayouts() {
        let bar = WindowSnapBarGeometry(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        let cards = WindowSnapGroup.allCases.map { bar.localRect(for: $0) }
        XCTAssertEqual(cards.count, 3)
        XCTAssertEqual(WindowSnapPlacement.allCases.count, 8)
        XCTAssertEqual(WindowSnapGroup.allCases.map(\.placements.count), [2, 2, 4])
        XCTAssertEqual(Set(cards.map(\.minY)).count, 1)
        for (left, right) in zip(cards, cards.dropFirst()) {
            XCTAssertLessThan(left.maxX, right.minX)
        }
    }

    func testBarFitsNarrowDisplaysAndAllCardsRemainReachable() {
        let visible = CGRect(x: 1440, y: -100, width: 360, height: 800)
        let bar = WindowSnapBarGeometry(visibleFrame: visible)
        XCTAssertTrue(visible.contains(bar.frame))
        for placement in WindowSnapPlacement.allCases {
            XCTAssertTrue(CGRect(origin: .zero, size: bar.frame.size).contains(bar.localRect(for: placement)))
        }
    }

    func testCoordinateConversionUsesPrimaryTopForVerticallyStackedDisplays() {
        let upperDisplayWindow = CGRect(x: 200, y: -900, width: 800, height: 600)
        let appKit = WindowLayoutCoordinates.flipped(upperDisplayWindow, primaryDisplayTop: 1080)
        XCTAssertEqual(appKit, CGRect(x: 200, y: 1380, width: 800, height: 600))
        XCTAssertEqual(WindowLayoutCoordinates.flipped(appKit, primaryDisplayTop: 1080), upperDisplayWindow)
    }

    func testPanelMarginsAndDividersAreNotDropTargets() {
        let geometry = WindowSnapBarGeometry(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        for group in WindowSnapGroup.allCases {
            let root = geometry.localRect(for: group)
            let surface = WindowSnapBarGeometry.surfaceRect(in: root)
            let margin = CGPoint(x: geometry.frame.minX + root.midX, y: geometry.frame.minY + root.minY + 4)
            XCTAssertNil(geometry.group(at: margin))
            XCTAssertNil(geometry.placement(at: margin))
            let panel = surface
            let divider = CGPoint(x: geometry.frame.minX + panel.midX, y: geometry.frame.minY + panel.midY)
            XCTAssertEqual(geometry.group(at: divider), group)
            XCTAssertNil(geometry.placement(at: divider))
        }
    }

    func testFixedSizeWindowsKeepTheirSizeAndAlignWithinTheDesktop() {
        let desktop = CGRect(x: -1920, y: 100, width: 1920, height: 1000)
        let size = CGSize(width: 1100, height: 700)
        for placement in WindowSnapPlacement.allCases {
            let frame = placement.frame(preserving: size, in: desktop)
            XCTAssertEqual(frame.size, size)
            XCTAssertTrue(desktop.contains(frame))
        }
        XCTAssertEqual(WindowSnapPlacement.upperRight.frame(preserving: size, in: desktop).maxX, desktop.maxX)
        XCTAssertEqual(WindowSnapPlacement.upperRight.frame(preserving: size, in: desktop).maxY, desktop.maxY)
    }
}

final class WindowDragMotionTests: XCTestCase {
    private let initial = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testDraggingContentWithoutMovingWindowDoesNotArmLayout() {
        var motion = WindowDragMotion(pointer: CGPoint(x: 300, y: 400), frame: initial)
        motion.observe(pointer: CGPoint(x: 700, y: 850), frame: initial)
        XCTAssertFalse(motion.isMoving)
    }

    func testWindowFollowingPointerArmsLayoutAndIgnoresTinyJitter() {
        var motion = WindowDragMotion(pointer: CGPoint(x: 300, y: 680), frame: initial)
        motion.observe(pointer: CGPoint(x: 302, y: 681), frame: initial.offsetBy(dx: 2, dy: 1))
        XCTAssertFalse(motion.isMoving)
        motion.observe(pointer: CGPoint(x: 320, y: 720), frame: initial.offsetBy(dx: 20, dy: 40))
        XCTAssertTrue(motion.isMoving)
    }

    func testUnrelatedWindowMotionDoesNotArmLayout() {
        var motion = WindowDragMotion(pointer: CGPoint(x: 300, y: 680), frame: initial)
        motion.observe(pointer: CGPoint(x: 300, y: 740), frame: initial.offsetBy(dx: 300, dy: -100))
        XCTAssertFalse(motion.isMoving)
    }

    func testResizingIsRejectedEvenIfWindowOriginChanges() {
        var motion = WindowDragMotion(pointer: CGPoint(x: 110, y: 400), frame: initial)
        motion.observe(pointer: CGPoint(x: 140, y: 400), frame: CGRect(x: 130, y: 100, width: 770, height: 600))
        XCTAssertTrue(motion.isRejected)
        XCTAssertFalse(motion.isMoving)
    }

    func testNativeTilingRestoreCanRebaseOnceBeforeNormalMovement() {
        var motion = WindowDragMotion(pointer: CGPoint(x: 300, y: 680), frame: initial)
        let restored = CGRect(x: 140, y: 130, width: 600, height: 450)
        motion.observe(pointer: CGPoint(x: 340, y: 710), frame: restored)
        XCTAssertFalse(motion.isRejected)
        motion.observe(pointer: CGPoint(x: 360, y: 730), frame: restored.offsetBy(dx: 20, dy: 20))
        XCTAssertTrue(motion.isMoving)
    }
}

@MainActor
final class WindowSnapIntegrationTests: XCTestCase {
    func testFadingOutImmediatelyDisarmsDropAndEventuallyHidesAllOptions() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = WindowSnapOverlayController()
        defer { overlay.hide() }
        overlay.update(pointer: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), on: screen)
        let geometry = try XCTUnwrap(overlay.geometry)
        let card = geometry.localRect(for: .halfLeft)
        let pointer = CGPoint(x: geometry.frame.minX + card.midX, y: geometry.frame.minY + card.midY)
        overlay.update(pointer: pointer, on: screen)
        overlay.hide(animated: true)
        XCTAssertNil(overlay.drop(at: pointer))
        XCTAssertNil(overlay.selection)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(overlay.optionPanels.values.allSatisfy { !$0.isVisible })
    }

    func testNewDragInterruptsDismissalWithoutHidingOrMovingItsTargets() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = WindowSnapOverlayController()
        defer { overlay.hide() }
        let center = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        overlay.update(pointer: center, on: screen)
        let geometry = try XCTUnwrap(overlay.geometry)
        let frames = overlay.optionPanels.mapValues(\.frame)
        overlay.hide(animated: true)
        try await Task.sleep(for: .milliseconds(30))
        let card = geometry.localRect(for: .upperRight)
        let pointer = CGPoint(x: geometry.frame.minX + card.midX, y: geometry.frame.minY + card.midY)
        overlay.update(pointer: pointer, on: screen)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(overlay.selection, .upperRight)
        XCTAssertEqual(overlay.drop(at: pointer)?.0, .upperRight)
        XCTAssertEqual(overlay.optionPanels.mapValues(\.frame), frames)
        for panel in overlay.optionPanels.values {
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(panel.alphaValue, 1, accuracy: 0.01)
        }
    }

    func testSelectionFeedbackOnlyOccursWhenEnteringAnOption() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        var feedback: [WindowSnapPlacement] = []
        let overlay = WindowSnapOverlayController(animationsEnabled: false) { feedback.append($0) }
        defer { overlay.hide() }
        overlay.update(pointer: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), on: screen)
        let geometry = try XCTUnwrap(overlay.geometry)
        for placement in WindowSnapPlacement.allCases {
            let card = geometry.localRect(for: placement)
            let pointer = CGPoint(x: geometry.frame.minX + card.midX, y: geometry.frame.minY + card.midY)
            for _ in 0 ..< 10 {
                overlay.update(pointer: pointer, on: screen)
            }
            XCTAssertEqual(overlay.drop(at: pointer)?.0, placement)
        }
        overlay.hide()
        XCTAssertEqual(feedback, WindowSnapPlacement.allCases)
    }

    func testDraggingAnywhereShowsTheBarAndKeepsItVisibleAwayFromTheTop() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = WindowSnapOverlayController()
        defer { overlay.hide() }
        let center = CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY)
        overlay.update(pointer: center, on: screen)
        let panel = try XCTUnwrap(overlay.optionPanels[.leftRight])
        XCTAssertTrue(panel.isVisible)
        XCTAssertNil(overlay.selection)
        XCTAssertNil(overlay.drop(at: center))
        overlay.update(pointer: CGPoint(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.minY + 20), on: screen)
        XCTAssertTrue(panel.isVisible)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    func testOverlayPassesMouseThroughAndDoesNotBecomeKey() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = WindowSnapOverlayController()
        defer { overlay.hide() }
        overlay.update(pointer: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 5), on: screen)
        let panel = try XCTUnwrap(overlay.optionPanels[.leftRight])
        let geometry = try XCTUnwrap(overlay.geometry)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        let rect = geometry.localRect(for: .halfRight).offsetBy(dx: geometry.frame.minX, dy: geometry.frame.minY)
        let pointer = CGPoint(x: rect.midX, y: rect.midY)
        overlay.update(pointer: pointer, on: screen)
        XCTAssertEqual(overlay.selection, .halfRight)
        XCTAssertEqual(overlay.drop(at: pointer)?.0, .halfRight)
        XCTAssertEqual(overlay.optionPanels.count, 3)
        for option in overlay.optionPanels.values {
            XCTAssertTrue(option.ignoresMouseEvents)
            XCTAssertFalse(option.canBecomeKey)
            XCTAssertFalse(option.canBecomeMain)
        }
        XCTAssertNil(overlay.drop(at: CGPoint(x: geometry.frame.minX - 1, y: geometry.frame.midY)))
        overlay.hide()
        XCTAssertNil(overlay.drop(at: pointer))
        XCTAssertFalse(panel.isVisible)
    }

    func testThreePanelsKeepTheirSizeWhileSelectingAnyLayout() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let overlay = WindowSnapOverlayController(animationsEnabled: false)
        defer { overlay.hide() }
        overlay.update(pointer: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), on: screen)
        let geometry = try XCTUnwrap(overlay.geometry)
        XCTAssertEqual(Set(overlay.optionPanels.values.map(ObjectIdentifier.init)).count, 3)
        for placement in WindowSnapPlacement.allCases {
            let group = placement.group
            let panel = try XCTUnwrap(overlay.optionPanels[group])
            let expected = geometry.localRect(for: group).offsetBy(dx: geometry.frame.minX, dy: geometry.frame.minY)
            XCTAssertEqual(panel.frame, expected)
            XCTAssertNil(panel.parent)
            XCTAssertNil(panel.sheetParent)
            let view = try XCTUnwrap(panel.contentView as? WindowSnapOptionView)
            let block = geometry.localRect(for: placement)
            let pointer = CGPoint(x: geometry.frame.minX + block.midX, y: geometry.frame.minY + block.midY)
            overlay.update(pointer: pointer, on: screen)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(overlay.selection, placement)
            XCTAssertEqual(overlay.drop(at: pointer)?.0, placement)
            XCTAssertEqual(view.selectedPlacement, placement)
            let surface = try XCTUnwrap(view.subviews.first)
            XCTAssertEqual(surface.frame, WindowSnapBarGeometry.surfaceRect(in: view.bounds))
            XCTAssertEqual(panel.frame, expected, "Selecting a layout must not resize or move any panel")
            XCTAssertTrue(overlay.optionPanels.values.allSatisfy(\.isVisible))
            XCTAssertEqual(overlay.optionPanels.count, 3)
        }
        overlay.update(pointer: CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY), on: screen)
        XCTAssertNil(overlay.selection)
        for panel in overlay.optionPanels.values {
            let view = try XCTUnwrap(panel.contentView as? WindowSnapOptionView)
            view.layoutSubtreeIfNeeded()
            XCTAssertNil(view.selectedPlacement)
            XCTAssertEqual(view.subviews.first?.frame, WindowSnapBarGeometry.surfaceRect(in: view.bounds))
        }
        overlay.hide()
        XCTAssertTrue(overlay.optionPanels.values.allSatisfy { !$0.isVisible })
    }

    func testDropKeepsOriginalWindowWhenAnotherWindowBecomesKey() throws {
        let original = makeWindow()
        let other = makeWindow()
        defer { original.close(); other.close() }
        original.makeKeyAndOrderFront(nil)
        let point = CGPoint(x: original.frame.midX, y: original.frame.maxY - 15)
        let target = try XCTUnwrap(WindowDragTarget.capture(at: point, eventWindow: original))
        other.makeKeyAndOrderFront(nil)
        let otherFrame = other.frame
        let screen = try XCTUnwrap(NSScreen.main)
        var feedback: [String] = []
        let controller = WindowLayoutController { feedback.append($0) }

        controller.apply(.halfRight, to: target, on: screen)

        XCTAssertEqual(original.frame, WindowSnapPlacement.halfRight.frame(in: WindowLayoutScreenArea.visibleFrame(for: screen)))
        XCTAssertEqual(other.frame, otherFrame)
        XCTAssertTrue(feedback.isEmpty, "Successful window layout should not show a toast")
    }

    func testResizeEdgesAndLayoutOverlaysCannotBecomeDragTargets() {
        let window = makeWindow()
        defer { window.close() }
        window.orderFront(nil)
        XCTAssertNil(WindowDragTarget.capture(at: CGPoint(x: window.frame.minX + 1, y: window.frame.midY), eventWindow: window))
        let panel = NSPanel(contentRect: window.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        panel.identifier = NSUserInterfaceItemIdentifier("Jarvis.WindowSnapOption.Test")
        panel.orderFrontRegardless()
        XCTAssertNil(WindowDragTarget.capture(at: CGPoint(x: panel.frame.midX, y: panel.frame.maxY - 15), eventWindow: panel))
    }

    func testFloatingPanelCanBeCapturedAndLaidOut() throws {
        let panel = NSPanel(
            contentRect: CGRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .resizable, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.orderFrontRegardless()
        defer { panel.close() }
        let pointer = CGPoint(x: panel.frame.midX, y: panel.frame.maxY - 15)
        let target = try XCTUnwrap(WindowDragTarget.capture(at: pointer, eventWindow: panel))
        XCTAssertTrue(target.nativeWindow === panel)
        let screen = try XCTUnwrap(NSScreen.main)
        WindowLayoutController { _ in }.apply(.upperRight, to: target, on: screen)
        let expected = WindowSnapPlacement.upperRight.frame(in: WindowLayoutScreenArea.visibleFrame(for: screen))
        XCTAssertEqual(panel.frame.minX, expected.minX, accuracy: 1)
        XCTAssertEqual(panel.frame.minY, expected.minY, accuracy: 1)
        XCTAssertEqual(panel.frame.width, expected.width, accuracy: 1)
        XCTAssertEqual(panel.frame.height, expected.height, accuracy: 1)
    }

    func testNonactivatingPanelCanBeFoundWithoutAnEventWindow() async throws {
        let panel = NSPanel(
            contentRect: CGRect(x: 160, y: 180, width: 500, height: 350),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.orderFrontRegardless()
        defer { panel.close() }
        try await Task.sleep(for: .milliseconds(150))
        let pointer = CGPoint(x: panel.frame.midX, y: panel.frame.maxY - 15)
        let hitNumber = NSWindow.windowNumber(at: pointer, belowWindowWithWindowNumber: 0)
        let flipped = CGPoint(x: pointer.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - pointer.y)
        let flippedHit = NSWindow.windowNumber(at: flipped, belowWindowWithWindowNumber: 0)
        let target = try XCTUnwrap(
            WindowDragTarget.capture(at: pointer, eventWindow: nil),
            "hit=\(hitNumber), flipped=\(flippedHit), panel=\(panel.windowNumber), frame=\(panel.frame)"
        )
        XCTAssertTrue(target.nativeWindow === panel)
    }

    func testWindowWithoutResizableStyleCanStillBeCaptured() throws {
        let window = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        defer { window.close() }
        let target = try XCTUnwrap(WindowDragTarget.capture(
            at: CGPoint(x: window.frame.midX, y: window.frame.maxY - 15), eventWindow: window
        ))
        XCTAssertTrue(target.nativeWindow === window)
    }

    func testPreferenceDefaultsOffAndPreservesExplicitChoices() throws {
        let suite = "WindowDragLayoutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(WindowDragLayoutPreference.load(from: defaults))
        for choice in [true, false] {
            defaults.set(choice, forKey: WindowDragLayoutPreference.key)
            XCTAssertEqual(WindowDragLayoutPreference.load(from: defaults), choice)
        }
    }
}
