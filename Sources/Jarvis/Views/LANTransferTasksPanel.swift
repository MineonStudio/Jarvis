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
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(Color.jarvisAccent)
                            Text("暂无传输")
                                .font(JarvisTypography.cardTitle)
                        }
                        .frame(maxWidth: .infinity, minHeight: 190)
                        .jarvisContentSurface(cornerRadius: JarvisMetrics.cardRadius)
                    } else {
                        ForEach(store.transfers) { transfer in
                            TransferRow(transfer: transfer) { store.cancel(transfer.id) }
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
}
