import AppKit
import SwiftUI

struct JarvisOnboardingView: View {
    let onContentSizeChange: (CGSize) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var requestedPermission: JarvisRequiredPermission?

    private var step: JarvisOnboardingStep {
        app.onboarding.step
    }

    private var isGranted: Bool {
        step.permission.map { app.isRequiredPermissionGranted($0) } ?? false
    }

    var body: some View {
        VStack(spacing: JarvisOnboardingLayout.sectionSpacing) {
            header
            HStack(alignment: .center, spacing: JarvisOnboardingLayout.columnSpacing) {
                JarvisOnboardingArtwork(step: step)
                    .frame(width: JarvisOnboardingLayout.columnWidth)
                pageContent
                    .frame(width: JarvisOnboardingLayout.columnWidth, alignment: .leading)
            }
            footer
        }
        .padding(JarvisOnboardingLayout.contentInset)
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            onContentSizeChange(size)
        }
        .background(colorScheme == .dark ? AnyShapeStyle(Color.jarvisBackground) : AnyShapeStyle(.background))
        .animation(JarvisMotion.animation(.easeInOut(duration: 0.24), reduceMotion: reduceMotion), value: step)
        .task {
            // Awaiting a system prompt must not advance or request the next permission.
            while !Task.isCancelled {
                app.refreshPermissionStatus()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            app.refreshPermissionStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            JarvisMascotMark(diameter: 28)
            Text("Jarvis")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(step.title)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            actions
        }
        .id(step)
        .transition(.opacity)
    }

    @ViewBuilder
    private var actions: some View {
        if step == .welcome {
            primaryButton("开始使用", icon: "arrow.right") { app.onboarding.finish() }
        } else {
            HStack(spacing: 20) {
                if isGranted, let permission = step.permission {
                    Label("\(permission.title)权限已开启", systemImage: "checkmark.circle.fill")
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(.green)
                        .fixedSize()
                        .frame(minHeight: 44)
                    primaryButton("下一步", icon: "arrow.right") { app.onboarding.advance() }
                } else {
                    primaryButton(primaryActionTitle, icon: "lock.open", action: performPrimaryAction)
                    Button("稍后设置") { app.onboarding.advance() }
                        .buttonStyle(.plain)
                        .font(JarvisTypography.control)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                Image(systemName: icon)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    private var primaryActionTitle: String {
        if requestedPermission == step.permission {
            return "前往系统设置"
        }
        return "获取\(step.permission?.title ?? "")权限"
    }

    private func performPrimaryAction() {
        if step == .welcome {
            app.onboarding.finish()
        } else if isGranted {
            app.onboarding.advance()
        } else if let permission = step.permission {
            if requestedPermission == permission {
                if !JarvisPrivacyPermissionAccess.openSettings(for: permission.privacyPermission) {
                    app.showToast("无法打开系统设置，请前往隐私与安全性中开启\(permission.title)权限")
                }
            } else {
                requestedPermission = permission
                app.requestRequiredPermission(permission)
            }
        }
    }

    private var footer: some View {
        ZStack {
            HStack {
                Button {
                    app.onboarding.goBack()
                } label: {
                    Label("上一步", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(step == .screenCapture)
                .opacity(step == .screenCapture ? 0 : 1)
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(JarvisOnboardingStep.allCases) { item in
                    Capsule()
                        .fill(item == step ? Color.jarvisAccent : Color.primary.opacity(0.12))
                        .frame(width: item == step ? 28 : 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(step.rawValue + 1) 步，共 \(JarvisOnboardingStep.allCases.count) 步")
        }
        .frame(minHeight: 28)
        .frame(maxWidth: .infinity)
    }
}
