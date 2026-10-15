import SwiftUI

/// The loudness of a whole recording, drawn as bars, with the played part in the accent
/// colour and a playhead you can drag to any point.
struct MeetingWaveformView: View {
    let waveform: MeetingAudioWaveform
    let progress: Double
    let onSeek: (Double) -> Void

    @State private var dragProgress: Double?

    private var shownProgress: Double {
        min(1, max(0, dragProgress ?? progress))
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, canvasSize in
                let peaks = waveform.peaks
                guard !peaks.isEmpty, canvasSize.width > 0 else { return }
                let slot = canvasSize.width / CGFloat(peaks.count)
                let barWidth = max(1, slot * 0.62)
                let played = canvasSize.width * shownProgress
                let accent = Color.jarvisAccent
                let rest = Color.jarvisTextSecondary.opacity(0.35)
                for (index, peak) in peaks.enumerated() {
                    let height = max(2, CGFloat(peak) * canvasSize.height)
                    let x = CGFloat(index) * slot
                    let rect = CGRect(
                        x: x,
                        y: (canvasSize.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(x + barWidth / 2 <= played ? accent : rest)
                    )
                }
                if shownProgress > 0 {
                    let head = CGRect(
                        x: min(canvasSize.width - 1.5, played),
                        y: 0,
                        width: 1.5,
                        height: canvasSize.height
                    )
                    context.fill(Path(head), with: .color(accent))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard size.width > 0 else { return }
                        dragProgress = min(1, max(0, value.location.x / size.width))
                    }
                    .onEnded { value in
                        guard size.width > 0 else { return }
                        let target = min(1, max(0, value.location.x / size.width))
                        dragProgress = nil
                        onSeek(target)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("录音波形")
        .accessibilityValue("已播放 \(Int((shownProgress * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(1, progress + 0.05))
            case .decrement: onSeek(max(0, progress - 0.05))
            default: break
            }
        }
    }
}

/// The input level as it arrives, newest on the right.
struct MeetingAudioLevelBars: View {
    let levels: [Double]
    var isPaused = false

    var body: some View {
        Canvas { context, size in
            let slots = max(levels.count, 1)
            let slot = size.width / CGFloat(slots)
            let barWidth = max(1, slot * 0.55)
            let accent = isPaused ? Color.jarvisTextSecondary : Color.jarvisAccent
            for (index, level) in levels.enumerated() {
                // Older bars fade out, so the newest reading reads as the live one.
                let age = Double(levels.count - index) / Double(slots)
                let height = max(2, min(1, max(0, level)) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * slot,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(accent.opacity(isPaused ? 0.5 : 1 - age * 0.65))
                )
            }
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }
}

/// The placeholder shown before a recording's waveform is ready. Decoding runs in the
/// background, and the bar it leaves behind is honest about that rather than empty.
struct MeetingWaveformPlaceholder: View {
    @State private var phase: Double = 0

    var body: some View {
        Canvas { context, size in
            let bars = 64
            let slot = size.width / CGFloat(bars)
            let barWidth = max(1, slot * 0.62)
            for index in 0 ..< bars {
                let wave = sin((Double(index) / Double(bars) * 3 + phase) * .pi * 2)
                let height = max(3, (0.25 + 0.2 * wave) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * slot,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(Color.jarvisTextSecondary.opacity(0.28))
                )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityHidden(true)
    }
}
