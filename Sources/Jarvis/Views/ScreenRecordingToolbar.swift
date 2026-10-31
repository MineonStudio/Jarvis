import SwiftUI

/// Desktop recording launcher. Recording state stays in the coordinator.
struct ScreenRecordingToolbar: View {
    @Bindable var recorder: ScreenRecordingCoordinator

    var body: some View {
        Group {
            if recorder.isPreparing {
                ScreenRecordingCountdownToolbar(recorder: recorder)
            } else {
                configurationControls
            }
        }
        .screenRecordingToolbarSurface(width: recorder.isPreparing ? nil : ScreenRecordingToolbarLayout.width)
        .onChange(of: recorder.isPreparing) { _, _ in recorder.panelController?.resizeLauncher() }
        .onChange(of: recorder.mode) { _, _ in recorder.panelController?.updateRegionBorder() }
        .onChange(of: recorder.displayID) { _, _ in recorder.region = nil }
        .onChange(of: recorder.settings) { _, _ in recorder.persistSettings() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("屏幕录制操作栏")
    }

    private var configurationControls: some View {
        HStack(spacing: ScreenRecordingToolbarLayout.spacing) {
            ForEach(ScreenRecordingMode.allCases) { mode in
                Button {
                    recorder.mode = mode
                    if mode == .window {
                        recorder.selectWindow()
                    }
                    if mode == .region {
                        recorder.selectRegion()
                    }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: ScreenRecordingToolbarLayout.modeWidth, height: ScreenRecordingToolbarLayout.controlHeight)
                        .captureToolbarSelection(isSelected: recorder.mode == mode)
                }
                .disabled(recorder.refreshing || recorder.selectingTarget)
                .accessibilityHint(mode.recordingHint)
                .onHover { hovering in
                    recorder.panelController?.showModeHint(hovering ? mode : nil)
                }
                .accessibilityLabel("录制\(mode.title)")
            }
            Divider().frame(height: 24).padding(.horizontal, 3)
            ScreenRecordingOptionsButton(recorder: recorder)
                .frame(width: 46, height: ScreenRecordingToolbarLayout.controlHeight)
            Button { recorder.start() } label: {
                HStack(spacing: 4) {
                    Text("录制")
                    if recorder.settings.countdown > 0 {
                        Image(systemName: "timer").font(.system(size: 11, weight: .semibold))
                        Text("\(recorder.settings.countdown)秒").monospacedDigit()
                    }
                }
            }
            .screenRecordingPrimaryButton(width: 96)
            .accessibilityLabel(recorder.recordingStartHint)
            .help(recorder.recordingStartHint)
            .disabled(!recorder.canStart)
            .opacity(recorder.canStart ? 1 : 0.5)
        }
    }
}
