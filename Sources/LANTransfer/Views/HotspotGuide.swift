import SwiftUI

public struct HotspotGuide: View {
    public init() {}

    @Environment(\.dismiss) private var dismiss
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("热点连接").font(.title2.bold())
            step(1, "手机开启热点")
            step(2, "Mac 连接热点")
            step(3, "扫描新二维码")
            HStack { Spacer(); Button("完成") { dismiss() }.buttonStyle(.borderedProminent) }
        }
        .padding(28)
        .frame(width: 360)
    }

    private func step(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.15), in: Circle())
            Text(title).fontWeight(.medium)
        }
    }
}
