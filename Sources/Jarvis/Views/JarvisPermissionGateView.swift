import AppKit
import SwiftUI

struct JarvisTaskPermissionOverlay: View {
    @Environment(AppModel.self) private var app
    let prompt: JarvisTaskPermissionPrompt

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.16))
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 18) {
                Image(systemName: prompt.permission.systemImage)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.jarvisAccent)
                    .frame(width: 108, height: 84)
                    .background(Color.jarvisAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))

                VStack(spacing: 8) {
                    Text(prompt.title)
                        .font(JarvisTypography.pageTitle)
                        .multilineTextAlignment(.center)
                    Text(prompt.message)
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("获取权限") {
                        app.handleTaskPermissionPromptAction()
                    }
                    .buttonStyle(PermissionCapsuleButtonStyle(isPrimary: true))
                    .frame(maxWidth: .infinity)

                    Button("暂不") {
                        app.taskPermissionPrompt = nil
                    }
                    .buttonStyle(PermissionCapsuleButtonStyle(isPrimary: false))
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(28)
            .frame(width: 440)
            .jarvisGlass(cornerRadius: 24, interactive: false)
            .shadow(color: Color.black.opacity(0.16), radius: 32, y: 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt.title)
    }
}

private struct PermissionCapsuleButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(JarvisTypography.bodyEmphasis)
            .foregroundStyle(isPrimary ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                Capsule(style: .continuous)
                    .fill(isPrimary ? Color.jarvisAccent : Color.jarvisInsetSurface)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(isPrimary ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct JarvisPermissionGateOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.16))
                .ignoresSafeArea()
                .contentShape(Rectangle())

            JarvisPermissionGateView()
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
        }
        .onAppear {
            app.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissionStatus()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("先让我帮得上忙")
    }
}

struct JarvisPermissionGateView: View {
    @Environment(AppModel.self) private var app
    private var remainingCount: Int {
        JarvisRequiredPermission.allCases.count { !app.isRequiredPermissionGranted($0) }
    }

    private var invitationLine: String {
        switch remainingCount {
        case 0: "都好了，我们开始。"
        case 1: "就差这一步了。"
        default: "打开这些，我们就开始。"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            JarvisOrbMark(diameter: 58)

            VStack(spacing: 7) {
                Text("先让我帮得上忙")
                    .font(JarvisTypography.pageTitle)
                    .multilineTextAlignment(.center)
                Text(invitationLine)
                    .font(JarvisTypography.secondary)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
                Text("工作搭子 Jarvis需要这四项权限才能开始工作；屏幕录制和辅助功能授权后需要重启一次。")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
            }

            JarvisPermissionList()
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 26)
        .frame(width: 400)
        .jarvisGlass(cornerRadius: 24, interactive: false)
        .shadow(color: Color.black.opacity(0.16), radius: 32, y: 14)
    }
}

enum JarvisPermissionListMode: Equatable {
    case gate
    case settings
}

/// The four required permissions with their current state. The gate cannot be
/// dismissed, so this is the only place grants are requested.
struct JarvisPermissionList: View {
    var cornerRadius: CGFloat = 16
    var mode: JarvisPermissionListMode = .gate

    var body: some View {
        if mode == .settings {
            // 卡片变窄后，四个等分胶囊会把「屏幕录制」挤成省略号。按内容宽度换行，文字保持完整。
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 136), spacing: 10)],
                spacing: 10
            ) {
                ForEach(JarvisRequiredPermission.allCases) { permission in
                    JarvisPermissionStatusCapsule(permission: permission)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(JarvisRequiredPermission.allCases.enumerated()), id: \.element.id) { index, permission in
                    JarvisPermissionRow(permission: permission)
                    if index < JarvisRequiredPermission.allCases.count - 1 {
                        Divider()
                            .opacity(0.45)
                            .padding(.leading, 50)
                    }
                }
            }
            .background(
                Color.jarvisInsetSurface,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

private struct JarvisPermissionStatusCapsule: View {
    @Environment(AppModel.self) private var app
    let permission: JarvisRequiredPermission

    var body: some View {
        let isGranted = app.isRequiredPermissionGranted(permission)
        return HStack(spacing: 8) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.jarvisTextSecondary)
                .frame(width: 16, height: 16)
            Text(permission.title)
                .font(JarvisTypography.control)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.green)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: SettingsFormMetrics.controlHeight, alignment: .leading)
        .background(Color.jarvisPanel.opacity(0.55), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(permission.title)，\(isGranted ? "已授权" : "未授权")")
        .animation(JarvisMotion.selection, value: isGranted)
    }
}

private struct JarvisPermissionRow: View {
    @Environment(AppModel.self) private var app
    let permission: JarvisRequiredPermission

    var body: some View {
        let isGranted = app.isRequiredPermissionGranted(permission)
        return HStack(spacing: 12) {
            Image(systemName: permission.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isGranted ? Color.green : Color.jarvisAccent)
                .frame(width: 30, height: 30)
                .background(
                    (isGranted ? Color.green : Color.jarvisAccent).opacity(0.12),
                    in: Circle()
                )

            Text(permission.title)
                .font(JarvisTypography.bodyEmphasis)
                .foregroundStyle(isGranted ? Color.jarvisTextSecondary : Color.primary)

            Spacer(minLength: 8)

            if isGranted {
                Text("已就绪")
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(permission.title)已就绪")
            } else {
                Button("允许") {
                    app.requestRequiredPermission(permission)
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
                .controlSize(.small)
                .accessibilityLabel("允许\(permission.title)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .animation(JarvisMotion.selection, value: isGranted)
    }
}
