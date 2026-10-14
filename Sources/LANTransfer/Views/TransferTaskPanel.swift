import SwiftUI

@MainActor
struct TransferTaskPanel: View {
    @ObservedObject var store: ShareStore
    @State private var filter: TransferTaskFilter = .all
    @State private var pendingDelete: Transfer?

    private var filteredTransfers: [Transfer] {
        store.transfers.filter { filter.matches($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundStyle(.secondary)
                Text("传输任务")
                    .font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 8)
                TransferTaskFilterBar(selection: $filter)
            }

            if store.transfers.isEmpty {
                emptyState("暂无传输")
            } else if filteredTransfers.isEmpty {
                emptyState("没有符合筛选的任务")
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVGrid(columns: columns(for: geometry.size.width), spacing: 10) {
                            ForEach(filteredTransfers) { transfer in
                                TransferRow(
                                    transfer: transfer,
                                    canResend: store.canStartTask,
                                    onCancel: { store.cancel(transfer.id) },
                                    onOpen: { store.openResource(transfer) },
                                    onResend: { store.resend(transfer) },
                                    onCopy: { store.copyResource(transfer) },
                                    onDelete: { pendingDelete = transfer }
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
        .confirmationDialog(
            "删除这条传输任务？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: {
                    if !$0 {
                        pendingDelete = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pendingDelete {
                    store.delete(pendingDelete.id)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func emptyState(_ title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func columns(for width: CGFloat) -> [GridItem] {
        let count = width >= 960 ? 3 : (width >= 620 ? 2 : 1)
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }
}

private struct TransferTaskFilterBar: View {
    @Binding var selection: TransferTaskFilter
    @State private var hovered: TransferTaskFilter?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TransferTaskFilter.allCases) { item in
                let isSelected = selection == item
                Button {
                    selection = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background {
                            Capsule().fill(
                                isSelected
                                    ? Color.accentColor
                                    : (hovered == item ? Color.primary.opacity(0.08) : .clear)
                            )
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    Color.accentColor.opacity(isSelected ? 0.42 : 0),
                                    lineWidth: 0.75
                                )
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hovered = hovering ? item : (hovered == item ? nil : hovered)
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 32)
        .glassEffect(.regular.interactive(false), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("任务筛选")
    }
}
