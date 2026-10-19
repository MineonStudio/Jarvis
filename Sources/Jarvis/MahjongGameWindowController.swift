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

/// Separate mahjong window with a native toolbar and a fixed 16:9 outer frame ratio.
/// One controller for the process, so a recreated plaza cannot open a second table.
@MainActor
final class MahjongGameWindowController: NSObject, NSWindowDelegate {
    static let shared = MahjongGameWindowController()

    private var window: NSWindow?
    private var hostedModel: MahjongGameWindowModel?
    private var suppressCloseCallback = false
    var onUserClose: (() -> Void)?

    private static let windowAspectRatio = NSSize(width: 16, height: 9)
    private static let defaultWindowSize = NSSize(width: 1280, height: 720)
    private static let minimumWindowSize = NSSize(width: 960, height: 540)
    private static let toolbarIdentifier = NSToolbar.Identifier("com.jarvis.mahjong.toolbar")

    private enum ToolbarItemID {
        static let facts = NSToolbarItem.Identifier("com.jarvis.mahjong.toolbar.facts")
        static let message = NSToolbarItem.Identifier("com.jarvis.mahjong.toolbar.message")
        static let round = NSToolbarItem.Identifier("com.jarvis.mahjong.toolbar.round")
        static let exit = NSToolbarItem.Identifier("com.jarvis.mahjong.toolbar.exit")
    }

    func show(model: MahjongGameWindowModel) {
        if window == nil {
            makeWindow(model: model)
        } else if hostedModel !== model, let window {
            let hosting = NSHostingView(rootView: MahjongTableView(model: model))
            hosting.sizingOptions = []
            window.contentView = hosting
            hostedModel = model
            installToolbar(on: window)
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
            contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "麻将"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.toolbarStyle = .unified
        window.aspectRatio = Self.windowAspectRatio
        window.minSize = Self.minimumWindowSize
        window.setFrame(NSRect(origin: .zero, size: Self.defaultWindowSize), display: false)
        window.backgroundColor = NSColor(red: 0.055, green: 0.22, blue: 0.11, alpha: 1)
        let hosting = NSHostingView(rootView: MahjongTableView(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting
        self.window = window
        hostedModel = model
        installToolbar(on: window)
        window.setFrame(NSRect(origin: .zero, size: Self.defaultWindowSize), display: false)
    }

    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        window.toolbar = toolbar
    }

    private func makeToolbarItem<Content: View>(
        _ identifier: NSToolbarItem.Identifier,
        label: String,
        size: NSSize,
        @ViewBuilder content: () -> Content
    ) -> NSToolbarItem {
        let hosting = NSHostingView(rootView: AnyView(content()))
        hosting.sizingOptions = []
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: size.width),
            container.heightAnchor.constraint(equalToConstant: size.height)
        ])
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.view = container
        return item
    }

    private var toolbarModel: MahjongGameWindowModel? { hostedModel }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if suppressCloseCallback { return true }
        let exit = onUserClose
        suppressCloseCallback = true
        exit?()
        suppressCloseCallback = false
        return true
    }
}

extension MahjongGameWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            ToolbarItemID.facts,
            .flexibleSpace,
            ToolbarItemID.message,
            .flexibleSpace,
            ToolbarItemID.round,
            ToolbarItemID.exit
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let model = toolbarModel else { return nil }
        switch itemIdentifier {
        case ToolbarItemID.facts:
            return makeToolbarItem(itemIdentifier, label: "牌局信息", size: NSSize(width: 260, height: 34)) {
                MahjongToolbarFacts(model: model)
            }
        case ToolbarItemID.message:
            return makeToolbarItem(itemIdentifier, label: "牌局状态", size: NSSize(width: 270, height: 34)) {
                MahjongToolbarMessage(model: model)
            }
        case ToolbarItemID.round:
            return makeToolbarItem(itemIdentifier, label: "时长与余牌", size: NSSize(width: 145, height: 34)) {
                MahjongToolbarRoundInfo(model: model)
            }
        case ToolbarItemID.exit:
            return makeToolbarItem(itemIdentifier, label: "退出游戏", size: NSSize(width: 108, height: 34)) {
                Button {
                    model.onExit()
                } label: {
                    Label("退出游戏", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .controlSize(.small)
                .buttonStyle(.glass)
            }
        default:
            return nil
        }
    }
}

private struct MahjongToolbarFacts: View {
    let model: MahjongGameWindowModel

    var body: some View {
        HStack(spacing: 8) {
            Text("麻将")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
            Text(model.game.ruleset.rawValue)
            Text(model.game.mode.rawValue)
            if model.game.mode == .lan, let roomCode = model.lanRoomService.roomCode {
                Text("房间码 \(roomCode)")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .glassEffect(in: Capsule())
    }
}

private struct MahjongToolbarMessage: View {
    let model: MahjongGameWindowModel

    var body: some View {
        Text(model.game.message)
            .font(.system(size: 13, weight: .medium, design: .serif))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .glassEffect(in: Capsule())
            .help(model.game.message)
    }
}

private struct MahjongToolbarRoundInfo: View {
    let model: MahjongGameWindowModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 10) {
                Text(duration(at: context.date))
                Text("余 \(model.game.wall.count)")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .glassEffect(in: Capsule())
        }
    }

    private func duration(at date: Date) -> String {
        if let endedAt = model.game.roundEndedAt {
            return Self.formatDuration(from: model.game.roundStartedAt, to: endedAt)
        }
        return Self.formatDuration(from: model.game.roundStartedAt, to: date)
    }

    private static func formatDuration(from start: Date?, to date: Date) -> String {
        guard let start else { return "00:00" }
        let seconds = max(0, Int(date.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
