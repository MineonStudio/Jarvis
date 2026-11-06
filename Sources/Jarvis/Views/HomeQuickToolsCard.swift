import SwiftUI

struct HomeQuickToolsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HomeDashboardCard(title: "工具使用排行榜", symbol: "chart.bar.xaxis", contentSpacing: 10, contentPadding: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 0) {
                ForEach(Array(app.toolUsage.rankedTools.enumerated()), id: \.element) { index, tool in
                    Button {
                        app.openTool(tool)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 19, weight: .medium)).foregroundStyle(Color.jarvisAccent)
                                .frame(width: 36, height: 36)
                                .background(Color.jarvisAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(alignment: .topTrailing) {
                                    HomeToolRankBadge(rank: index + 1).offset(x: 8, y: -6)
                                }
                            Text("\(Text(tool.navigationTitle).foregroundStyle(.primary))\(Text("*\(app.toolUsage.count(for: tool))次").foregroundStyle(.secondary))")
                                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                        .jarvisHoverFeedback(in: RoundedRectangle(cornerRadius: 10), scale: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("第 \(index + 1) 名，\(tool.navigationTitle)，使用 \(app.toolUsage.count(for: tool)) 次")
                    .help("打开\(tool.navigationTitle)")
                }
            }
        }
    }
}

private struct HomeToolRankBadge: View {
    let rank: Int
    private var colors: [Color] {
        switch rank {
        case 1: [Color(red: 1, green: 0.85, blue: 0.43), Color(red: 0.88, green: 0.54, blue: 0.08)]
        case 2: [Color(red: 0.85, green: 0.91, blue: 0.98), Color(red: 0.47, green: 0.57, blue: 0.70)]
        default: [Color(red: 0.96, green: 0.74, blue: 0.56), Color(red: 0.68, green: 0.39, blue: 0.23)]
        }
    }

    var body: some View {
        ZStack {
            if rank <= 3 {
                Image(systemName: "seal.fill").font(.system(size: 24))
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: (colors.last ?? .clear).opacity(0.25), radius: 2, y: 1)
                Image(systemName: "seal").font(.system(size: 23)).foregroundStyle(.white.opacity(0.55))
            } else {
                Circle().fill(.background).overlay { Circle().strokeBorder(.secondary.opacity(0.16)) }
            }
            Text("\(rank)").font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(rank <= 3 ? Color.white : .secondary)
        }
        .frame(width: 21, height: 21).accessibilityHidden(true)
    }
}
