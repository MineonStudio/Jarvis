import SwiftUI

struct DiagnosticsSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        SettingsContentPanel {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
            HStack(spacing: JarvisSpacing.groupGap) {
                VStack(alignment: .leading, spacing: SettingsFormMetrics.labelSpacing) {
                    Text("诊断日志")
                        .font(SettingsTypography.itemTitle)
                    Text("导出日志以排查运行问题")
                        .font(SettingsTypography.itemSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("导出日志") {
                    app.exportDiagnostics()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }
        }
    }
}
