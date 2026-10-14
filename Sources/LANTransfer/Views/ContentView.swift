import AppKit
import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ShareStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var copied = false
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.running {
                activeContent
            } else {
                waitingContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.running)
        .onReceive(clock) { now = $0 }
    }

    private var activeContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectionPanel
                HStack(alignment: .top, spacing: 16) {
                    sendPanel
                    receivePanel
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var waitingContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tint)
                .frame(width: 68, height: 68)
                .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 19))
            Text("等待连接")
                .font(.system(size: 17, weight: .semibold))
            if !store.errorMessage.isEmpty {
                Text(store.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var connectionPanel: some View {
        HStack(spacing: 20) {
            qrCode
            VStack(alignment: .leading, spacing: 13) {
                Label("连接设备", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 17, weight: .semibold))
                HStack(spacing: 10) {
                    Text(store.address)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.address, forType: .string)
                        copied = true
                    } label: {
                        Label(copied ? "已复制" : "复制链接", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .fixedSize()
                }
                HStack(spacing: 8) {
                    metric("已连接", value: "\(store.pairedDevices)", icon: "laptopcomputer.and.iphone")
                    metric("运行", value: uptime, icon: "clock")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(20)
        .frame(height: 228)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
        .onChange(of: store.address) { _, _ in copied = false }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
            Text(value).foregroundStyle(.primary)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }

    private var uptime: String {
        guard let started = store.startedAt else { return "—" }
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    @ViewBuilder
    private var qrCode: some View {
        if let image = qrImage(store.address) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 140, height: 140)
                .padding(8)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                .accessibilityLabel("连接二维码")
        }
    }

    private var sendPanel: some View {
        directionPanel("发送到其他设备", icon: "square.and.arrow.up", tint: .blue) {
            if let task = store.transfers.first(where: { $0.direction == .download && $0.isInProgress }) {
                transferAnimation(task, tint: .blue)
            } else if store.isImporting {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("正在准备")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 116)
            } else {
                uploadDropZone
            }
            if let message = store.importMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(store.importHasErrors ? .red : .secondary)
                    .lineLimit(2)
            }
        }
    }

    private var receivePanel: some View {
        directionPanel("从其他设备接收", icon: "square.and.arrow.down", tint: .green) {
            if let task = store.transfers.first(where: { $0.direction == .upload && $0.isInProgress }) {
                transferAnimation(task, tint: .green)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.green)
                    Text("等待文件")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 116)
            }
        }
    }

    private func directionPanel<Content: View>(
        _ title: String, icon: String, tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 204, alignment: .topLeading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    }

    private func transferAnimation(_ task: Transfer, tint: Color) -> some View {
        VStack(spacing: 13) {
            Image(systemName: task.direction == .download ? "square.and.arrow.up" : "square.and.arrow.down")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(0.11), in: Circle())
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
            if task.status == .active {
                ProgressView(value: task.fraction)
                    .tint(tint)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 4)
            }
            HStack(spacing: 6) {
                Text(task.status.rawValue)
                if task.status == .active {
                    Text("\(Int(task.fraction * 100))%")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .accessibilityElement(children: .combine)
    }

    private var uploadDropZone: some View {
        Button { store.chooseSharedFiles() } label: {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 25, weight: .light))
                    .foregroundStyle(.tint)
                Text("选择文件")
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 116)
            .background(Color.accentColor.opacity(isDropTargeted ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor.opacity(isDropTargeted ? 0.7 : 0.18), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
        }
        .buttonStyle(.plain)
        .disabled(!store.canStartTask)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard store.canStartTask,
                  let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
            else { return false }
            Task {
                if let url = await droppedFileURL(from: provider) {
                    store.importSharedFiles([url])
                }
            }
            return true
        }
    }

    private func droppedFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = if let fileURL = item as? URL {
                    fileURL
                } else if let data = item as? Data {
                    URL(dataRepresentation: data, relativeTo: nil)
                } else if let path = item as? String, path.hasPrefix("/") {
                    URL(fileURLWithPath: path)
                } else if let string = item as? String {
                    URL(string: string)
                } else {
                    nil
                }
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    private func qrImage(_ content: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
