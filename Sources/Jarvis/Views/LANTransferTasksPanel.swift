import LANTransfer
import SwiftUI

struct LANTransferTasksModalOverlay: View {
    @Binding var isPresented: Bool

    var body: some View {
        JarvisCenteredModalOverlay(isPresented: $isPresented, title: "传输任务") {
            LANTransferTasksPanel { isPresented = false }
        }
    }
}

private struct LANTransferTasksPanel: View {
    let onClose: () -> Void
    @ObservedObject private var store = ShareStore.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("传输任务")
                        .font(SettingsTypography.pageTitle)

                    if store.transfers.isEmpty {
                        JarvisEmptyState(
                            icon: "arrow.up.arrow.down",
                            title: "暂无传输",
                            message: "手机上传或下载后，任务会显示在这里。"
                        )
                    } else {
                        ForEach(store.transfers) { transfer in
                            transferCard(transfer)
                        }
                    }
                }
                .frame(maxWidth: SettingsLayout.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(JarvisMetrics.pageInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.jarvisBackground)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.jarvisTextSecondary)
            .accessibilityLabel("关闭传输任务")
            .padding(.top, 15)
            .padding(.trailing, 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func transferCard(_ transfer: Transfer) -> some View {
        JarvisCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: transfer.direction == .upload ? "arrow.down.circle" : "arrow.up.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.jarvisAccent)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(transfer.name)
                            .font(JarvisTypography.bodyEmphasis)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(transfer.status.rawValue)
                            .font(JarvisTypography.caption)
                            .foregroundStyle(transfer.status == .failed ? .red : .secondary)
                    }

                    ProgressView(value: transfer.fraction)
                        .tint(Color.jarvisAccent)

                    HStack {
                        Text("\(transfer.direction.rawValue) · \(ByteCountFormatter.string(fromByteCount: transfer.done, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: transfer.total, countStyle: .file))")
                        Spacer(minLength: 8)
                        if transfer.status == .active {
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(transfer.bytesPerSecond), countStyle: .file))/s")
                        }
                    }
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)

                    if !transfer.detail.isEmpty {
                        Text(transfer.detail)
                            .font(JarvisTypography.caption)
                            .foregroundStyle(transfer.status == .failed ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if transfer.status == .active {
                    Button("取消") { store.cancel(transfer.id) }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                }
            }
        }
    }
}
