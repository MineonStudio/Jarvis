import AppKit

extension ScreenRecordingCoordinator {
    func selectWindow() {
        guard !isActive, !selectingTarget else { return }
        selectingTarget = true
        panelController?.showLauncher()
        let mainWindow = NSApp.windows.first {
            $0.frameAutosaveName == JarvisMainWindowController.frameAutosaveName && $0.isVisible
                && $0.isOnActiveSpace && !$0.isMiniaturized
        }
        mainWindow?.orderOut(nil)
        Task { [self] in
            await refreshSources()
            guard selectingTarget else { mainWindow?.orderBack(nil); return }
            windowID = nil
            guard !windows.isEmpty else {
                selectingTarget = false
                mainWindow?.orderBack(nil)
                showingSetup = true
                panelController?.showLauncher()
                return
            }
            windowSelectionController.select(windowIDs: Set(windows.map(\.windowID))) { [weak self] id in
                guard let self else { return }
                windowID = id
                selectingTarget = false
                mainWindow?.orderBack(nil)
                showingSetup = true
                panelController?.showLauncher()
                Task { await self.refreshPreview() }
            }
        }
    }
}
