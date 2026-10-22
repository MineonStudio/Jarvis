import AppKit
import SwiftUI

/// Settlement text and the exit hooks for the table window.
/// The plaza keeps the match. This object lets the hosting view update without being rebuilt.
@MainActor
@Observable
final class MahjongGameWindowModel {
    let game: MahjongGame
    let archive: MahjongArchiveStore
    var lanRoomService: MahjongLANRoomService
    var roundNotice: String?
    var roundSettlement: MahjongArchiveSettlement?
    let menuLANRoomService = MahjongLANRoomService()
    var onStartSolo: (MahjongRuleset) -> Void
    var onStartLAN: (MahjongLANRoomService) -> Void
    var onCloseMenu: () -> Void
    var onNextRound: () -> Void
    var onExit: () -> Void

    init(game: MahjongGame, archive: MahjongArchiveStore, lanRoomService: MahjongLANRoomService) {
        self.game = game
        self.archive = archive
        self.lanRoomService = lanRoomService
        onNextRound = {}
        onExit = {}
        onStartSolo = { _ in }
        onStartLAN = { _ in }
        onCloseMenu = {}
    }
}

/// A borderless 16:9 game window, opened independently from the plaza.
/// One controller for the process, so a recreated plaza cannot open a second table.
@MainActor
final class MahjongGameWindowController: NSObject, NSWindowDelegate {
    static let shared = MahjongGameWindowController()

    private var window: NSWindow?
    private var hostedModel: MahjongGameWindowModel?
    private var suppressCloseCallback = false
    var onUserClose: (() -> Void)?

    private static let defaultContentSize = NSSize(width: 1920, height: 1080)
    private static let minimumContentSize = NSSize(width: 960, height: 540)

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAudioActivity), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshAudioActivity), name: NSApplication.didResignActiveNotification, object: nil)
    }

    @objc private func refreshAudioActivity() {
        MahjongAudioPlayer.shared.setFocused(NSApp.isActive && window?.isKeyWindow == true && window?.isVisible == true)
    }

    func show(model: MahjongGameWindowModel) {
        if window == nil {
            makeWindow(model: model)
        } else if hostedModel !== model, let window {
            let hosting = NSHostingView(rootView: MahjongTableView(model: model))
            hosting.sizingOptions = []
            window.contentView = hosting
            hostedModel = model
        }
        guard let window else { return }
        MahjongAudioPlayer.shared.startSession()
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides the window without running the exit hook. Used when the match already ended.
    func hide() {
        MahjongAudioPlayer.shared.stopSession()
        suppressCloseCallback = true
        window?.orderOut(nil)
        suppressCloseCallback = false
    }

    private func makeWindow(model: MahjongGameWindowModel) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let availableSize = screen?.visibleFrame.size ?? Self.defaultContentSize
        let scale = min(
            1,
            availableSize.width / Self.defaultContentSize.width,
            availableSize.height / Self.defaultContentSize.height
        )
        let contentSize = NSSize(
            width: Self.defaultContentSize.width * scale,
            height: Self.defaultContentSize.height * scale
        )
        let window = MahjongBorderlessWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "欢乐麻将"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentAspectRatio = Self.defaultContentSize
        window.contentMinSize = NSSize(
            width: min(Self.minimumContentSize.width, contentSize.width),
            height: min(Self.minimumContentSize.height, contentSize.height)
        )
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setContentSize(contentSize)
        window.backgroundColor = MahjongTableSettings.shared.style.color
        let hosting = NSHostingView(rootView: MahjongTableView(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting
        if let visibleFrame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2
            ))
        }
        self.window = window
        hostedModel = model
    }

    func windowDidBecomeKey(_: Notification) {
        refreshAudioActivity()
    }

    func windowDidResignKey(_: Notification) {
        MahjongAudioPlayer.shared.setFocused(false)
    }

    func windowDidMiniaturize(_: Notification) {
        MahjongAudioPlayer.shared.setFocused(false)
    }

    func windowWillClose(_: Notification) {
        MahjongAudioPlayer.shared.stopSession()
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        if suppressCloseCallback {
            return true
        }
        let exit = onUserClose
        suppressCloseCallback = true
        exit?()
        suppressCloseCallback = false
        return true
    }
}

/// Borderless NSWindows need to opt into keyboard focus for game controls and text fields.
private final class MahjongBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
