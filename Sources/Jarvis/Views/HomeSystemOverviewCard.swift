import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HomeSystemOverviewCard: View {
    let monitor: HomeSystemMonitor
    @State private var deviceImage: NSImage?

    var body: some View {
        HomeDashboardCard(title: "系统概览", symbol: "desktopcomputer", contentSpacing: 10, contentPadding: 14) {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Group {
                        if let deviceImage {
                            Image(nsImage: deviceImage).resizable().interpolation(.high).scaledToFit()
                        } else {
                            Image(systemName: "desktopcomputer").resizable().scaledToFit().foregroundStyle(Color.jarvisAccent)
                        }
                    }.frame(width: 96, height: 80).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(monitor.deviceName).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Text(monitor.macInfo.modelName).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(monitor.macInfo.modelYear ?? "年份待识别")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                VStack(spacing: 8) {
                    info("芯片", value: monitor.macInfo.chip)
                    info("内存", value: monitor.macInfo.memory)
                    info("存储", value: storage)
                    info("系统", value: monitor.macInfo.systemVersion)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .task(id: monitor.macInfo.modelIdentifier) {
            let types = UTType.types(
                tag: monitor.macInfo.modelIdentifier,
                tagClass: UTTagClass(rawValue: "com.apple.device-model-code"), conformingTo: nil
            )
            if let type = types.first {
                deviceImage = NSWorkspace.shared.icon(for: type)
            } else {
                deviceImage = NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)
            }
        }
    }

    private var storage: String {
        guard let bytes = monitor.macInfo.storageBytes else { return "—" }
        let capacity = ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
        return monitor.macInfo.storageMedium?.lowercased() == "ssd" ? "\(capacity) SSD" : capacity
    }

    private func info(_ label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity)
    }
}
