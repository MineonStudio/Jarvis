import AppKit
import AVFoundation
import Combine
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum TransferCardMetrics {
    static let height: CGFloat = 112
    static let padding: CGFloat = 10
    static var thumb: CGFloat {
        height - padding * 2
    }

    static let corner: CGFloat = 14
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        case .pending, .accepted, .active: return .secondary
        }
    }

    private var resourceMissing: Bool {
        _ = resourceCheck
        guard let url = transfer.resourceURL else { return transfer.status == .completed }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return true }
        return values.isRegularFile != true || values.isSymbolicLink == true
    }

    private var hasFile: Bool {
        transfer.resourceURL != nil && !resourceMissing
    }

    private var showsStatus: Bool {
        resourceMissing || transfer.status == .failed || transfer.status == .cancelled
    }

    private var statusText: String {
        resourceMissing ? "文件已移除" : transfer.status.rawValue
    }

    private var sizeText: String {
        "\(TransferByteCount.string(from: transfer.done)) / \(TransferByteCount.string(from: transfer.total))"
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TransferFilePreview(url: resourceMissing ? nil : transfer.resourceURL, name: transfer.name)
                .frame(width: TransferCardMetrics.thumb, height: TransferCardMetrics.thumb)

            VStack(alignment: .leading, spacing: 6) {
                Text(transfer.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Text(sizeText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if showsStatus {
                        Text(statusText)
                            .foregroundStyle(statusColor)
                            .fixedSize()
                    }
                }
                HStack(spacing: 10) {
                    progressBar
                    Text("\(Int(transfer.fraction * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(TransferCardMetrics.padding)
        .frame(maxWidth: .infinity, minHeight: TransferCardMetrics.height, maxHeight: TransferCardMetrics.height, alignment: .leading)
        .background(resourceMissing ? Color.orange.opacity(0.09) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: TransferCardMetrics.corner))
        .overlay {
            if resourceMissing {
                RoundedRectangle(cornerRadius: TransferCardMetrics.corner).strokeBorder(Color.orange.opacity(0.35))
            }
        }
        .overlay(alignment: .bottom) {
            actionOverlay
        }
        .clipShape(RoundedRectangle(cornerRadius: TransferCardMetrics.corner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: TransferCardMetrics.corner, style: .continuous))
        .onHover { hovering in
            guard hovering != isHovered else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.16)) {
                isHovered = hovering
            }
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
        .accessibilityLabel(
            showsStatus
                ? "\(transfer.name)，\(statusText)，\(Int(transfer.fraction * 100))%"
                : "\(transfer.name)，\(Int(transfer.fraction * 100))%"
        )
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

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.18))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(2, geometry.size.width * transfer.fraction))
            }
        }
        .frame(height: 2)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var actionOverlay: some View {
        if isHovered {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                pill("打开", enabled: hasFile, action: onOpen)
                pill(copied ? "已复制" : "复制", enabled: hasFile, action: copyFile)
                if transfer.isInProgress {
                    pill("取消", action: onCancel)
                } else {
                    pill("重新发送", enabled: hasFile && canResend, action: onResend)
                }
                pill("删除", destructive: true, action: onDelete)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
        }
    }

    private func pill(
        _ title: String,
        destructive: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(TransferCardActionPillButtonStyle(destructive: destructive))
        .disabled(!enabled)
        .help(title == "重新发送" && !enabled ? "启动共享并等待当前任务结束后可重新发送" : title)
    }

    @ViewBuilder
    private var contextActions: some View {
        if transfer.isInProgress {
            Button("取消", action: onCancel)
        }
        if hasFile {
            Button("打开", action: onOpen)
            Button("复制") { copyFile() }
            Button("重新发送", action: onResend)
                .disabled(!canResend)
        }
        Divider()
        Button("删除", role: .destructive, action: onDelete)
    }

    private func copyFile() {
        guard hasFile, onCopy() else { return }
        copied = true
    }
}

private struct TransferCardActionPillButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(destructive ? Color.red : Color.primary)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .opacity(configuration.isPressed ? 0.68 : (isEnabled ? 1 : 0.45))
            .glassEffect(.regular.interactive(true), in: Capsule())
            .contentShape(Capsule())
            .shadow(color: .black.opacity(0.24), radius: 6, y: 2)
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
    }
}

private struct TransferFilePreview: View {
    let url: URL?
    let name: String
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .frame(width: TransferCardMetrics.thumb, height: TransferCardMetrics.thumb)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .task(id: "\(url?.path ?? "")|\(name)") {
                let fileURL = url
                let fileName = name
                let pixelSize = TransferCardMetrics.thumb * 2
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
