import SwiftUI

struct MeetingModelSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsSectionCard("会议识别模型") {
            content
        }
        .onAppear {
            app.refreshMeetingModelState()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.sectionSpacing) {
            ForEach(MeetingModelPreparationStage.allCases) { stage in
                MeetingModelSettingsRow(stage: stage)
            }

            if case let .failed(nil, _, message) = app.meetingModelState {
                Text(message)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct MeetingModelSettingsRow: View {
    @Environment(AppModel.self) private var app
    let stage: MeetingModelPreparationStage

    private var isReady: Bool {
        app.meetingModelAvailability.isReady(for: stage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.controlGap) {
            HStack(alignment: .center, spacing: JarvisSpacing.itemGap) {
                VStack(alignment: .leading, spacing: SettingsFormMetrics.labelSpacing) {
                    Text(stage.title)
                        .font(SettingsTypography.itemTitle)
                    Text(stage.modelName)
                        .font(JarvisTypography.monospacedSmall)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 8)
                action
                    .fixedSize(horizontal: true, vertical: false)
            }

            if case let .downloading(activeStage, progress) = app.meetingModelState,
               activeStage == stage
            {
                HStack(spacing: JarvisSpacing.controlGap) {
                    ProgressView(value: progress)
                        .tint(Color.jarvisAccent)
                    Text("下载中 · \(Int(progress * 100))%")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }

            if case let .failed(failedStage, operation, message) = app.meetingModelState,
               failedStage == stage
            {
                Text("\(operation == .remove ? "移除失败" : "下载失败")：\(message)")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, JarvisSpacing.controlGap)
    }

    @ViewBuilder
    private var action: some View {
        switch app.meetingModelState {
        case .checking:
            Button("检查中") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case let .downloading(activeStage, _):
            if activeStage == stage {
                Button("取消") { app.cancelMeetingModelPreparation() }
                    .buttonStyle(JarvisSecondaryButtonStyle())
            } else {
                availabilityAction
            }
        case let .removing(activeStage):
            if activeStage == stage {
                HStack(spacing: JarvisSpacing.iconGap) {
                    ProgressView().controlSize(.small)
                    Text("移除中")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            } else {
                availabilityAction
            }
        case let .failed(failedStage, operation, _) where failedStage == stage:
            if operation == .remove {
                Button("重试移除", role: .destructive) {
                    app.removeMeetingModel(stage)
                }
                .buttonStyle(JarvisSecondaryButtonStyle(tint: .red))
                .disabled(!app.canManageMeetingModels)
            } else {
                Button("重试下载") {
                    app.prepareMeetingModel(stage)
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
                .disabled(!app.canManageMeetingModels)
            }
        default:
            availabilityAction
        }
    }

    @ViewBuilder
    private var availabilityAction: some View {
        if isReady {
            if stage == .chineseTranscription {
                Text("系统已安装")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
            } else {
                Button("移除", role: .destructive) {
                    app.removeMeetingModel(stage)
                }
                .buttonStyle(JarvisSecondaryButtonStyle(tint: .red))
                .disabled(!app.canManageMeetingModels)
                .help("移除本机下载的 \(stage.title) 模型")
            }
        } else {
            Button("下载") {
                app.prepareMeetingModel(stage)
            }
            .buttonStyle(JarvisPrimaryButtonStyle())
            .disabled(!app.canManageMeetingModels)
        }
    }
}
