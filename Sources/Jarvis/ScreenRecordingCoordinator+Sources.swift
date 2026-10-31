import AppKit
import AVFoundation
import ScreenCaptureKit

extension ScreenRecordingCoordinator {
    func refreshSources() async {
        guard !refreshing, !isActive else { return }
        refreshing = true
        defer { refreshing = false }
        guard CGPreflightScreenCaptureAccess() else {
            sourceContent = nil
            displays = []; windows = []; preview = nil
            message = "需要屏幕录制权限。请授权后点击刷新；若系统要求重新打开应用，请完成后重试。"
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            sourceContent = content
            displays = content.displays
            windows = content.windows.filter {
                $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
                    && $0.frame.width >= 50 && $0.frame.height >= 50 && $0.windowLayer == 0
            }.sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
            if !displays.contains(where: { $0.displayID == displayID }) {
                displayID = displays.first?.displayID
                region = nil
            }
            if !windows.contains(where: { $0.windowID == windowID }) {
                windowID = windows.first?.windowID
            }
            message = nil
            await refreshPreview()
        } catch { message = "无法获取录制目标：\(error.localizedDescription)" }
    }

    func requestScreenPermission() {
        if !CGRequestScreenCaptureAccess() {
            _ = JarvisPrivacyPermissionAccess.openSettings(for: .screenCapture)
        }
        Task { await refreshSources() }
    }

    func makeFilter(content: SCShareableContent? = nil) throws -> SCContentFilter {
        guard let content = content ?? sourceContent else { throw ScreenRecordingError.message("请刷新录制目标。") }
        if mode == .window {
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenRecordingError.message("所选窗口已经关闭，请重新选择。")
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenRecordingError.message("所选显示器已断开，请重新选择。")
        }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        filter.includeMenuBar = true
        return filter
    }

    func refreshPreview() async {
        let revision = UUID()
        previewRevision = revision
        preview = nil
        guard !isActive, let filter = try? makeFilter() else { return }
        let config = SCStreamConfiguration()
        let rect = mode == .region ? region.map { ScreenRecordingGeometry.sourceRect(from: $0, screenHeight: selectedDisplay?.frame.height ?? 0) } : nil
        if let rect {
            config.sourceRect = rect
        }
        let source = rect?.size ?? filter.contentRect.size
        let size = ScreenRecordingQuality.hd.outputSize(for: source)
        config.width = Int(size.width); config.height = Int(size.height)
        config.showsCursor = settings.showsCursor
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard previewRevision == revision, !isActive else { return }
            preview = NSImage(cgImage: image, size: .zero)
        } catch {
            if previewRevision == revision {
                message = "预览暂不可用，可刷新目标后重试：\(error.localizedDescription)"
            }
        }
    }

    func selectRegion() {
        guard !isActive, !selectingTarget else { return }
        region = nil
        guard let displayID,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == displayID
              }) else { return }
        selectingTarget = true
        panelController?.showLauncher()
        Task { [self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard selectingTarget else { return }
            selectionController.select(on: screen) { [weak self] rect in
                guard let self else { return }
                selectingTarget = false
                if let rect {
                    region = rect
                }
                showingSetup = true
                panelController?.showLauncher()
                Task { await self.refreshPreview() }
            }
        }
    }
}
