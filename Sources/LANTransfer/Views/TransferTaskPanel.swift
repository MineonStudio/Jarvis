import JarvisDesignSystem
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
        VStack(alignment: .leading, spacing: JarvisSpacing.groupGap) {
            HStack(spacing: JarvisSpacing.controlGap) {
                Text("传输列表")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(filteredTransfers.count) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                TransferTaskFilterBar(selection: $filter)
            }

            if store.transfers.isEmpty {
                emptyState("暂无传输")
            } else if filteredTransfers.isEmpty {
                emptyState("没有符合筛选的任务")
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            columnHeader
                            ScrollView(.vertical) {
                                LazyVStack(spacing: 0) {
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
                                        Divider()
                                            .overlay(Color.primary.opacity(0.04))
                                            .padding(.leading, TransferListMetrics.rowInset + TransferListMetrics.thumbnail + JarvisSpacing.itemGap)
                                    }
                                }
                                .padding(.bottom, JarvisSpacing.controlGap)
                            }
                            .scrollIndicators(.automatic)
                        }
                        .frame(width: max(geometry.size.width, TransferListMetrics.minimumWidth), height: geometry.size.height)
                    }
                    .scrollIndicators(.automatic)
                }
            }
        }
        .padding(JarvisSpacing.panelInset)
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
        VStack(spacing: JarvisSpacing.itemGap) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var columnHeader: some View {
        HStack(spacing: TransferListMetrics.columnGap) {
            Text("文件")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("类型")
                .frame(width: TransferListMetrics.typeWidth, alignment: .leading)
            Text("接收 / 发送")
                .frame(width: TransferListMetrics.directionWidth, alignment: .leading)
            Text("设备")
                .frame(width: TransferListMetrics.deviceWidth, alignment: .leading)
            Text("状态")
                .frame(width: TransferListMetrics.statusWidth, alignment: .leading)
            Text("大小")
                .frame(width: TransferListMetrics.sizeWidth, alignment: .leading)
            Text("操作")
                .frame(width: TransferListMetrics.actionsWidth, alignment: .leading)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, TransferListMetrics.rowInset)
        .padding(.vertical, JarvisSpacing.controlGap)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct TransferTaskFilterBar: View {
    @Binding var selection: TransferTaskFilter
    @State private var hovered: TransferTaskFilter?

    var body: some View {
        HStack(spacing: JarvisSpacing.hairline) {
            ForEach(TransferTaskFilter.allCases) { item in
                let isSelected = selection == item
                Button {
                    selection = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, JarvisSpacing.controlGap)
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
        .padding(JarvisSpacing.textGap)
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .modifier(JarvisButtonShadowModifier())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("任务筛选")
    }
}
