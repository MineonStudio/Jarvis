import AppKit
import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ShareStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now = Date()
    @State private var isDropTargeted = false
    @State private var copied = false
    @State private var recentSharedFiles: [URL] = []
    @State private var recentReceivedFiles: [URL] = []
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !store.errorMessage.isEmpty {
                    Label(store.errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                connectionPanel
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        sendPanel.frame(minWidth: 300, maxWidth: .infinity)
                        receivePanel.frame(minWidth: 300, maxWidth: .infinity)
                    }
                    VStack(spacing: 16) {
                        sendPanel
                        receivePanel
                    }
                }
                if !store.transfers.isEmpty {
                    transferPanel
                }
            }
            .padding(30)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onReceive(clock) {
            now = $0
            if Int(now.timeIntervalSince1970) % 10 == 0 {
                refreshRecentFiles()
            }
        }
        .onAppear(perform: refreshRecentFiles)
        .onChange(of: store.importMessage) { _, _ in refreshRecentFiles() }
        .onChange(of: store.transfers.filter { $0.status == .completed }.map(\.id)) { _, _ in
            refreshRecentFiles()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: store.running)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("局域网传输")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Label(store.running ? "共享中" : "未开启", systemImage: store.running ? "circle.fill" : "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.running ? .green : .secondary)
        }
    }

    private var connectionPanel: some View {
        Group {
            if store.running {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 28) {
                        qrCode
                        connectionDetails
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        qrCode
                        connectionDetails
                    }
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "wifi")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tint)
                        .frame(width: 78, height: 78)
                        .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
                    Text("等待连接")
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 124, alignment: .center)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var qrCode: some View {
        if let image = qrImage(store.address) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 152, height: 152)
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("连接二维码")
        }
    }

    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 17) {
            Label("连接设备", systemImage: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
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
            }
            HStack(spacing: 8) {
                metric("已连接", value: "\(store.pairedDevices)", icon: "laptopcomputer.and.iphone")
                metric("运行", value: uptime, icon: "clock")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: store.address) { _, _ in copied = false }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
            Text(value).foregroundStyle(.primary)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }

    private var sendPanel: some View {
        directionPanel(
            "发送", icon: "arrow.up.right", tint: .blue,
            active: store.transfers.contains { $0.status == .active && $0.direction == .download }
        ) {
            uploadDropZone
            recentFileList(recentSharedFiles)
            folderButton("共享文件", url: store.sharedDirectory)
            if let message = store.importMessage {
                Label(message, systemImage: store.importHasErrors ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(store.importHasErrors ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var receivePanel: some View {
        directionPanel(
            "接收", icon: "arrow.down.left", tint: .green,
            active: store.transfers.contains { $0.status == .active && $0.direction == .upload }
        ) {
            recentFileList(recentReceivedFiles)
            folderButton("接收文件", url: store.receivedDirectory)
        }
    }

    private func recentFileList(_ files: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if files.isEmpty {
                Text("暂无文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                ForEach(files, id: \.path) { url in
                    Button { NSWorkspace.shared.open(url) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(url.path)
                    if url != files.last {
                        Divider()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func refreshRecentFiles() {
        recentSharedFiles = recentFiles(in: store.sharedDirectory)
        recentReceivedFiles = recentFiles(in: store.receivedDirectory)
    }

    private func recentFiles(in directory: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        )) ?? []
        return Array(urls.filter {
            guard let values = try? $0.resourceValues(forKeys: keys) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }.sorted {
            let left = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            return left > right
        }.prefix(10))
    }

    private func directionPanel(
        _ title: String, icon: String, tint: Color, active: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
                    .symbolEffect(.pulse, options: .repeating, isActive: active && !reduceMotion)
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }

    private var uploadDropZone: some View {
        Button { store.chooseSharedFiles() } label: {
            VStack(spacing: 9) {
                if store.isImporting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tint)
                }
                Text(store.isImporting ? "正在添加" : "添加文件")
                    .font(.system(size: 14, weight: .semibold))
                Text("拖放文件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(Color.accentColor.opacity(isDropTargeted ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(Color.accentColor.opacity(isDropTargeted ? 0.7 : 0.18), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
        }
        .buttonStyle(.plain)
        .disabled(store.isImporting)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard !store.isImporting else { return false }
            let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
            guard !files.isEmpty else { return false }
            Task {
                var urls: [URL] = []
                for provider in files {
                    if let url = await droppedFileURL(from: provider) {
                        urls.append(url)
                    }
                }
                store.importSharedFiles(urls)
            }
            return true
        }
    }

    private func folderButton(_ title: String, url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 9) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(url.path)
    }

    private var transferPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("传输任务").font(.system(size: 17, weight: .semibold))
            ForEach(store.transfers.prefix(4)) { transfer in
                TransferRow(transfer: transfer) { store.cancel(transfer.id) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
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

    private var uptime: String {
        guard let started = store.startedAt else { return "—" }
        let seconds = max(0, Int(now.timeIntervalSince(started)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
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
