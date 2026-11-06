import SwiftUI

struct MeetingModelSettingsCard: View {
    @AppStorage(MeetingRecordingPreferences.hotwordsKey) private var hotwords = ""

    var body: some View {
        SettingsSectionCard("会议识别模型") {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.sectionSpacing) {
                MeetingModelSetupCard()
                VStack(alignment: .leading, spacing: SettingsFormMetrics.labelSpacing) {
                    Text("热词").font(SettingsTypography.itemTitle)
                    TextField("例如：项目名称、参会人姓名，用逗号分隔", text: $hotwords)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: SettingsFormMetrics.controlHeight, alignment: .leading)
                        .padding(.horizontal, JarvisSpacing.rowInset)
                        .modifier(SettingsCapsuleFieldModifier())
                        .accessibilityLabel("热词")
                }
            }
        }
    }
}

struct MeetingModelSetupCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.controlGap) {
            HStack(alignment: .center, spacing: JarvisSpacing.itemGap) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Paraformer-large").font(SettingsTypography.itemTitle)
                    Text("支持中英文，中文准、速度快、内存占用小。\n热词交给大模型在纪要里纠正。")
                        .font(SettingsTypography.itemSubtitle).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                statusSlot
            }
            .padding(.vertical, JarvisSpacing.controlGap)
            .frame(minHeight: SettingsFormMetrics.controlHeight)

            if case let .downloading(_, progress) = app.meetingModelState {
                ProgressView(value: progress)
                Text(downloadLabel).font(SettingsTypography.itemSubtitle).monospacedDigit().foregroundStyle(.secondary)
            }
            if case let .failed(_, _, message) = app.meetingModelState {
                Text(message).font(SettingsTypography.itemSubtitle).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .onAppear { app.refreshMeetingModelState() }
    }

    private var statusSlot: some View {
        ZStack(alignment: .trailing) {
            Button("移除") {}.buttonStyle(JarvisSecondaryButtonStyle()).hidden().accessibilityHidden(true)
            HStack(spacing: JarvisSpacing.controlGap) { statusView }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private var statusView: some View {
        switch app.meetingModelState {
        case .checking:
            Text("检测中").font(JarvisTypography.control).foregroundStyle(.secondary)
        case .removing:
            ProgressView().controlSize(.small)
            Text("移除中…").font(JarvisTypography.control).foregroundStyle(.secondary)
        case .downloading:
            ProgressView().controlSize(.small)
            Text("下载中…").font(JarvisTypography.control).foregroundStyle(.secondary)
            Button("取消", action: app.cancelMeetingModelPreparation).buttonStyle(JarvisSecondaryButtonStyle())
        case .ready:
            Button("移除") { app.removeMeetingModel(.paraformer) }
                .buttonStyle(JarvisSecondaryButtonStyle()).disabled(!app.canManageMeetingModels)
                .accessibilityLabel("移除 Paraformer-large 模型")
        case .notReady:
            Button("下载", action: app.prepareMeetingModels)
                .buttonStyle(JarvisSecondaryButtonStyle()).disabled(!app.canManageMeetingModels)
                .accessibilityLabel("下载 Paraformer-large 模型")
        case let .failed(_, operation, _):
            Button("重试") {
                if operation == .remove {
                    app.removeMeetingModel(.paraformer)
                } else {
                    app.prepareMeetingModels()
                }
            }
            .buttonStyle(JarvisSecondaryButtonStyle()).disabled(!app.canManageMeetingModels)
        }
    }

    private var downloadLabel: String {
        let done = ByteCountFormatter.string(fromByteCount: app.meetingModelDownloadCompletedBytes, countStyle: .file)
        guard app.meetingModelDownloadTotalBytes > 0 else { return "正在连接下载服务…" }
        let total = ByteCountFormatter.string(fromByteCount: app.meetingModelDownloadTotalBytes, countStyle: .file)
        return "\(done) / \(total) · 支持断点续传"
    }
}
