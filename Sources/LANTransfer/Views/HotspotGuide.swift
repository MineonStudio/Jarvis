import SwiftUI

public struct HotspotGuide: View {
    public init() {}

    @Environment(\.dismiss) private var dismiss
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("热点模式").font(.title.bold())
            Text("当路由器阻止设备互访时，可以让 Mac 连接手机热点。")
            step(1, "在手机上开启个人热点", "安卓或 iPhone 的设置中均可找到热点入口。")
            step(2, "让 Mac 加入手机热点", "从 macOS 菜单栏的 Wi-Fi 列表选择该热点。")
            step(3, "等待二维码刷新", "网络地址变化后，应用会自动重启服务。请扫描新的二维码。")
            HStack { Spacer(); Button("完成") { dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 460)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.headline).frame(width: 28, height: 28).background(.tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) { Text(title).fontWeight(.semibold); Text(detail).font(.callout).foregroundStyle(.secondary) }
        }
    }
}
