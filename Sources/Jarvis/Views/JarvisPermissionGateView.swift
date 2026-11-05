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

            VStack(spacing: JarvisSpacing.sectionGap) {
                Image(systemName: prompt.permission.systemImage)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Color.jarvisAccent)
                    .frame(width: 108, height: 84)
                    .background(Color.jarvisAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))

                VStack(spacing: JarvisSpacing.controlGap) {
                    Text(prompt.title)
                        .font(JarvisTypography.pageTitle)
                        .multilineTextAlignment(.center)
                    Text(prompt.message)
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: JarvisSpacing.itemGap) {
                    Button("获取权限") {
                        app.handleTaskPermissionPromptAction()
                    }
                    .buttonStyle(PermissionCapsuleButtonStyle(isPrimary: true))
                    .frame(maxWidth: .infinity)

                    Button("暂不") {
                        app.dismissTaskPermissionPrompt()
                    }
                    .buttonStyle(PermissionCapsuleButtonStyle(isPrimary: false))
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(JarvisSpacing.pageInset)
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
            .jarvisButtonShadow()
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
        VStack(spacing: JarvisSpacing.pageInset) {
            JarvisOrbMark(diameter: 58)

            VStack(spacing: JarvisSpacing.controlGap) {
                Text("先让我帮得上忙")
                    .font(JarvisTypography.pageTitle)
                    .multilineTextAlignment(.center)
                Text(invitationLine)
                    .font(JarvisTypography.secondary)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
                Text("Jarvis 需要这三项权限才能开始工作；屏幕录制和辅助功能授权后需要重启一次。")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
            }

            JarvisPermissionList()
        }
        .padding(.horizontal, JarvisSpacing.pageInset)
        .padding(.top, JarvisSpacing.pageInset)
        .padding(.bottom, JarvisSpacing.pageInset)
        .frame(width: 400)
        .jarvisGlass(cornerRadius: 24, interactive: false)
        .shadow(color: Color.black.opacity(0.16), radius: 32, y: 14)
    }
}

enum JarvisPermissionListMode: Equatable {
    case gate
    case settings
}

/// The required permissions with their current state and available actions.
struct JarvisPermissionList: View {
    var cornerRadius: CGFloat = 16
    var mode: JarvisPermissionListMode = .gate

    var body: some View {
        if mode == .settings {
            VStack(spacing: JarvisSpacing.itemGap) {
                ForEach(Array(JarvisRequiredPermission.allCases.enumerated()), id: \.element.id) { index, permission in
                    JarvisPermissionSettingsRow(permission: permission)
                    if index < JarvisRequiredPermission.allCases.count - 1 {
                        Divider()
                    }
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

private struct JarvisPermissionSettingsRow: View {
    @Environment(AppModel.self) private var app
    let permission: JarvisRequiredPermission

    var body: some View {
        let isGranted = app.isRequiredPermissionGranted(permission)
        return HStack(spacing: JarvisSpacing.itemGap) {
            HStack(spacing: JarvisSpacing.controlGap) {
                Text(permission.title)
                    .font(SettingsTypography.itemTitle)
                    .foregroundStyle(Color.primary)
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isGranted ? Color.green : Color.jarvisTextSecondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(isGranted ? "已开启" : "未开启")
            Spacer(minLength: 8)
            Button(isGranted ? "关闭" : "获取") {
                if isGranted {
                    if JarvisPrivacyPermissionAccess.openSettings(for: permission.privacyPermission) {
                        app.showToast("请在系统设置中关闭\(permission.title)权限")
                    } else {
                        app.showToast("无法打开系统设置，请前往隐私与安全性关闭\(permission.title)权限")
                    }
                } else {
                    app.requestRequiredPermission(permission)
                }
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("\(isGranted ? "关闭" : "获取")\(permission.title)权限")
            .help(isGranted ? "前往系统设置关闭\(permission.title)权限" : "获取\(permission.title)权限")
        }
        .frame(maxWidth: .infinity, minHeight: SettingsFormMetrics.controlHeight, alignment: .leading)
        .accessibilityElement(children: .contain)
        .animation(JarvisMotion.selection, value: isGranted)
    }
}

private struct JarvisPermissionRow: View {
    @Environment(AppModel.self) private var app
    let permission: JarvisRequiredPermission

    var body: some View {
        let isGranted = app.isRequiredPermissionGranted(permission)
        return HStack(spacing: JarvisSpacing.itemGap) {
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
        .padding(.horizontal, JarvisSpacing.cardInset)
        .padding(.vertical, JarvisSpacing.rowInset)
        .animation(JarvisMotion.selection, value: isGranted)
    }
}
