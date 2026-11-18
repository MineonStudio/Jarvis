import AppKit
import LANTransfer
import SwiftUI

struct ContentView: View {
    static let homePointerCoordinateSpace = "jarvis.main-window"

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadedSection: AppSection
    @State private var settingsSelection: SettingsSection = .general
    @State private var homePointerTracker = JarvisHomePointerTracker()
    @State private var homeMonitor = HomeSystemMonitor()

    init(initialSection: AppSection) {
        _loadedSection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            JarvisSidebarNavigation(
                topItems: topNavigationItems,
                bottomItems: bottomNavigationItems,
                selection: selectedSectionBinding,
                title: { $0.navigationTitle },
                icon: { $0.icon },
                footerTitle: "设置",
                footerIcon: "gearshape",
                footerIsSelected: app.selectedSection == .settings,
                footerAction: { selectSection(.settings) },
                showsHeader: false
            )
            // Track the page below the toolbar. A tracker on the entire
            // NavigationSplitView also covers AppKit's native window buttons.
            .onContinuousHover(
                coordinateSpace: .named(Self.homePointerCoordinateSpace),
                perform: updateHomePointer
            )
            .background(Color.jarvisBackground)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(
                min: JarvisMetrics.sidebarMinimumWidth,
                ideal: JarvisMetrics.sidebarWidth,
                max: JarvisMetrics.sidebarMaximumWidth
            )
        } detail: {
            loadedSectionView
                .id(loadedSection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.jarvisBackground)
                .onContinuousHover(
                    coordinateSpace: .named(Self.homePointerCoordinateSpace),
                    perform: updateHomePointer
                )
        }
        .background(Color.jarvisBackground.ignoresSafeArea())
        .toolbarVisibility(.visible, for: .windowToolbar)
        .toolbarBackgroundVisibility(loadedSection == .home ? .hidden : .automatic, for: .windowToolbar)
        .tint(app.accentColorPreference.resolvedColor)
        .coordinateSpace(name: Self.homePointerCoordinateSpace)
        .onChange(of: loadedSection) { _, section in
            if section != .home {
                homePointerTracker.location = nil
            }
        }
        .onChange(of: app.selectedSection) { previous, next in
            if previous == .settings, next != .settings, app.taskPermissionPrompt?.presentation == .settingsPage {
                app.dismissTaskPermissionPrompt()
            }
        }
        .task(id: navigationTargetID) {
            let nextSection = app.selectedSection
            guard nextSection != loadedSection else { return }

            // Let the navigation indicator finish its interaction animation
            // before mounting a potentially heavy page hierarchy such as the
            // AI WebView. The tab selection itself is already committed.
            if !reduceMotion {
                do {
                    try await Task.sleep(nanoseconds: 180_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, nextSection == app.selectedSection else { return }
            // The sidebar indicator has settled. Replace the page in one
            // transaction so old and new module hierarchies never overlap.
            loadedSection = nextSection
        }
    }

    private func updateHomePointer(_ phase: HoverPhase) {
        guard loadedSection == .home else {
            homePointerTracker.location = nil
            return
        }
        if case let .active(location) = phase {
            if homePointerTracker.location != location {
                homePointerTracker.lastPointerMovement = Date()
            }
            homePointerTracker.location = location
        } else {
            homePointerTracker.location = nil
        }
    }

    private func selectSection(_ section: AppSection) {
        if let tool = section.skill {
            app.toolUsage.recordOpen(tool)
        }
        app.selectedSection = section
    }

    private var selectedSectionBinding: Binding<AppSection> {
        Binding(get: { app.selectedSection }, set: selectSection)
    }

    private var topNavigationItems: [AppSection] {
        [
            .home,
            .aiConversation,
            .skill(.screenshot),
            .skill(.screenRecording),
            .skill(.clipboard),
            .skill(.meetingNotes),
            .skill(.resume),
            .skill(.lanTransfer)
        ]
    }

    private var bottomNavigationItems: [AppSection] {
        [.skill(.wallpaper), .gamePlaza, .entertainment]
    }

    private var navigationTargetID: String {
        switch app.selectedSection {
        case .home:
            "home"
        case let .skill(skill):
            "skill|\(skill.id)"
        case .aiConversation:
            "ai-conversation|\(app.selectedAIProvider.id)"
        case .entertainment:
            "entertainment|\(app.selectedEntertainmentPlatform.id)"
        case .gamePlaza:
            "game-plaza"
        case .settings:
            "settings"
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch loadedSection {
        case .home: JarvisHomeView(pointerTracker: homePointerTracker, monitor: homeMonitor)
        case .aiConversation: AIConversationView()
        case .entertainment: EntertainmentView()
        case .gamePlaza: GamePlazaView()
        case .settings: SettingsView(selection: $settingsSelection)
        case .skill(.screenshot): ScreenshotView()
        case .skill(.screenRecording): ScreenRecordingView()
        case .skill(.clipboard): ClipboardView()
        case .skill(.windowLayout): WindowLayoutView()
        case .skill(.resume): ResumeContentView()
        case .skill(.wallpaper): WallpaperView()
        case .skill(.meetingNotes): MeetingView()
        case .skill(.lanTransfer): LANTransferModuleView()
        }
    }

    private var loadedSectionView: some View {
        detailView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JarvisToastHost: View {
    static let capsuleIdentity = "jarvis.toast"

    static func shouldAnimatePresence(from previous: String?, to next: String?) -> Bool {
        (previous == nil) != (next == nil)
    }

    let message: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let message {
                // Stable identity so a new action replaces the text in place
                // instead of playing the previous toast back out.
                JarvisToast(message: message)
                    .id(Self.capsuleIdentity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
            value: message != nil
        )
    }
}

extension View {
    func jarvisToastOverlay(_ message: String?) -> some View {
        overlay(alignment: .bottom) {
            JarvisToastHost(message: message)
                .padding(.bottom, JarvisSpacing.pageInset)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(false)
        }
    }
}
