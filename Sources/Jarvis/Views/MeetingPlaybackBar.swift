import SwiftUI

struct MeetingPlaybackBar: View {
    @Bindable var playback: MeetingPlayback
    let url: URL?
    let revision: Int
    @State private var waveform: MeetingAudioWaveform?

    var body: some View {
        HStack(spacing: 16) {
            Button(action: playback.toggle) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17)).frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless).disabled(!playback.available)
            .accessibilityLabel(playback.isPlaying ? "暂停录音播放" : "播放录音")
            Text(MeetingRecordingStyle.formatTimestamp(playback.position))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Group {
                if let waveform {
                    MeetingWaveformView(
                        waveform: waveform,
                        progress: playback.duration > 0 ? playback.position / playback.duration : 0
                    ) {
                        playback.seek($0 * playback.duration)
                    }
                } else {
                    MeetingWaveformPlaceholder { playback.seek($0 * playback.duration) }
                }
            }.frame(height: 32).disabled(!playback.available)
            Text(playback.available ? MeetingRecordingStyle.formatTimestamp(playback.duration) : "录音待处理")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .task(id: "\(url?.path ?? ""):\(revision)") {
            waveform = nil
            guard let url else { return }
            let result = await MeetingAudioWaveformStore.shared.waveform(for: url)
            if !Task.isCancelled {
                waveform = result
            }
        }
    }
}
