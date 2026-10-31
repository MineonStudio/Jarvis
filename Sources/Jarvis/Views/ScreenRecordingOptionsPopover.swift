import AVFoundation
import SwiftUI

/// Hosted in a separate top-level panel, outside the launcher's fixed-height glass.
struct ScreenRecordingOptionsPopover: View {
    @Bindable var recorder: ScreenRecordingCoordinator
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: width, height: height)
        .onChange(of: recorder.settings) { _, _ in recorder.persistSettings() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("屏幕录制选项")
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            heading("计时器")
            ForEach(ScreenRecordingSettings.countdownOptions, id: \.self) { seconds in
                option(seconds == 0 ? "无" : "\(seconds) 秒", selected: recorder.settings.countdown == seconds) {
                    recorder.settings.countdown = seconds
                }
            }
            Divider().padding(.vertical, 5)
            heading("麦克风")
            option("无", selected: !recorder.settings.microphone) {
                recorder.settings.microphone = false
                recorder.settings.microphoneID = ""
            }
            option("系统默认麦克风", selected: recorder.settings.microphone && recorder.settings.microphoneID.isEmpty) {
                recorder.settings.microphone = true
                recorder.settings.microphoneID = ""
            }
            ForEach(recorder.microphones, id: \.uniqueID) { device in
                option(device.localizedName, selected: recorder.settings.microphone && recorder.settings.microphoneID == device.uniqueID) {
                    recorder.settings.microphone = true
                    recorder.settings.microphoneID = device.uniqueID
                }
            }
            Divider().padding(.vertical, 5)
            heading("录制格式")
            VStack(alignment: .leading, spacing: 8) {
                Picker("编码", selection: $recorder.settings.useHEVC) {
                    Text("H.264").tag(false)
                    Text("HEVC").tag(true)
                }
                Picker("画质", selection: $recorder.settings.quality) {
                    ForEach(ScreenRecordingQuality.allCases) { Text($0.title).tag($0) }
                }
                Picker("帧率", selection: $recorder.settings.frameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
            }
            .controlSize(.small)
            .font(.system(size: 13))
            .padding(.horizontal, 8).padding(.vertical, 6)
            option("显示鼠标", selected: recorder.settings.showsCursor) { recorder.settings.showsCursor.toggle() }
            option("显示鼠标点按", selected: recorder.settings.showsMouseClicks == true) {
                recorder.settings.showsMouseClicks = !(recorder.settings.showsMouseClicks == true)
            }
            option("包括系统音频", selected: recorder.settings.systemAudio) { recorder.settings.systemAudio.toggle() }
            if let message = recorder.message {
                Text(message).font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }.padding(8)
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 5).padding(.bottom, 2)
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        ScreenRecordingOptionRow(title: title, selected: selected, action: action)
    }
}

private struct ScreenRecordingOptionRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    .frame(width: 14).opacity(selected ? 1 : 0)
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 27)
            .background(hovered ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "已选择" : "未选择")
    }
}
