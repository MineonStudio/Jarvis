import AppKit
import SwiftUI

/// The idle state of the independent Mahjong window. Settings floats above the
/// same artwork, leaving the title and the main menu visible.
struct MahjongLaunchView: View {
    let model: MahjongGameWindowModel
    @ObservedObject private var service: MahjongLANRoomService

    init(model: MahjongGameWindowModel) {
        self.model = model
        _service = ObservedObject(wrappedValue: model.menuLANRoomService)
    }

    private enum Page {
        case main, solo, lan, settings
    }

    private enum LANDialog {
        case create, join
    }

    @State private var page: Page = .main
    @State private var settingsSelection: MahjongSettingsSection = .profile
    @State private var hoveredMenuTitle: String?
    @State private var lanDialog: LANDialog?
    @State private var selectedLANRuleset: MahjongRuleset?
    @State private var joinCode = ""
    @State private var showsStartNotice = false

    private var archive: MahjongArchiveStore {
        model.archive
    }

    var body: some View {
        photoMenu
            .onChange(of: page) { oldPage, newPage in
                hoveredMenuTitle = nil
                lanDialog = nil
                selectedLANRuleset = nil
                if oldPage == .lan, newPage != .lan, !model.game.isStarted {
                    service.stop()
                }
            }
            .onChange(of: model.roundNotice) { _, notice in
                showsStartNotice = notice != nil && !model.game.isStarted
            }
            .onChange(of: service.connected) { _, connected in
                if connected, !service.isHosting, page == .lan {
                    model.onStartLAN(service)
                }
            }
            .alert("无法开始对局", isPresented: $showsStartNotice) {
                Button("知道了", role: .cancel) { model.roundNotice = nil }
            } message: {
                Text(model.roundNotice ?? "")
            }
    }

    private var photoMenu: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let url = Bundle.main.url(forResource: "mahjong-launch-background", withExtension: "png", subdirectory: "GameArtwork"),
                   let image = NSImage(contentsOf: url)
                {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityLabel("欢乐麻将")
                } else {
                    MahjongVisualTheme.felt
                }

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 24)

                    Group {
                        switch page {
                        case .main: mainMenu
                        case .solo: soloMenu
                        case .lan: lanMenu
                        case .settings: settingsMenu
                        }
                    }
                    .frame(width: min(geometry.size.width * 0.49, 560), alignment: .leading)
                    .padding(.leading, geometry.size.width * 0.052)
                    .padding(.bottom, geometry.size.height * 0.055)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                if page == .settings {
                    rightPanel(in: geometry.size) {
                        MahjongSettingsView(archive: archive, selection: settingsSelection) {
                            withAnimation(.easeOut(duration: 0.2)) { page = .main }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .zIndex(1)
                }

                if let lanDialog {
                    rightPanel(in: geometry.size) { lanDialogPanel(lanDialog) }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .zIndex(1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private var mainMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            menuButton("单人模式") { page = .solo }
            menuButton("局域网对战") { page = .lan }
            menuButton("设置") {
                settingsSelection = .profile
                withAnimation(.easeOut(duration: 0.2)) { page = .settings }
            }
            menuButton("退出") { model.onCloseMenu() }
        }
    }

    private var soloMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MahjongRuleset.allCases) { ruleset in
                menuButton(ruleset.rawValue) { model.onStartSolo(ruleset) }
            }
            menuButton("返回主菜单") { page = .main }
        }
    }

    private var settingsMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MahjongSettingsSection.allCases) { section in
                menuButton(section.rawValue) {
                    withAnimation(.easeInOut(duration: 0.18)) { settingsSelection = section }
                }
            }
            menuButton("返回主菜单") {
                withAnimation(.easeOut(duration: 0.2)) { page = .main }
            }
        }
    }

    private func rightPanel(in size: CGSize, @ViewBuilder content: () -> some View) -> some View {
        let leftEdge = max(size.width * 0.32, 308)
        let topEdge = max(size.height * 0.30, 238)
        let rightInset = max(size.width * 0.035, 28)
        let bottomInset = max(size.height * 0.045, 24)
        let panelWidth = size.width - leftEdge - rightInset
        let panelHeight = size.height - topEdge - bottomInset
        return content()
            .frame(width: panelWidth, height: panelHeight)
            .position(x: leftEdge + panelWidth / 2, y: topEdge + panelHeight / 2)
    }

    private var lanMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MahjongRuleset.allCases) { ruleset in
                menuButton(ruleset.rawValue) {
                    selectedLANRuleset = ruleset
                    lanDialog = .create
                }
            }
            menuButton("创建房间") {
                selectedLANRuleset = nil
                lanDialog = .create
            }
            menuButton("加入房间") {
                joinCode = ""
                service.startBrowsing()
                lanDialog = .join
            }
            menuButton("返回主菜单") { page = .main }
        }
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .foregroundStyle(hoveredMenuTitle == title ? MahjongVisualTheme.goldHover : MahjongVisualTheme.ivory)
                .shadow(color: .black.opacity(0.9), radius: 5, y: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .scaleEffect(hoveredMenuTitle == title ? 1.055 : 1, anchor: .leading)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredMenuTitle = hovering ? title : (hoveredMenuTitle == title ? nil : hoveredMenuTitle)
        }
        .animation(.easeOut(duration: 0.16), value: hoveredMenuTitle == title)
    }

    private func lanDialogPanel(_ dialog: LANDialog) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(dialog == .create ? "创建房间" : "加入房间")
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                Spacer()
                Button { dismissLANDialog() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MahjongVisualTheme.ivory)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭房间弹窗")
            }

            ScrollView {
                Group {
                    if dialog == .create {
                        createRoomContent
                    } else {
                        joinRoomContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(MahjongVisualTheme.ivory)
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.32), radius: 22, y: 10)
        .environment(\.colorScheme, .dark)
    }

    private var createRoomContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let code = service.roomCode {
                Text("\(service.roomRuleset.rawValue) · \(service.humanCount)/4 · \(archive.player.nickname)的房间")
                    .font(.system(size: 16, weight: .medium))
                Text(code)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .tracking(6)
                    .foregroundStyle(MahjongVisualTheme.gold)
                    .textSelection(.enabled)
                Text("将房间码发给同一局域网的朋友")
                    .foregroundStyle(MahjongVisualTheme.muted)
                if service.isHosting {
                    Button("进入牌桌") { model.onStartLAN(service) }
                        .buttonStyle(MahjongGameButtonStyle(kind: .primary))
                } else {
                    Text(service.status).foregroundStyle(MahjongVisualTheme.muted)
                }
            } else {
                Text("选择玩法")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MahjongVisualTheme.muted)
                ForEach(MahjongRuleset.allCases) { ruleset in
                    Button {
                        selectedLANRuleset = ruleset
                    } label: {
                        HStack {
                            Text(ruleset.rawValue)
                            Spacer()
                            if selectedLANRuleset == ruleset {
                                Image(systemName: "checkmark.circle.fill")
                            }
                        }
                        .padding(12)
                        .foregroundStyle(selectedLANRuleset == ruleset ? MahjongVisualTheme.gold : MahjongVisualTheme.ivory)
                        .background(MahjongVisualTheme.raisedSurface.opacity(selectedLANRuleset == ruleset ? 1 : 0.65), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                Button("创建房间") {
                    guard let selectedLANRuleset else { return }
                    service.createRoom(profile: archive.player, ruleset: selectedLANRuleset)
                }
                .buttonStyle(MahjongGameButtonStyle(kind: .primary))
                .disabled(selectedLANRuleset == nil)
            }
        }
    }

    private var joinRoomContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TextField("输入六位房间码", text: $joinCode)
                    .textFieldStyle(.plain)
                    .foregroundStyle(MahjongVisualTheme.ivory)
                    .tint(MahjongVisualTheme.gold)
                    .padding(12)
                    .background(MahjongVisualTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(MahjongVisualTheme.gold.opacity(0.4)))
                    .onChange(of: joinCode) { _, value in
                        joinCode = String(value.filter(\.isNumber).prefix(6))
                    }
                Button("加入") { service.joinRoom(code: joinCode, profile: archive.player) }
                    .buttonStyle(MahjongGameButtonStyle(kind: .primary))
                    .disabled(joinCode.count != 6 || service.isConnecting)
            }

            HStack {
                Text("可用房间").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("刷新") { service.startBrowsing() }
                    .buttonStyle(MahjongGameButtonStyle())
            }
            if service.rooms.isEmpty {
                Text("尚未发现可加入的房间")
                    .foregroundStyle(MahjongVisualTheme.muted)
                    .frame(maxWidth: .infinity, minHeight: 75, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(service.rooms) { room in
                        Button {
                            joinCode = room.code
                            service.joinRoom(code: room.code, profile: archive.player)
                        } label: {
                            HStack {
                                Text(room.displayName).lineLimit(2)
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.right")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(MahjongVisualTheme.raisedSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(room.humanCount >= 4 || service.isConnecting)
                    }
                }
            }
            Text(service.status)
                .font(.system(size: 13))
                .foregroundStyle(MahjongVisualTheme.muted)
                .lineLimit(2)
        }
    }

    private func dismissLANDialog() {
        service.stop()
        lanDialog = nil
        selectedLANRuleset = nil
    }
}
