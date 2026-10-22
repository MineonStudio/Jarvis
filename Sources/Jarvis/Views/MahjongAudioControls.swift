import SwiftUI

struct MahjongAudioControls: View {
    @Bindable var settings: MahjongAudioSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("音量")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Toggle("静音", isOn: $settings.isMuted)
                    .toggleStyle(.switch)
                    .fixedSize()
            }
            volume("总音量", value: $settings.overallVolume)
            volume("背景音乐", value: $settings.musicVolume)
            volume("游戏音效", value: $settings.effectsVolume)
            volume("语音播报", value: $settings.voiceVolume)
            HStack(spacing: 12) {
                Button("试听音效") { MahjongAudioPlayer.shared.previewEffects() }
                    .buttonStyle(MahjongGameButtonStyle())
                Button("恢复默认") { settings.restoreDefaults() }
                    .buttonStyle(MahjongGameButtonStyle())
            }
            .mahjongGlassGroup(spacing: 12)
            Text("大厅与牌桌共用欢快配乐，切换时连续播放；语音播报时音乐会自动降低。设置保存在本机。")
                .font(.system(size: 13))
                .foregroundStyle(MahjongVisualTheme.muted)
        }
        .foregroundStyle(MahjongVisualTheme.ivory)
        .tint(MahjongVisualTheme.accent)
    }

    private func volume(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .frame(width: 76, alignment: .leading)
            Slider(value: value, in: 0 ... 1)
                .accessibilityLabel(title)
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 14))
    }
}
