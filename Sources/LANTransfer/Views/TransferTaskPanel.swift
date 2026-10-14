import SwiftUI

@MainActor
struct TransferTaskPanel: View {
    @ObservedObject var store: ShareStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(.secondary)
                Text("传输任务")
                    .font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
                if !store.transfers.isEmpty {
                    Text("\(store.transfers.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if store.transfers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("暂无传输")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVGrid(columns: columns(for: geometry.size.width), spacing: 10) {
                            ForEach(store.transfers) { transfer in
                                TransferRow(
                                    transfer: transfer,
                                    canResend: store.canStartTask,
                                    onCancel: { store.cancel(transfer.id) },
                                    onOpen: { store.openResource(transfer) },
                                    onResend: { store.resend(transfer) }
                                )
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let count = width >= 960 ? 3 : (width >= 620 ? 2 : 1)
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }
}
