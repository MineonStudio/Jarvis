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

    private var isCompact: Bool {
        width < 1040
    }

    private var valueFontSize: CGFloat {
        isCompact ? 22 : 25
    }

    private var metricSpacing: CGFloat {
        isCompact ? 8 : 12
    }

    private var cpuColor: Color {
        metricColor(HomeMetricLevel(fraction: monitor.snapshot.cpu))
    }

    private var memoryColor: Color {
        metricColor(HomeMetricLevel(fraction: monitor.snapshot.memoryFraction))
    }

    private var diskColor: Color {
        metricColor(HomeMetricLevel(fraction: monitor.snapshot.diskFraction))
    }

    private var gpuColor: Color {
        metricColor(HomeMetricLevel(fraction: monitor.snapshot.gpu))
    }

    private var temperatureReminderColor: Color {
        switch monitor.snapshot.thermalStatus {
        case .warm: .orange
        case .hot, .critical: .red
        default: .secondary
        }
    }

    private func metricColor(_ level: HomeMetricLevel?) -> Color {
        guard let level else { return .secondary }
        let rgb = level.rawValue
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    var body: some View {
        // A single row should fill the dashboard band. LazyVGrid keeps its
        // intrinsic height, leaving extra space around shorter metric cards.
        HStack(alignment: .top, spacing: 12) {
            metric(title: "CPU", symbol: "cpu", color: cpuColor) {
                usageBody(
                    monitor.snapshot.cpu, color: cpuColor,
                    detail: monitor.snapshot.thermalStatus.temperatureReminder(for: monitor.snapshot.temperatures.cpu),
                    detailColor: temperatureReminderColor,
                    temperature: HomeDashboardFormatting.temperature(monitor.snapshot.temperatures.cpu)
                )
                if let guidance = monitor.snapshot.thermalStatus.guidance {
                    Text(guidance)
                        .font(.system(size: 10))
                        .foregroundStyle(temperatureReminderColor)
                        .lineLimit(2)
                        .frame(height: 22, alignment: .leading)
                }
            }
            metric(title: "GPU", symbol: "square.stack.3d.up", color: gpuColor) {
                usageBody(
                    monitor.snapshot.gpu, color: gpuColor,
                    detail: monitor.snapshot.thermalStatus.temperatureReminder(for: monitor.snapshot.temperatures.gpu),
                    detailColor: temperatureReminderColor,
                    temperature: HomeDashboardFormatting.temperature(monitor.snapshot.temperatures.gpu)
                )
            }
            metric(title: "内存", symbol: "memorychip", color: memoryColor) {
                usageBody(
                    monitor.snapshot.memoryFraction, color: memoryColor,
                    detail: "\(HomeDashboardFormatting.bytes(monitor.snapshot.memoryUsed)) / \(HomeDashboardFormatting.bytes(monitor.snapshot.memoryTotal))"
                )
            }
            metric(title: "磁盘", symbol: "internaldrive", color: diskColor) {
                usageBody(
                    monitor.snapshot.diskFraction, color: diskColor,
                    detail: "\(HomeDashboardFormatting.bytes(monitor.snapshot.diskUsed)) / \(HomeDashboardFormatting.bytes(monitor.snapshot.diskTotal))"
                )
            }
            metric(title: "网络", symbol: "network", color: .purple) {
                let upload = HomeDashboardFormatting.rate(monitor.snapshot.upload)
                let download = HomeDashboardFormatting.rate(monitor.snapshot.download)
                VStack(alignment: .leading, spacing: 5) {
                    networkRow(upload, symbol: "arrow.up", title: "上传")
                    networkRow(download, symbol: "arrow.down", title: "下载")
                }
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .frame(height: 48, alignment: .leading)
            }
        }
    }

    private func usageBody(
        _ fraction: Double?, color: Color, detail: String? = nil, detailColor: Color = .secondary, temperature: String? = nil
    ) -> some View {
        HStack(spacing: 0) {
            ring(fraction, color: color, temperature: temperature)
            Spacer(minLength: metricSpacing)
            VStack(alignment: .trailing, spacing: 3) {
                Text(HomeDashboardFormatting.percent(fraction))
                    .font(.system(size: valueFontSize, weight: .semibold))
                    .monospacedDigit().lineLimit(1)
                if let detail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(detailColor)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .multilineTextAlignment(.trailing)
            .frame(height: 48, alignment: .topTrailing)
        }
        .frame(maxWidth: .infinity).frame(height: 48)
        .accessibilityElement(children: .combine)
    }

    private func networkRow(_ value: String, symbol: String, title: String) -> some View {
        HStack(spacing: 0) {
            Image(systemName: symbol).foregroundStyle(.purple).frame(width: 18)
            Spacer(minLength: metricSpacing)
            Text(value).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }

    private func ring(_ value: Double?, color: Color, temperature: String? = nil) -> some View {
        let diameter: CGFloat = isCompact ? 40 : 42
        return ZStack {
            Circle().stroke(color.opacity(0.12), lineWidth: 6)
            Circle().trim(from: 0, to: value ?? 0).stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let temperature {
                Text(temperature)
                    .font(.system(size: isCompact ? 10 : 11, weight: .medium))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: diameter - 10)
            }
        }
        .frame(width: diameter, height: diameter).padding(3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(temperature.map { "温度 \($0)" } ?? "")
        .accessibilityHidden(temperature == nil)
    }

    private func metric(
        title: String, symbol: String, color: Color,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                Spacer(minLength: 0)
            }
            .frame(height: 16)
            content()
        }
        .padding(isCompact ? 12 : 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .jarvisContentSurface(cornerRadius: 16)
    }
}
