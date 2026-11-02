import SwiftUI

typealias MahjongSettingsPalette = MahjongVisualTheme

enum MahjongSettingsSection: String, CaseIterable, Identifiable {
    case profile = "我的资料"
    case record = "玩家数据"
    case daily = "每日签到"
    case table = "牌桌主题"
    case voice = "声音设置"

    var id: String {
        rawValue
    }
}

/// Compact settings panel displayed over the Mahjong launch scene.
struct MahjongSettingsView: View {
    let archive: MahjongArchiveStore
    let selection: MahjongSettingsSection
    let onBack: () -> Void

    enum RecordTab: String, CaseIterable {
        case mine = "我的数据"
        case ai = "AI 玩家数据"
    }

    @State var recordTab: RecordTab = .mine
    @State var selectedAIProfileID: String?
    @State var nicknameDraft = ""
    @State var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailPane
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.32), radius: 22, y: 10)
        .environment(\.colorScheme, .dark)
        .onAppear { nicknameDraft = archive.player.nickname }
        .onExitCommand(perform: onBack)
    }

    var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(selection.rawValue)
                    .font(.system(size: 25, weight: .semibold, design: .serif))
                    .foregroundStyle(MahjongSettingsPalette.ivory)
                Spacer()
                Button(action: onBack) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MahjongSettingsPalette.ivory)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭设置")
            }
            .padding(.bottom, JarvisSpacing.cardInset)

            ScrollView {
                Group {
                    switch selection {
                    case .profile: profileContent
                    case .record: recordContent
                    case .daily: dailyContent
                    case .table: MahjongTableStylePicker()
                    case .voice: voiceContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, JarvisSpacing.controlGap)
                .padding(.bottom, JarvisSpacing.pageInset)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, JarvisSpacing.pageInset)
        .padding(.top, JarvisSpacing.pageInset)
        .padding(.bottom, JarvisSpacing.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var profileContent: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.pageInset) {
            HStack(alignment: .center, spacing: JarvisSpacing.sectionGap) {
                MahjongArchiveAvatar(profile: archive.player, size: 86)
                    .padding(JarvisSpacing.iconGap)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(MahjongSettingsPalette.accent.opacity(0.8), lineWidth: 2))

                VStack(alignment: .leading, spacing: JarvisSpacing.groupGap) {
                    caption("玩家昵称")
                    HStack(spacing: JarvisSpacing.itemGap) {
                        TextField("输入昵称", text: $nicknameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(MahjongSettingsPalette.ivory)
                            .padding(.horizontal, JarvisSpacing.cardInset)
                            .frame(height: 45)
                            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MahjongSettingsPalette.accent.opacity(0.35), lineWidth: 1))
                            .onSubmit(saveNickname)
                        primaryButton("保存", action: saveNickname)
                    }
                    Text("最多 16 个字符")
                        .font(.system(size: 12))
                        .foregroundStyle(MahjongSettingsPalette.muted)
                }
                .frame(maxWidth: 430)
            }

            caption("选择头像")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 125), spacing: JarvisSpacing.itemGap)], alignment: .leading, spacing: JarvisSpacing.itemGap) {
                ForEach(MahjongArchiveAvatarStyle.playerChoices, id: \.self) { style in
                    avatarChoice(style)
                }
            }
        }
    }

    func avatarChoice(_ style: MahjongArchiveAvatarStyle) -> some View {
        var preview = archive.player
        preview.avatarStyle = style
        preview.customAvatarFilename = nil
        let isSelected = archive.player.customAvatarFilename == nil && archive.player.avatarStyle == style
        return Button {
            archive.updatePlayerProfile(avatarStyle: style)
        } label: {
            VStack(spacing: JarvisSpacing.controlGap) {
                MahjongArchiveAvatar(profile: preview, size: 54)
                    .accessibilityHidden(true)
                Text(style.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? MahjongSettingsPalette.accent : MahjongSettingsPalette.ivory)
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(isSelected ? MahjongSettingsPalette.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? MahjongSettingsPalette.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.displayName)
    }
}
