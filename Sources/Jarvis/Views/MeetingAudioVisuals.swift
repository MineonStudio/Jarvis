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
                // Half the slot: the gaps are what make the shape readable, and a narrow
                // card must not draw the bars over each other.
                let barWidth = min(slot, max(0.8, slot * 0.5))
                let played = canvasSize.width * shownProgress
                let accent = Color.jarvisAccent
                let rest = Color.jarvisTextSecondary.opacity(0.35)
                for (index, peak) in peaks.enumerated() {
                    // A silent stretch stays empty: the envelope is scaled to its own
                    // loudest moment, so zero really does mean nothing was said.
                    guard peak > 0.001 else { continue }
                    let height = max(1, CGFloat(peak) * canvasSize.height)
                    let x = CGFloat(index) * slot
                    let rect = CGRect(
                        x: x,
                        y: (canvasSize.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    let shape = barWidth >= 2
                        ? Path(roundedRect: rect, cornerRadius: barWidth / 2)
                        : Path(rect)
                    context.fill(shape, with: .color(x + barWidth / 2 <= played ? accent : rest))
                }
                if shownProgress > 0 {
                    let head = CGRect(
                        x: min(max(0, played), max(0, canvasSize.width - 1.5)),
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
            let barWidth = min(slot, max(1, slot * 0.5))
            let accent = isPaused ? Color.jarvisTextSecondary : Color.jarvisAccent
            for (index, level) in levels.enumerated() {
                // Older bars fade out, so the newest reading reads as the live one. A floor
                // on the height would turn silence into a solid block of bars.
                let age = Double(levels.count - index) / Double(slots)
                let height = min(1, max(0, level)) * size.height
                guard height > 0.5 else { continue }
                let rect = CGRect(
                    x: CGFloat(index) * slot,
                    y: (size.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let shape = barWidth >= 2
                    ? Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    : Path(rect)
                context.fill(
                    shape,
                    with: .color(accent.opacity(isPaused ? 0.45 : 0.9 - age * 0.55))
                )
            }
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("系统音频电平")
        .accessibilityValue(
            isPaused ? "已暂停" : "\(Int((levels.last ?? 0) * 100))%"
        )
    }
}

/// The placeholder shown before a recording's waveform is ready. Decoding runs off the main
/// actor, and the bar it leaves behind is honest about that rather than empty. It seeks like
/// the real one, so the control is never missing while the envelope is being built.
struct MeetingWaveformPlaceholder: View {
    let onSeek: (Double) -> Void

    @State private var phase: Double = 0

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let bars = 32
                let slot = size.width / CGFloat(bars)
                let barWidth = min(slot, max(0.8, slot * 0.5))
                for index in 0 ..< bars {
                    let wave = sin((Double(index) / Double(bars) * 2 + phase) * .pi * 2)
                    let height = max(3, (0.18 + 0.12 * wave) * size.height)
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
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard geometry.size.width > 0 else { return }
                        onSeek(min(1, max(0, value.location.x / geometry.size.width)))
                    }
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
        .accessibilityElement()
        .accessibilityLabel("录音波形（正在生成）")
        .accessibilityHint("拖动可定位")
    }
}
