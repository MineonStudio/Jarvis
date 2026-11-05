import AppKit
import AVFoundation
import Combine
import ImageIO
import JarvisDesignSystem
import SwiftUI
import UniformTypeIdentifiers

enum TransferListMetrics {
    static let thumbnail: CGFloat = 40
    static let rowInset = JarvisSpacing.rowInset
    static let rowHeight: CGFloat = 76
    static let columnGap = JarvisSpacing.itemGap
    static let typeWidth: CGFloat = 56
    static let directionWidth: CGFloat = 72
    static let deviceWidth: CGFloat = 118
    static let statusWidth: CGFloat = 110
    static let sizeWidth: CGFloat = 80
    static let actionsWidth: CGFloat = 298
    static let minimumWidth: CGFloat = 1040
}

@MainActor
public struct TransferRow: View {
    public let transfer: Transfer
    public let canResend: Bool
    public let onCancel: () -> Void
    public let onOpen: () -> Void
    public let onResend: () -> Void
    public let onCopy: () -> Bool
    public let onDelete: () -> Void

    @State private var isHovered = false
    @State private var copied = false
    @State private var resourceCheck = 0

    public init(
        transfer: Transfer,
        canResend: Bool,
        onCancel: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onResend: @escaping () -> Void,
        onCopy: @escaping () -> Bool,
        onDelete: @escaping () -> Void
    ) {
        self.transfer = transfer
        self.canResend = canResend
        self.onCancel = onCancel
        self.onOpen = onOpen
        self.onResend = onResend
        self.onCopy = onCopy
        self.onDelete = onDelete
    }

    private var statusColor: Color {
        if resourceMissing {
            return .orange
        }
        switch transfer.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        case .pending, .accepted: return .secondary
        case .active: return .accentColor
        }
    }

    private var resourceMissing: Bool {
        _ = resourceCheck
        if transfer.isText {
            return false
        }
        guard let url = transfer.resourceURL else { return transfer.status == .completed }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return true }
        return values.isRegularFile != true || values.isSymbolicLink == true
    }

    private var hasFile: Bool {
        transfer.resourceURL != nil && !resourceMissing
    }

    private var canCopy: Bool {
        transfer.isText || hasFile
    }

    private var statusText: String {
        resourceMissing ? "文件已移除" : transfer.status.rawValue
    }

    private var statusIcon: String {
        if resourceMissing {
            return "exclamationmark.circle.fill"
        }
        switch transfer.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "minus.circle"
        case .pending, .accepted: return "clock"
        case .active: return "arrow.triangle.2.circlepath"
        }
    }

    private var title: String {
        guard let text = transfer.textContent else { return transfer.name }
        let preview = String(text.prefix(160))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return preview.isEmpty ? "空文本" : preview
    }

    private var subtitle: String? {
        if transfer.status == .failed, !transfer.detail.isEmpty {
            return transfer.detail
        }
        return nil
    }

    private var fileType: String {
        if transfer.isText {
            return "文本"
        }
        let ext = (transfer.name as NSString).pathExtension.uppercased()
        return ext.isEmpty ? "文件" : ext
    }

    private var sizeText: String {
        if transfer.status == .active {
            return "\(TransferByteCount.string(from: transfer.done)) / \(TransferByteCount.string(from: transfer.total))"
        }
        return TransferByteCount.string(from: transfer.total)
    }

    public var body: some View {
        HStack(spacing: TransferListMetrics.columnGap) {
            identity
            Text(fileType)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: TransferListMetrics.typeWidth, alignment: .leading)
            Label(transfer.direction.rawValue, systemImage: transfer.direction == .upload ? "arrow.down.left" : "arrow.up.right")
                .font(.system(size: 12, weight: .medium))
                .frame(width: TransferListMetrics.directionWidth, alignment: .leading)
            device.frame(width: TransferListMetrics.deviceWidth, alignment: .leading)
            status.frame(width: TransferListMetrics.statusWidth, alignment: .leading)
            Text(sizeText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: TransferListMetrics.sizeWidth, alignment: .leading)
            actions
        }
        .padding(.horizontal, TransferListMetrics.rowInset)
        .padding(.vertical, JarvisSpacing.itemGap)
        .frame(maxWidth: .infinity, minHeight: TransferListMetrics.rowHeight, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.035 : 0))
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if !hovering {
                copied = false
            }
        }
        .onTapGesture(count: 2) {
            if hasFile {
                onOpen()
            }
        }
        .contextMenu { contextActions }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title)，\(transfer.direction.rawValue)，\(statusText)")
        .accessibilityAction(named: "打开") {
            if hasFile {
                onOpen()
            }
        }
        .accessibilityAction(named: "复制") { copyFile() }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            resourceCheck &+= 1
        }
    }

    private var identity: some View {
        HStack(spacing: JarvisSpacing.itemGap) {
            TransferFilePreview(url: resourceMissing ? nil : transfer.resourceURL, name: transfer.name, isText: transfer.isText)
                .frame(width: TransferListMetrics.thumbnail, height: TransferListMetrics.thumbnail)
                .background(Color.accentColor.opacity(transfer.isText ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: JarvisSpacing.textGap) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(transfer.isText ? .tail : .middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(transfer.textContent ?? transfer.name)
    }

    private var device: some View {
        Text(transfer.targetDeviceIP ?? "其他设备")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.textGap) {
            HStack(spacing: JarvisSpacing.iconGap) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .foregroundStyle(resourceMissing || transfer.status == .failed ? statusColor : .primary)
                if transfer.status == .active {
                    Spacer(minLength: 0)
                    Text("\(Int(transfer.fraction * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)

            if transfer.status == .active {
                progressBar
            }
            if transfer.status == .active, transfer.bytesPerSecond.isFinite, transfer.bytesPerSecond > 0 {
                Text("\(TransferByteCount.string(from: Int64(min(transfer.bytesPerSecond, 1e15))))/s")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(transfer.detail.isEmpty ? statusText : transfer.detail)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Color.accentColor.opacity(0.15))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * transfer.fraction)
                }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var actions: some View {
        HStack(spacing: JarvisSpacing.controlGap) {
            actionButton("打开", width: 44, enabled: hasFile, action: onOpen)
            actionButton(copied ? "已复制" : "复制", width: 56, enabled: canCopy, action: copyFile)
            actionButton("重新发送", width: 68, enabled: canCopy && canResend && !transfer.isInProgress, action: onResend)
            actionButton("取消传输", width: 68, enabled: transfer.isInProgress, action: onCancel)
            actionButton("删除", icon: "trash", width: 30, destructive: true, action: onDelete)
        }
        .frame(width: TransferListMetrics.actionsWidth, alignment: .leading)
    }

    private func actionButton(
        _ title: String,
        icon: String? = nil,
        width: CGFloat,
        enabled: Bool = true,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(systemName: icon)
                } else {
                    Text(title)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .frame(width: width, height: 30)
            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
            .modifier(JarvisButtonShadowModifier())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(title)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var contextActions: some View {
        if transfer.isInProgress {
            Button("取消", action: onCancel)
        }
        if hasFile {
            Button("打开", action: onOpen)
        }
        if canCopy {
            Button("复制") { copyFile() }
            Button("重新发送", action: onResend)
                .disabled(!canResend)
        }
        Divider()
        Button("删除", role: .destructive, action: onDelete)
    }

    private func copyFile() {
        guard canCopy, onCopy() else { return }
        copied = true
    }
}

private struct TransferFilePreview: View {
    let url: URL?
    let name: String
    var isText = false
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .frame(width: TransferListMetrics.thumbnail, height: TransferListMetrics.thumbnail)
            .overlay {
                if isText {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.tint)
                } else if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .task(id: "\(url?.path ?? "")|\(name)") {
                let fileURL = url
                let fileName = name
                let pixelSize = TransferListMetrics.thumbnail * 2
                image = await Task.detached(priority: .utility) {
                    await TransferFileIcon.image(url: fileURL, name: fileName, pixelSize: pixelSize)
                }.value
            }
    }
}

private enum TransferFileIcon {
    static func image(url: URL?, name: String, pixelSize: CGFloat) async -> NSImage {
        if let url, FileManager.default.fileExists(atPath: url.path) {
            if isVideo(url: url, name: name), let poster = await videoPoster(url: url, pixelSize: pixelSize) {
                return poster
            }
            if let thumbnail = rasterThumbnail(url: url, pixelSize: pixelSize) {
                return thumbnail
            }
            return fileIcon(url: url, name: name, pixelSize: pixelSize)
        }
        return fileIcon(url: url, name: name, pixelSize: pixelSize)
    }

    private static func fileIcon(url: URL?, name: String, pixelSize: CGFloat) -> NSImage {
        let icon: NSImage
        if let url, FileManager.default.fileExists(atPath: url.path) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            let ext = (name as NSString).pathExtension
            icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        }
        icon.size = NSSize(width: pixelSize, height: pixelSize)
        return icon
    }

    private static func isVideo(url: URL, name: String) -> Bool {
        let ext = (url.pathExtension.isEmpty ? (name as NSString).pathExtension : url.pathExtension).lowercased()
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg"].contains(ext) {
            return true
        }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    private static func videoPoster(url: URL, pixelSize: CGFloat) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixelSize, height: pixelSize)
        let time = CMTime(seconds: 0.05, preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, _ in
                guard let cgImage else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                )
            }
        }
    }

    private static func rasterThumbnail(url: URL, pixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rawType = CGImageSourceGetType(source),
              let type = UTType(rawType as String),
              type.conforms(to: .image)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
