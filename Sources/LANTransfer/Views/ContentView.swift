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
    @State private var textDraft = ""
    @FocusState private var isTextComposerFocused: Bool
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
        GeometryReader { geometry in
            let padding: CGFloat = 16
            let spacing: CGFloat = 16
            let innerWidth = max(0, geometry.size.width - padding * 2)
            let innerHeight = max(0, geometry.size.height - padding * 2)
            let availableWidth = max(0, innerWidth - spacing)
            HStack(alignment: .top, spacing: spacing) {
                connectionPanel
                    .frame(width: availableWidth * 2 / 3, height: innerHeight)
                sendPanel
                    .frame(width: availableWidth / 3, height: innerHeight)
            }
            .padding(padding)
        }
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
        HStack(spacing: 18) {
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
                connectedDevicesRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
    private var connectedDevicesRow: some View {
        if store.connectedDevices.isEmpty {
            Text("暂无已连接设备")
                .foregroundStyle(.tertiary)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(store.connectedDevices.enumerated()), id: \.element.id) { index, device in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hue: device.colorHue, saturation: 0.68, brightness: 0.82))
                                .frame(width: 7, height: 7)
                            Text("设备\(index + 1)(\(device.ipAddress))")
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: 18)
        }
    }

    @ViewBuilder
    private var qrCode: some View {
        if let image = qrImage(store.address) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
                .padding(8)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("连接二维码")
        }
    }

    private var sendPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 6))
                Text("发送到")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Picker("传输设备", selection: $store.selectedDeviceIP) {
                    if store.connectedDevices.isEmpty {
                        Text("无设备").tag(nil as String?)
                    } else {
                        ForEach(Array(store.connectedDevices.enumerated()), id: \.element.id) { index, device in
                            Text("设备\(index + 1)(\(device.ipAddress))")
                                .tag(Optional(device.id))
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(store.connectedDevices.isEmpty || !store.canStartTask)
                .fixedSize()
                Spacer(minLength: 0)
            }
            if let task = store.transfers.first(where: { $0.direction == .download && $0.isInProgress }) {
                transferAnimation(task, tint: .accentColor)
            } else if store.isImporting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在准备")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    textComposer
                        .frame(height: 32)
                    uploadDropZone
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            if let message = store.importMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(store.importHasErrors ? .red : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func transferAnimation(_ task: Transfer, tint: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: task.direction == .download ? "square.and.arrow.up" : "square.and.arrow.down")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                Text(task.status.rawValue)
                if task.status == .active {
                    Text("\(Int(task.fraction * 100))%")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            if task.status == .active {
                ProgressView(value: task.fraction)
                    .tint(tint)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var uploadDropZone: some View {
        Button { store.chooseSharedFiles() } label: {
            Text("选择文件")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor.opacity(isDropTargeted ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
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

    private var textComposer: some View {
        HStack(spacing: 8) {
            TextField("消息", text: $textDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isTextComposerFocused)
                .onSubmit(sendDraft)
                .disabled(!store.canStartTask)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(.regularMaterial, in: Capsule())
            Button {
                sendDraft()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.10), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!store.canStartTask || textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("发送文本")
        }
    }

    private func sendDraft() {
        guard textDraft.utf8.count <= 200_000 else {
            store.sendText(textDraft)
            return
        }
        store.sendText(textDraft)
        textDraft = ""
        isTextComposerFocused = false
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
