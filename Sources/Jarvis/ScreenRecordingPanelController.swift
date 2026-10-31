import AppKit
import SwiftUI

@MainActor
final class ScreenRecordingPanelController {
    private let recorder: ScreenRecordingCoordinator
    private var panel: NSPanel?
    private var savedLauncherFrame: CGRect?
    var launcherFrame: CGRect? {
        guard let panel else { return savedLauncherFrame }
        if let container = panel.contentView as? ScreenRecordingOptionsContainer {
            return panel.convertToScreen(container.toolbar.frame)
        }
        return panel.frame
    }

    private var regionBorder: NSPanel?
    private var borderTrackingTask: Task<Void, Never>?
    private var modeHint: NSPanel?
    private var modeHintTask: Task<Void, Never>?

    init(recorder: ScreenRecordingCoordinator) {
        self.recorder = recorder
    }

    private var launcherLevel: NSWindow.Level {
        recorder.selectingTarget ? NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) : .floating
    }

    func showLauncher() {
        if let panel {
            panel.level = launcherLevel
            panel.orderFrontRegardless()
            panel.makeKey()
            updateRegionBorder()
            return
        }
        let panel = ScreenRecordingLauncherPanel(
            contentRect: CGRect(x: 0, y: 0, width: ScreenRecordingToolbarLayout.width, height: ScreenRecordingToolbarLayout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onCancel = { [weak recorder] in recorder?.dismissToolbar() }
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = launcherLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: ScreenRecordingToolbar(recorder: recorder))
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let savedLauncherFrame {
            panel.setFrameOrigin(CGPoint(x: savedLauncherFrame.midX - ScreenRecordingToolbarLayout.width / 2, y: savedLauncherFrame.minY))
        } else if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: frame.midX - ScreenRecordingToolbarLayout.width / 2, y: frame.minY + 32))
        }
        self.panel = panel
        // Nonactivating panels can receive keyboard focus in the current Space
        // without activating the main Jarvis window on another desktop.
        panel.orderFrontRegardless()
        panel.makeKey()
        updateRegionBorder()
    }

    func resizeLauncher() {
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, let view = panel.contentView else { return }
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            guard size.width.isFinite, size.width > 0 else { return }
            let frame = CGRect(
                x: panel.frame.midX - size.width / 2, y: panel.frame.minY,
                width: size.width, height: ScreenRecordingToolbarLayout.height
            )
            panel.setFrame(frame, display: true)
        }
    }

    func showModeHint(_ mode: ScreenRecordingMode?) {
        modeHintTask?.cancel()
        modeHint?.close()
        modeHint = nil
        guard let mode else { return }
        modeHintTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, let panel else { return }
            let view = NSHostingView(rootView: Text(mode.recordingHint)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6)))
            let size = view.fittingSize
            let index = ScreenRecordingMode.allCases.firstIndex(of: mode) ?? 0
            let hint = NSPanel(
                contentRect: CGRect(
                    x: panel.frame.minX + 34 + CGFloat(index) * (ScreenRecordingToolbarLayout.modeWidth + ScreenRecordingToolbarLayout.spacing) - size.width / 2,
                    y: panel.frame.maxY + 8, width: size.width, height: size.height
                ),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            hint.isReleasedWhenClosed = false
            hint.isOpaque = false
            hint.backgroundColor = .clear
            hint.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
            hint.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            hint.ignoresMouseEvents = true
            hint.contentView = view
            hint.orderFrontRegardless()
            modeHint = hint
        }
    }

    func updateRegionBorder() {
        borderTrackingTask?.cancel()
        regionBorder?.close()
        regionBorder = nil
        guard !recorder.selectingTarget else { return }
        if recorder.mode == .region {
            showRegionBorder(displayID: recorder.displayID, rect: recorder.region)
        } else if recorder.mode == .window, let window = recorder.selectedWindow {
            showBorder(frame: ScreenRecordingGeometry.windowFrame(window.frame))
            let id = window.windowID
            borderTrackingTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    guard let self, let border = regionBorder else { return }
                    guard let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first,
                          let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                          let rect = CGRect(dictionaryRepresentation: dictionary)
                    else {
                        border.orderOut(nil)
                        return
                    }
                    border.setFrame(ScreenRecordingGeometry.windowFrame(rect), display: true)
                }
            }
        }
    }

    func showRegionBorder(displayID: CGDirectDisplayID?, rect: CGRect?) {
        guard let displayID, let rect,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == displayID
              }) else { return }
        showBorder(frame: rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY))
    }

    private func showBorder(frame: CGRect) {
        regionBorder?.close()
        let border = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        border.isReleasedWhenClosed = false
        border.isOpaque = false; border.backgroundColor = .clear
        border.ignoresMouseEvents = true
        border.level = .floating
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        border.contentView = NSHostingView(rootView: ScreenRecordingRegionOutline())
        border.orderFrontRegardless()
        regionBorder = border
    }

    func hide() {
        borderTrackingTask?.cancel()
        if panel != nil {
            savedLauncherFrame = launcherFrame
        }
        showModeHint(nil)
        regionBorder?.orderOut(nil); regionBorder?.close(); regionBorder = nil
        panel?.orderOut(nil); panel?.close(); panel = nil
    }
}

private final class ScreenRecordingLauncherPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == JarvisKeyCode.escape {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
