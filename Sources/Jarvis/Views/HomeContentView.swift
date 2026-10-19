import SwiftUI

struct JarvisHomeView: View {
    let pointerTracker: JarvisHomePointerTracker

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var promptIndex = 0
    @State private var promptSequence: [Int] = []
    @State private var displayedMessage = ""
    @State private var isPromptHovered = false

    private var prompts: [JarvisHomePrompt] {
        let permissionOrder: [JarvisRequiredPermission] = [
            .microphone, .screenCapture, .accessibility, .camera
        ]
        let missingPermissions = permissionOrder.filter { !app.isRequiredPermissionGranted($0) }

        return JarvisHomePrompt.featurePrompts
            + missingPermissions.map { JarvisHomePrompt.permissionPrompt(for: $0) }
    }

    private var dialogueCycleID: String {
        prompts.map(\.id).sorted().joined(separator: "|")
    }

    private var activePrompt: JarvisHomePrompt {
        guard promptSequence.indices.contains(promptIndex),
              prompts.indices.contains(promptSequence[promptIndex])
        else {
            return prompts[0]
        }
        return prompts[promptSequence[promptIndex]]
    }

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(placement: .navigation) {
                    EmptyView()
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) {
                    EmptyView()
                }
            },
            content: {
                GeometryReader { geometry in
                    let diameter = min(max(geometry.size.width * 0.42, 320), 480)
                    let mascotFrame = geometry.frame(in: .named(ContentView.homePointerCoordinateSpace))
                    let pointerDirection = pointerTracker.location.map { location in
                        CGSize(
                            width: min(max((location.x - mascotFrame.midX) / (geometry.size.width * 0.5), -1), 1),
                            height: min(max((location.y - mascotFrame.midY) / (geometry.size.height * 0.5), -1), 1)
                        )
                    }

                    JarvisMascotView(
                        diameter: diameter,
                        pointerDirection: pointerDirection,
                        promptBubble: AnyView(
                            promptBubble
                                .frame(width: min(300, geometry.size.width * 0.52), height: 176)
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(40)
            }
        )
    }

    private var promptBubble: some View {
        let prompt = activePrompt

        return Button {
            if let permission = prompt.permission {
                app.promptForTaskPermission(permission)
            } else {
                app.selectedSection = prompt.destination
            }
        } label: {
            ZStack {
                JarvisThoughtBubbleShape()
                    .fill(Color.jarvisAccent.opacity(0.18))
                    .overlay {
                        JarvisThoughtBubbleShape()
                            .stroke(Color.jarvisAccent.opacity(0.28), lineWidth: 1)
                    }

                Text(displayedMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 228, maxHeight: 80)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: 12, y: -15)
            }
            .contentShape(Rectangle())
            .shadow(color: .black.opacity(0.10), radius: 15, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(prompt.message)
        .accessibilityHint(
            prompt.permission.map { "查看\($0.title)权限" } ?? "打开\(prompt.destination.navigationTitle)"
        )
        .onHover { isPromptHovered = $0 }
        .task(id: dialogueCycleID) {
            promptSequence = Array(prompts.indices).shuffled()
            promptIndex = 0
            await typeAndRotatePrompts()
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: promptIndex)
    }

    private func typeAndRotatePrompts() async {
        while !Task.isCancelled {
            let currentPrompt = activePrompt
            displayedMessage = ""
            if reduceMotion {
                displayedMessage = currentPrompt.message
            } else {
                for character in currentPrompt.message {
                    guard !Task.isCancelled else { return }
                    displayedMessage.append(character)
                    do {
                        try await Task.sleep(for: .milliseconds(55))
                    } catch {
                        return
                    }
                }
            }

            guard prompts.count > 1 else {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        return
                    }
                }
                return
            }

            let displayUntil = Date().addingTimeInterval(14)
            while Date() < displayUntil || isPromptHovered || !pointerTracker.isIdle, !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(400))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                let nextIndex = promptIndex + 1
                if nextIndex == promptSequence.count {
                    var nextSequence = Array(prompts.indices).shuffled()
                    if nextSequence == promptSequence, nextSequence.count > 1 {
                        let firstIndex = nextSequence.removeFirst()
                        nextSequence.append(firstIndex)
                    }
                    promptSequence = nextSequence
                    promptIndex = 0
                } else {
                    promptIndex = nextIndex
                }
            }
        }
    }
}

private struct JarvisThoughtBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.16, 0.40))
        path.addCurve(to: point(0.30, 0.12), control1: point(0.07, 0.29), control2: point(0.10, 0.14))
        path.addCurve(to: point(0.52, 0.10), control1: point(0.37, 0.02), control2: point(0.44, 0.04))
        path.addCurve(to: point(0.73, 0.12), control1: point(0.61, 0.01), control2: point(0.67, 0.02))
        path.addCurve(to: point(0.94, 0.35), control1: point(0.84, 0.05), control2: point(0.97, 0.16))
        path.addCurve(to: point(0.92, 0.59), control1: point(1.00, 0.48), control2: point(0.99, 0.57))
        path.addCurve(to: point(0.72, 0.77), control1: point(0.87, 0.76), control2: point(0.81, 0.79))
        path.addCurve(to: point(0.48, 0.75), control1: point(0.63, 0.83), control2: point(0.55, 0.82))
        path.addCurve(to: point(0.25, 0.70), control1: point(0.39, 0.72), control2: point(0.31, 0.79))
        path.addCurve(to: point(0.16, 0.40), control1: point(0.10, 0.62), control2: point(0.08, 0.51))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: rect.width * 0.105, y: rect.height * 0.72, width: rect.width * 0.065, height: rect.height * 0.105))
        path.addEllipse(in: CGRect(x: rect.width * 0.035, y: rect.height * 0.87, width: rect.width * 0.04, height: rect.height * 0.065))
        return path
    }
}

private struct JarvisHomePrompt: Identifiable {
    let id: String
    let message: String
    let destination: AppSection
    let permission: JarvisRequiredPermission?

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
        case .camera:
            .init(
                id: "permission.camera",
                message: "开启摄像头权限，支持摄像头的网页功能就能正常使用啦。",
                destination: .aiConversation,
                permission: permission
            )
        }
    }

    static let featurePrompts: [JarvisHomePrompt] = [
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
        )
    ]
}
