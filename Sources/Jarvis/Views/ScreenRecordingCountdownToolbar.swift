import SwiftUI

struct ScreenRecordingCountdownToolbar: View {
    let recorder: ScreenRecordingCoordinator

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: recorder.mode.icon).font(.system(size: 21))
                if recorder.mode != .display {
                    Text(recorder.recordingScopeSummary)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 180)
                        .help(recorder.recordingScopeSummary)
                }
            }
            Button(recorder.recordingButtonTitle) {}
                .screenRecordingPrimaryButton()
                .allowsHitTesting(false)
                .monospacedDigit()
                .accessibilityLabel(recorder.recordingButtonTitle)
            Button("取消") { recorder.cancelPreparation() }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 48, height: ScreenRecordingToolbarLayout.controlHeight)
        }
        .padding(.horizontal, 6)
    }
}
