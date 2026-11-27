import Combine
import SwiftUI
import Translation

/// Forwards row `objectWillChange` so each row updates while its system status changes.
@MainActor
final class LanguagePackSettingsStore: ObservableObject {
    private let models: [ScreenshotTranslationLanguage: LanguagePackRowModel]
    private var cancellables: Set<AnyCancellable> = []
    private var activationRefreshTask: Task<Void, Never>?
    private var lifecycleGeneration = 0

    init(service: any LanguagePackService = SystemLanguagePackService()) {
        var models: [ScreenshotTranslationLanguage: LanguagePackRowModel] = [:]
        for target in ScreenshotTranslationLanguage.packTargets {
            models[target] = LanguagePackRowModel(target: target, service: service)
        }
        self.models = models
        for model in models.values {
            model.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }

    func model(for target: ScreenshotTranslationLanguage) -> LanguagePackRowModel {
        if let model = models[target] {
            return model
        }
        // #10：init 已为所有 packTargets 建好 model，这里不应到达。
        // 断言 + 现场补一个，避免强制解包崩溃。
        assertionFailure("LanguagePackSettingsStore 缺少 \(target) 的 model")
        return LanguagePackRowModel(target: target, service: SystemLanguagePackService())
    }

    func checkAll(excluding completedTarget: ScreenshotTranslationLanguage? = nil) async {
        for target in ScreenshotTranslationLanguage.packTargets where target != completedTarget {
            guard !Task.isCancelled else {
                return
            }
            await model(for: target).refresh()
        }
    }

    func openLanguageSettings() -> Bool {
        SystemLanguagePackService.openLanguageSettings()
    }

    func refreshAfterActivation() {
        // Assets are shared with screenshot translation and other apps, so a
        // refresh cannot depend on opening Settings through this card.
        refreshStatuses()
    }

    func consumeSession(
        _ handler: any LanguagePackSessionHandling,
        for target: ScreenshotTranslationLanguage
    ) async {
        let generation = lifecycleGeneration
        await model(for: target).consumeSession(handler)
        guard generation == lifecycleGeneration else {
            return
        }
        // Preparing a pair installs both languages; update every affected row.
        // Clearing sessionConfiguration can cancel translationTask itself, so
        // the store owns this refresh independently of that SwiftUI task.
        await refreshStatuses(excluding: target).value
    }

    @discardableResult
    private func refreshStatuses(
        excluding target: ScreenshotTranslationLanguage? = nil
    ) -> Task<Void, Never> {
        activationRefreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            await self?.checkAll(excluding: target)
        }
        activationRefreshTask = task
        return task
    }

    func tearDownAll() {
        lifecycleGeneration += 1
        activationRefreshTask?.cancel()
        activationRefreshTask = nil
        for model in models.values {
            model.tearDown()
        }
    }
}

struct ScreenshotLanguagePackSettingsCard: View {
    @StateObject private var store = LanguagePackSettingsStore()

    var body: some View {
        VStack(alignment: .leading, spacing: JarvisSpacing.itemGap) {
            HStack {
                Text("截图翻译语言包")
                    .font(SettingsTypography.cardTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button("刷新状态") {
                    store.refreshAfterActivation()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }
            SettingsContentPanel {
                VStack(spacing: JarvisSpacing.controlGap) {
                    ForEach(ScreenshotTranslationLanguage.packTargets) { target in
                        LanguagePackRowView(
                            model: store.model(for: target),
                            openLanguageSettings: store.openLanguageSettings,
                            consumeSession: { await store.consumeSession($0, for: target) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await store.checkAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshAfterActivation()
        }
        .onDisappear { store.tearDownAll() }
    }
}

private struct LanguagePackRowView: View {
    @ObservedObject var model: LanguagePackRowModel
    let openLanguageSettings: () -> Bool
    let consumeSession: (any LanguagePackSessionHandling) async -> Void
    @State private var showingSettingsOpenFailure = false

    var body: some View {
        HStack(spacing: JarvisSpacing.itemGap) {
            Text(model.target.title)
                .font(SettingsTypography.itemTitle)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 8)
            statusSlot
        }
        .padding(.vertical, JarvisSpacing.controlGap)
        .frame(minHeight: SettingsFormMetrics.controlHeight)
        // 挂在背景上。直接修饰这一行时，translationTask 的首帧会把行高撑开一下。
        .background {
            Color.clear
                .translationTask(model.sessionConfiguration) { session in
                    await consumeSession(
                        SystemLanguagePackSessionHandler(target: model.target, session: session)
                    )
                }
        }
        .animation(nil, value: model.phase)
        .alert("无法打开系统设置", isPresented: $showingSettingsOpenFailure) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("无法打开“系统设置”的“语言与地区”页面，请稍后重试。")
        }
        .id("language-pack-\(model.target.rawValue)-\(model.channelGeneration)")
    }

    /// 打开设置时相位还是「检测中」。先按最终按钮占住高度，状态回来才不会把整张卡片顶下去。
    private var statusSlot: some View {
        ZStack(alignment: .trailing) {
            Button("移除") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .hidden()
                .accessibilityHidden(true)
            HStack(spacing: JarvisSpacing.controlGap) {
                statusView
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.phase {
        case .checking:
            Text("检测中").font(JarvisTypography.control).foregroundStyle(Color.secondary)
        case .installed:
            Text("已下载").font(JarvisTypography.control).foregroundStyle(Color.secondary)
                .fixedSize()
            Button("移除") {
                showingSettingsOpenFailure = !openLanguageSettings()
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("在系统设置中移除\(model.target.title)语言包")
            .help("打开系统设置的语言与地区页面管理翻译语言包")
        case .supported:
            Button("下载") { model.startDownload() }
                .buttonStyle(JarvisSecondaryButtonStyle())
        case .unsupported:
            Text("系统不支持")
                .font(JarvisTypography.control)
                .foregroundStyle(Color.secondary)
                .fixedSize()
        case .downloading:
            ProgressView().controlSize(.small)
            Text("下载中…").font(JarvisTypography.control).foregroundStyle(Color.secondary)
            Button("取消") { model.cancelDownload() }
                .buttonStyle(JarvisSecondaryButtonStyle())
        case let .failed(message):
            Text(message)
                .font(JarvisTypography.control)
                .foregroundStyle(Color.red)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Button("重试") { model.startDownload() }
                .buttonStyle(JarvisSecondaryButtonStyle())
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}
