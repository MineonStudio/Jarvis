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
    var onNextRound: () -> Void
    var onExit: () -> Void

    init(game: MahjongGame, archive: MahjongArchiveStore, lanRoomService: MahjongLANRoomService) {
        self.game = game
        self.archive = archive
        self.lanRoomService = lanRoomService
        onNextRound = {}
        onExit = {}
    }
}

/// Separate mahjong window. Same open/close life as the clipboard panel, but a normal window
/// whose content stays at 1280:1000 so the table cannot be stretched.
/// One controller for the process, so a recreated plaza cannot open a second table.
@MainActor
final class MahjongGameWindowController: NSObject, NSWindowDelegate {
    static let shared = MahjongGameWindowController()

    private var window: NSWindow?
    private var hostedModel: MahjongGameWindowModel?
    private var suppressCloseCallback = false
    var onUserClose: (() -> Void)?

    private static let contentRatio = NSSize(width: 1280, height: 1000)
    private static let defaultContentSize = NSSize(width: 1152, height: 900)
    private static let minimumContentSize = NSSize(width: 960, height: 750)

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
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides the window without running the exit hook. Used when the match already ended.
    func hide() {
        suppressCloseCallback = true
        window?.orderOut(nil)
        suppressCloseCallback = false
    }

    private func makeWindow(model: MahjongGameWindowModel) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "麻将"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentAspectRatio = Self.contentRatio
        window.contentMinSize = Self.minimumContentSize
        window.setContentSize(Self.defaultContentSize)
        window.backgroundColor = NSColor(red: 0.055, green: 0.22, blue: 0.11, alpha: 1)
        let hosting = NSHostingView(rootView: MahjongTableView(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting
        self.window = window
        hostedModel = model
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
