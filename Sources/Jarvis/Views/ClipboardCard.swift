import AppKit
import SwiftUI

struct ClipboardCard: View, Equatable {
    @Environment(AppModel.self) private var app
    @State private var isSensitiveRevealed = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSensitiveCopyConfirmation = false
    @State private var showingSensitivePreviewConfirmation = false
    let item: ClipboardItem
    let isSelected: Bool
    let cardSize: CGSize
    let maxPixelSize: Int
    let enablesHoverZoom: Bool
    let onClick: (Int, () -> Void) -> Void
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onCopy: () -> Void
    let onPreview: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item
            && lhs.isSelected == rhs.isSelected
            && lhs.cardSize == rhs.cardSize
            && lhs.maxPixelSize == rhs.maxPixelSize
            && lhs.enablesHoverZoom == rhs.enablesHoverZoom
    }

    private var previewContent: some View {
        Color.clear.overlay { previewLayer }.clipped()
    }

    private var previewLayer: some View {
        ZStack {
            if item.kind == .text {
                VStack(spacing: JarvisSpacing.controlGap) {
                    if let presentation = item.sensitivePresentation(
                        revealed: isSensitiveRevealed || !app.hideSensitiveClipboardContent
                    ) {
                        Text(presentation.displayText)
                            .font(
                                presentation.requiresReveal
                                    ? JarvisTypography.secondary
                                    : JarvisTypography.body
                            )
                            .foregroundStyle(
                                presentation.requiresReveal
                                    ? Color.jarvisTextSecondary
                                    : Color.primary
                            )
                            .lineLimit(presentation.requiresReveal ? 2 : 6)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel(
                                isSensitiveRevealed ? presentation.accessibilityText : item.preview
                            )

                        if presentation.requiresReveal {
                            Text("双击临时显示")
                                .font(JarvisTypography.caption)
                                .foregroundStyle(Color.jarvisTextSecondary)
                                .accessibilityHidden(true)
                        } else if presentation.sensitivity != nil,
                                  isSensitiveRevealed
                        {
                            Label("已临时显示", systemImage: "eye")
                                .font(JarvisTypography.caption)
                                .foregroundStyle(Color.jarvisTextSecondary)
                        }

                    } else {
                        Text(item.preview)
                            .font(JarvisTypography.body)
                            .lineLimit(6)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(HistoryGridMetrics.clipboardCardPadding)
            } else if item.kind == .file {
                VStack(spacing: JarvisSpacing.itemGap) {
                    Image(systemName: item.kind.icon)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(Color.jarvisAccent)
                    Text(item.preview)
                        .font(JarvisTypography.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, HistoryGridMetrics.clipboardCardPadding)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ClipboardItemPreview(item: item, maxPixelSize: maxPixelSize)
            }
        }
    }

    @ViewBuilder
    private var previewArea: some View {
        if ClipboardSharing.canProvide(for: item),
           !item.isSensitive || isSensitiveRevealed
        {
            previewContent
                .onDrag {
                    ClipboardSharing.itemProvider(for: item) ?? NSItemProvider()
                }
        } else {
            previewContent
        }
    }

    private func copyContent() {
        if item.isSensitive {
            showingSensitiveCopyConfirmation = true
        } else {
            onCopy()
        }
    }

    /// 读屏用的「时间戳，选中状态」。
    ///
    /// 别把它写回卡片 body 里那一长串修饰符中间的内联三元插值：release 构建下
    /// （CI 那台机器的编译器）整条表达式的类型检查会超时——`the compiler is unable
    /// to type-check this expression in reasonable time`，1.3.6 的发布就是这么红的。
    private var selectionDescription: String {
        let selection = isSelected ? "已选中" : "未选中"
        let favorite = item.isPinned ? "，已收藏" : ""
        return "\(item.shortTimestamp)，\(selection)\(favorite)"
    }

    private var cardAccessibilityHint: String {
        item.isSensitive && !isSensitiveRevealed
            ? "点击选择，双击临时显示"
            : "点击选择，双击打开预览"
    }

    private func openFromCard() {
        if item.isSensitive, !isSensitiveRevealed {
            isSensitiveRevealed = true
        } else {
            onDoubleClick()
        }
    }

    var body: some View {
        GalleryCard(
            size: cardSize, isSelected: isSelected, enablesHoverZoom: enablesHoverZoom,
            onClick: { onClick($0, openFromCard) },
            preview: { previewArea },
            leading: {
                Label(item.kind.title, systemImage: item.isPinned ? "star.fill" : item.kind.icon)
            },
            trailing: { Text(JarvisHistoryDateFormatting.string(from: item.createdAt)) }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            item.isSensitive
                ? "\(item.kind.title)，敏感内容"
                : "\(item.kind.title)，剪贴板内容"
        )
        .accessibilityValue(selectionDescription)
        .accessibilityHint(cardAccessibilityHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
        .accessibilityAction(named: "查看", openFromCard)
        .accessibilityAction(named: "复制") {
            copyContent()
        }
        .contextMenu {
            Button {
                if item.isSensitive {
                    showingSensitivePreviewConfirmation = true
                } else {
                    onPreview()
                }
            } label: {
                Label("查看", systemImage: "eye")
            }
            .disabled(!item.canFullscreenPreview)

            Button {
                copyContent()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }

            Button {
                onPin()
            } label: {
                Label(
                    item.isPinned ? "取消收藏" : "收藏",
                    systemImage: item.isPinned ? "star.slash" : "star"
                )
            }

            Divider()

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "删除这条剪贴板记录？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                onDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
        .confirmationDialog(
            "这段内容疑似包含敏感信息",
            isPresented: $showingSensitiveCopyConfirmation,
            titleVisibility: .visible
        ) {
            Button("显示并复制") {
                onCopy()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只有在你主动确认后，才会显示并复制原始内容。")
        }
        .confirmationDialog(
            "这段内容疑似包含敏感信息",
            isPresented: $showingSensitivePreviewConfirmation,
            titleVisibility: .visible
        ) {
            Button("显示并查看") {
                onPreview()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只有在你主动确认后，才会打开原始内容预览。")
        }
    }
}
