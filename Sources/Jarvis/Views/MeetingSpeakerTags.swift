import SwiftUI

/// Tingo-style participant chips: a voice color, the display name, and a rename action.
struct MeetingSpeakerTags: View {
    let speakers: [MeetingSpeaker]
    let transcript: [MeetingTranscriptSegment]
    let playbackAvailable: Bool
    let isPreviewing: (String) -> Bool
    let onPreview: (String, MeetingTranscriptSegment) -> Void
    let onEdit: () -> Void
    @State private var samples: [String: MeetingTranscriptSegment] = [:]

    var body: some View {
        MeetingSpeakerTagsLayout {
            ForEach(speakers) { speaker in
                Button {
                    if let segment = samples[speaker.id] {
                        onPreview(speaker.id, segment)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(MeetingSpeakerColors.color(for: speaker.colorIndex)).frame(width: 8, height: 8)
                        Text(speaker.name).lineLimit(1)
                        Image(systemName: isPreviewing(speaker.id) ? "pause.fill" : "play.fill")
                            .font(.system(size: 8))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(isPreviewing(speaker.id) ? Color.jarvisAccent : .secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
                    .contentShape(Capsule())
                    .jarvisHoverFeedback(in: Capsule(), scale: 1)
                }
                .buttonStyle(.plain)
                .disabled(!playbackAvailable || samples[speaker.id] == nil)
                .accessibilityLabel("\(isPreviewing(speaker.id) ? "暂停试听" : "试听首次发言")：\(speaker.name)")
                .help(playbackAvailable && samples[speaker.id] != nil ? "试听\(speaker.name)的首次发言，再次点击暂停" : "暂无可试听的发言录音")
            }
            Button(action: onEdit) {
                Label("改名", systemImage: "pencil")
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("修改说话人姓名或合并分组")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("说话人")
        .onChange(of: transcript, initial: true) { _, segments in
            samples = MeetingSpeakerPreview.firstUtterances(in: segments)
        }
    }
}

enum MeetingSpeakerColors {
    static func color(for index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo]
        return colors[max(0, index) % colors.count]
    }
}

private struct MeetingSpeakerTagsLayout: Layout {
    private let spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (view, point) in zip(subviews, result.positions) {
            view.place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: min(bounds.width, view.sizeThatFits(.unspecified).width), height: 26)
            )
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var usedWidth: CGFloat = 0
        var positions: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let itemWidth = min(width, size.width)
            if x > 0, x + itemWidth > width {
                x = 0; y += 26 + spacing
            }
            positions.append(CGPoint(x: x, y: y))
            x += itemWidth + spacing
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: usedWidth, height: subviews.isEmpty ? 0 : y + 26), positions)
    }
}
