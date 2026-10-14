import AppKit
import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ShareStore
    @State private var now = Date()
    @State private var isDropTargeted = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introduction
                if !store.errorMessage.isEmpty {
                    Label(store.errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        connectionCard.frame(minWidth: 370, maxWidth: .infinity, alignment: .topLeading)
                        directoryCard.frame(minWidth: 370, maxWidth: .infinity, alignment: .topLeading)
                    }
                    VStack(spacing: 16) {
                        connectionCard
                        directoryCard
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: 1040)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onReceive(clock) { now = $0 }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("局域网传输")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("Mac 与手机互传文件，手机无需安装 App。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var connectionCard: some View {
        sectionCard("连接", icon: "wifi") {
            if store.running {
                HStack(alignment: .center, spacing: 16) {
                    if let image = qrImage(store.address) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 144, height: 144)
                            .padding(8)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("扫码打开传输页面")
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Label("共享中", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .fontWeight(.semibold)
                        Text("用手机扫描二维码，打开传输网页。")
                            .font(.callout)
                        Text("也可以复制下方链接，在同一网络的设备上打开。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(store.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Button("复制链接") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.address, forType: .string)
                }
                .buttonStyle(.link)
                Divider()
                LabeledContent("本机 IP", value: URLComponents(string: store.address)?.host ?? "—")
                LabeledContent("已配对设备", value: "\(store.pairedDevices)")
                LabeledContent("运行时间", value: uptime)
            } else {
                emptyState("尚未共享", icon: "wifi", detail: "从工具栏启动共享，再用手机扫描二维码连接。")
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
    }

    private var directoryCard: some View {
        sectionCard("共享文件", icon: "folder") {
            directoryRow("共享目录", url: store.sharedDirectory, help: "手机可下载此目录中的文件")
            uploadDropZone
            if let message = store.importMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(store.importHasErrors ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            directoryRow("接收目录", url: store.receivedDirectory, help: "手机上传的文件保存到这里")
            Divider()
            LabeledContent("单文件上限", value: "2 GB")
        }
    }

    private var uploadDropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.tint)
            Text("上传文件到共享目录")
                .font(.callout.weight(.semibold))
            Text("选择文件，或从访达拖拽到这里")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.isImporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("选择文件…") { store.chooseSharedFiles() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(16)
        .background(
            Color.accentColor.opacity(isDropTargeted ? 0.12 : 0.035),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color.accentColor.opacity(isDropTargeted ? 0.7 : 0.3),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                )
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard !store.isImporting else { return false }
            let files = providers.filter {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            }
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

    private func directoryRow(_ title: String, url: URL, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(help).font(.caption).foregroundStyle(.secondary)
            Text(url.path).font(.caption).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            Button("在访达中打开") { NSWorkspace.shared.open(url) }.buttonStyle(.link)
        }
    }

    private func sectionCard(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private var uptime: String {
        guard let started = store.startedAt else { return "—" }
        let seconds = Int(now.timeIntervalSince(started))
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

    private func emptyState(_ title: String, icon: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
