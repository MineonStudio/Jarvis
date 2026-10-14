import Combine
import SwiftUI

@MainActor
public struct TransferRow: View {
    public let transfer: Transfer
    public let canResend: Bool
    public let onCancel: () -> Void
    public let onOpen: () -> Void
    public let onResend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travelling = false
    @State private var resourceCheck = 0

    public init(
        transfer: Transfer,
        canResend: Bool,
        onCancel: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onResend: @escaping () -> Void
    ) {
        self.transfer = transfer
        self.canResend = canResend
        self.onCancel = onCancel
        self.onOpen = onOpen
        self.onResend = onResend
    }

    private var accent: Color {
        transfer.direction == .download ? .blue : .green
    }

    private var resourceMissing: Bool {
        _ = resourceCheck
        guard let url = transfer.resourceURL else { return transfer.status == .completed }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return true }
        return values.isRegularFile != true || values.isSymbolicLink == true
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: resourceMissing ? "doc.questionmark" : (transfer.status == .completed ? "checkmark" : (transfer.direction == .download ? "square.and.arrow.up" : "square.and.arrow.down")))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(resourceMissing ? Color.orange : accent)
                    .frame(width: 34, height: 34)
                    .background((resourceMissing ? Color.orange : accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .symbolEffect(.pulse, options: .repeating, isActive: transfer.status == .active && !reduceMotion)
                VStack(alignment: .leading, spacing: 3) {
                    Text(transfer.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(transfer.direction.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Text(resourceMissing ? "文件已移除" : transfer.status.rawValue)
                    .foregroundStyle(resourceMissing ? Color.orange : (transfer.status == .failed ? Color.red : Color.secondary))
                Spacer(minLength: 0)
                Text("\(Int(transfer.fraction * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))

            route

            Text("\(ByteCountFormatter.string(fromByteCount: transfer.done, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: transfer.total, countStyle: .file))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            if !transfer.detail.isEmpty && transfer.detail != "历史文件" {
                Text(transfer.detail)
                    .font(.caption)
                    .foregroundStyle(transfer.status == .failed ? Color.red : Color.secondary)
                    .lineLimit(2)
            }

            if transfer.isInProgress {
                HStack {
                    Spacer()
                    Button("取消", action: onCancel)
                        .buttonStyle(.bordered)
                }
            } else if transfer.resourceURL != nil && !resourceMissing {
                HStack(spacing: 8) {
                    Button("重新发送", action: onResend)
                        .disabled(!canResend)
                        .help(canResend ? "发送此文件" : "启动共享并等待当前任务结束后可重新发送")
                    Button("打开", action: onOpen)
                    Spacer(minLength: 0)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(resourceMissing ? Color.orange.opacity(0.09) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if resourceMissing {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.35))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(transfer.direction.rawValue) \(transfer.name)，\(transfer.status.rawValue)，\(Int(transfer.fraction * 100))%")
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            resourceCheck &+= 1
        }
    }

    private var route: some View {
        GeometryReader { geometry in
            let travel = max(0, geometry.size.width - 8)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 4)
                Capsule()
                    .fill(accent.opacity(0.75))
                    .frame(width: max(4, geometry.size.width * transfer.fraction), height: 4)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: transfer.fraction)
                if transfer.status == .active && !reduceMotion {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                        .shadow(color: accent.opacity(0.5), radius: 4)
                        .offset(x: transfer.direction == .download ? (travelling ? travel : 0) : (travelling ? 0 : travel))
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: travelling)
                }
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: 8)
        .onAppear { travelling = true }
    }
}
