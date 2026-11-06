import SwiftUI

struct HomeTipsCard: View {
    var illustrationHeight: CGFloat = 96
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var index = 0
    @State private var isHovering = false

    private var prompts: [JarvisHomePrompt] {
        let missing = JarvisRequiredPermission.allCases.filter { !app.isRequiredPermissionGranted($0) }
        let shortcuts: [JarvisHomePrompt] = [
            .init(id: "shortcut.screenshot", message: "按 \(app.screenshotShortcut.displayString) 开始截图；框选后可标注、识别文字或翻译。", destination: .skill(.screenshot), permission: nil),
            .init(id: "shortcut.clipboard", message: "按 \(app.clipboardShortcut.displayString) 唤出剪贴板历史，快速找回刚复制的文字和图片。", destination: .skill(.clipboard), permission: nil),
            .init(id: "shortcut.meeting", message: "按 \(app.meetingShortcut.displayString) 开始或结束会议录音，不用先切回主窗口。", destination: .skill(.meetingNotes), permission: nil),
            .init(id: "shortcut.window", message: "按 \(app.windowLayoutShortcut.displayString) 打开窗口布局，选好布局后即可整理当前窗口；按 Esc 取消。", destination: .skill(.windowLayout), permission: nil)
        ]
        return shortcuts + JarvisHomePrompt.featurePrompts + missing.map(JarvisHomePrompt.permissionPrompt)
    }

    private var prompt: JarvisHomePrompt {
        prompts[index % prompts.count]
    }

    var body: some View {
        HomeDashboardCard(title: "小贴士", symbol: "lightbulb", contentSpacing: 10, contentPadding: 14) {
            HomeTipIllustration(theme: prompt.illustration, height: illustrationHeight)
                .id(prompt.illustration)
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 6) {
                Text(prompt.title).font(.system(size: 14, weight: .semibold))
                Text(prompt.message).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(prompt.id).transition(.opacity)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(prompts.indices, id: \.self) { page in
                    Button {
                        select(page)
                    } label: {
                        Capsule()
                            .fill(page == index % prompts.count ? Color.jarvisAccent : Color.secondary.opacity(0.22))
                            .frame(width: page == index % prompts.count ? 12 : 4, height: 4)
                            .frame(width: 12, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("第 \(page + 1) 条小贴士")
                    .accessibilityAddTraits(page == index % prompts.count ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onHover { isHovering = $0 }
        .task(id: "\(index)-\(scenePhase == .active && !isHovering)-\(prompts.count)") {
            guard scenePhase == .active, !isHovering else { return }
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard !Task.isCancelled else { return }
            select((index + 1) % prompts.count)
        }
    }

    private func select(_ page: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { index = page }
    }
}

private struct JarvisHomePrompt: Identifiable {
    let id: String
    let message: String
    let destination: AppSection
    let permission: JarvisRequiredPermission?

    var illustration: String {
        switch destination {
        case .skill(.screenshot), .skill(.screenRecording): "capture"
        case .skill(.wallpaper), .gamePlaza, .entertainment: "relax"
        default: "organize"
        }
    }

    var title: String {
        if let permission {
            return "让 Jarvis 帮你更多 · \(permission.title)"
        }
        switch destination {
        case .skill(.screenshot): return "把有用的信息留下来"
        case .skill(.screenRecording): return "让每一步操作都清晰可见"
        case .skill(.clipboard): return "刚复制的内容，随时找得到"
        case .skill(.meetingNotes): return "专心讨论，让 Jarvis 做记录"
        case .skill(.resume): return "让经历成为你的优势"
        case .skill(.lanTransfer): return "让文件在设备间自由流动"
        case .skill(.windowLayout): return "给工作留一个整齐的桌面"
        case .skill(.wallpaper): return "换一张壁纸，换一种心情"
        case .aiConversation: return "给灵感找一个好搭档"
        case .gamePlaza, .entertainment: return "忙完之后，轻松一下"
        default: return "用好 Jarvis 的每一个小工具"
        }
    }

    static func permissionPrompt(for permission: JarvisRequiredPermission) -> JarvisHomePrompt {
        switch permission {
        case .microphone:
            .init(
                id: "permission.microphone",
                message: "开启麦克风权限，我就能帮你录取会议内容哦。",
                destination: .skill(.meetingNotes),
                permission: permission
            )
        case .screenCapture:
            .init(
                id: "permission.screen-capture",
                message: "开启屏幕录制权限，我就能帮你截图和采集会议系统声音啦。",
                destination: .skill(.screenshot),
                permission: permission
            )
        case .accessibility:
            .init(
                id: "permission.accessibility",
                message: "开启辅助功能权限，我就能帮你快速整理窗口啦。",
                destination: .skill(.windowLayout),
                permission: permission
            )
        }
    }

    static let featurePrompts: [JarvisHomePrompt] = [
        .init(
            id: "screen-recording",
            message: "想演示操作或记录问题？屏幕录制支持全屏、窗口和自定义区域。",
            destination: .skill(.screenRecording),
            permission: nil
        ),
        .init(
            id: "work-companion",
            message: "我是 Jarvis。办公时帮你处理琐事，休息时一起放松。",
            destination: .gamePlaza,
            permission: nil
        ),
        .init(
            id: "wallpaper",
            message: "想给桌面换个新氛围吗？去壁纸库逛逛，说不定有你的下一张心头好。",
            destination: .skill(.wallpaper),
            permission: nil
        ),
        .init(
            id: "screenshot",
            message: "看到有用的信息，随手截下来吧。我还能帮你识别和翻译截图里的文字。",
            destination: .skill(.screenshot),
            permission: nil
        ),
        .init(
            id: "clipboard",
            message: "刚复制过的文字或图片找不到了？来剪贴板历史里翻一翻。",
            destination: .skill(.clipboard),
            permission: nil
        ),
        .init(
            id: "meeting",
            message: "要开会啦？让我帮你录下讨论内容，之后还能整理成会议纪要。",
            destination: .skill(.meetingNotes),
            permission: nil
        ),
        .init(
            id: "window-layout",
            message: "桌面窗口有点乱？试试一键排布，把常用窗口摆得整整齐齐。",
            destination: .skill(.windowLayout),
            permission: nil
        ),
        .init(
            id: "lan-transfer",
            message: "想把文件传到另一台设备？同一网络下就能快速传给附近的设备。",
            destination: .skill(.lanTransfer),
            permission: nil
        ),
        .init(
            id: "resume",
            message: "正在准备求职材料吗？可以从简历制作开始，慢慢打磨出满意的版本。",
            destination: .skill(.resume),
            permission: nil
        ),
        .init(
            id: "ai",
            message: "有问题想一起琢磨？去 AI 聚合页选个模型，开始聊聊吧。",
            destination: .aiConversation,
            permission: nil
        ),
        .init(
            id: "entertainment",
            message: "忙完了就放松一下吧。娱乐广场里可以看看你喜欢的平台内容。",
            destination: .entertainment,
            permission: nil
        ),
        .init(
            id: "mahjong",
            message: "想打两圈欢乐麻将？可以单人练习，也能和朋友开房对战。",
            destination: .gamePlaza,
            permission: nil
        )
    ]
}
