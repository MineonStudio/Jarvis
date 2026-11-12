import AppKit
import SwiftUI

struct HomeDashboardCard<Content: View>: View {
    let title: String
    let symbol: String
    var actionTitle: String?
    var action: (() -> Void)?
    var contentSpacing: CGFloat = 14
    var contentPadding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            HStack(spacing: 7) {
                Image(systemName: symbol).foregroundStyle(Color.jarvisAccent)
                Text(title).foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain).foregroundStyle(Color.jarvisAccent).font(
                            .system(size: 11, weight: .medium)
                        )
                }
            }.font(.system(size: 14, weight: .semibold))
            content
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .jarvisContentSurface(cornerRadius: 16)
    }
}

struct HomeDashboardHeader: View {
    let pointerTracker: JarvisHomePointerTracker
    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    welcome(at: context.date)
                    Spacer(minLength: 24)
                    clock(at: context.date)
                }
                VStack(alignment: .leading, spacing: 12) {
                    welcome(at: context.date)
                    clock(at: context.date)
                }
            }
        }
    }

    private func welcome(at date: Date) -> some View {
        HStack(spacing: 16) {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named(ContentView.homePointerCoordinateSpace))
                let direction = pointerTracker.location.map { location in
                    CGSize(
                        width: min(1, max(-1, (location.x - frame.midX) / 240)),
                        height: min(1, max(-1, (location.y - frame.midY) / 180))
                    )
                }
                JarvisMascotView(diameter: 60, pointerDirection: direction, promptBubble: AnyView(EmptyView()))
            }.frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 7) {
                Text("\(HomeDashboardFormatting.greeting(at: date))，\(displayName)")
                    .font(.system(size: 24, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Text("把琐事交给 Jarvis，专注眼前的事。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.fixedSize(horizontal: true, vertical: false)
        }
    }

    private var displayName: String {
        let name = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? NSUserName() : name
    }

    private func clock(at date: Date) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(date.formatted(.dateTime.month().day().weekday(.wide)))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
        }.fixedSize()
    }
}

struct HomeMetricsGrid: View {
    let monitor: HomeSystemMonitor
    let width: CGFloat
    @Environment(AppModel.self) private var app

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: width >= 760 ? 4 : 2), spacing: 12
        ) {
            metric(title: "CPU", symbol: "cpu", color: .jarvisAccent) {
                HStack(spacing: 12) {
                    ring(monitor.snapshot.cpu, color: .jarvisAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(HomeDashboardFormatting.percent(monitor.snapshot.cpu)).font(
                            .system(size: 25, weight: .semibold)
                        ).monospacedDigit()
                        Text("全系统使用率").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HomeSparkline(values: monitor.cpuHistory, color: .jarvisAccent, maximum: 1)
            }
            metric(title: "内存", symbol: "memorychip", color: .green) {
                HStack(spacing: 12) {
                    ring(monitor.snapshot.memoryFraction, color: .green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(HomeDashboardFormatting.percent(monitor.snapshot.memoryFraction)).font(
                            .system(size: 25, weight: .semibold)
                        ).monospacedDigit()
                        Text(
                            "\(HomeDashboardFormatting.bytes(monitor.snapshot.memoryUsed)) / \(HomeDashboardFormatting.bytes(monitor.snapshot.memoryTotal))"
                        )
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                HomeSparkline(values: monitor.memoryHistory, color: .green, maximum: 1)
            }
            metric(title: "磁盘", symbol: "internaldrive", color: .orange) {
                HStack(spacing: 12) {
                    ring(monitor.snapshot.diskFraction, color: .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(HomeDashboardFormatting.percent(monitor.snapshot.diskFraction))
                            .font(.system(size: 25, weight: .semibold)).monospacedDigit()
                        Text("可用 \(HomeDashboardFormatting.bytes(monitor.snapshot.diskAvailable))")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }
                HomeSparkline(values: monitor.diskHistory, color: .orange, maximum: 1)
            }
            metric(title: "网络", symbol: "network", color: .purple) {
                HomeNetworkMetric(
                    upload: monitor.snapshot.upload,
                    download: monitor.snapshot.download,
                    history: monitor.networkHistory,
                    display: monitor.identity,
                    onCopied: { app.showToast($0) }
                )
            }
        }
    }

    private func ring(_ value: Double?, color: Color) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.12), lineWidth: 6)
            Circle().trim(from: 0, to: value ?? 0).stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }.frame(width: 44, height: 44).padding(3).accessibilityHidden(true)
    }

    private func metric(
        title: String, symbol: String, color: Color, spacing: CGFloat = 10, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .jarvisContentSurface(cornerRadius: 16)
    }
}

struct HomeSparkline: View {
    let values: [Double]
    let color: Color
    let maximum: Double?
    var height: CGFloat = 22
    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let ceiling = max(maximum ?? values.max() ?? 1, 1e-6)
            var line = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: size.width * CGFloat(index) / CGFloat(max(29, values.count - 1)),
                    y: size.height * (1 - min(1, max(0, value / ceiling)))
                )
                if index == 0 {
                    line.move(to: point)
                } else {
                    line.addLine(to: point)
                }
            }
            context.stroke(
                line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }.frame(height: height).accessibilityHidden(true)
    }
}
