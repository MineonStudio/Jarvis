import SwiftUI

@MainActor
public struct TransferRow: View {
    public let transfer: Transfer
    public let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travelling = false

    public init(transfer: Transfer, onCancel: @escaping () -> Void) {
        self.transfer = transfer
        self.onCancel = onCancel
    }

    private var isSending: Bool {
        transfer.direction == .download
    }

    private var accent: Color {
        isSending ? .blue : .green
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            directionIcon
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(transfer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(transfer.status.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(transfer.status == .failed ? Color.red : Color.secondary)
                }
                HStack(spacing: 9) {
                    Text(transfer.direction.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                    route
                    Text("\(Int(transfer.fraction * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: transfer.done, countStyle: .file))
                    Text("/")
                    Text(ByteCountFormatter.string(fromByteCount: transfer.total, countStyle: .file))
                    if transfer.status == .active, transfer.bytesPerSecond > 0 {
                        Spacer(minLength: 4)
                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(transfer.bytesPerSecond), countStyle: .file))/s")
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                if !transfer.detail.isEmpty {
                    Text(transfer.detail)
                        .font(.caption)
                        .foregroundStyle(transfer.status == .failed ? Color.red : Color.secondary)
                }
            }
            if transfer.status == .active {
                Button("取消", action: onCancel)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(transfer.direction.rawValue) \(transfer.name)，\(transfer.status.rawValue)，\(Int(transfer.fraction * 100))%")
    }

    private var directionIcon: some View {
        Image(systemName: transfer.status == .completed ? "checkmark" : (isSending ? "arrow.up.right" : "arrow.down.left"))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 38, height: 38)
            .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
            .symbolEffect(.pulse, options: .repeating, isActive: transfer.status == .active && !reduceMotion)
    }

    private var route: some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 8)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 4)
                Capsule()
                    .fill(accent.opacity(0.7))
                    .frame(width: max(4, geometry.size.width * transfer.fraction), height: 4)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: transfer.fraction)
                if transfer.status == .active, !reduceMotion {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: accent.opacity(0.5), radius: 4)
                        .offset(x: isSending ? (travelling ? width : 0) : (travelling ? 0 : width))
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: travelling)
                }
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: 8)
        .onAppear { travelling = true }
    }
}
