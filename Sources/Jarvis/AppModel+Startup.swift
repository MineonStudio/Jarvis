import Foundation

extension AppModel {
    func startDeferredStartup() {
        let startedAt = Date()
        JarvisLog.info(
            category: .lifecycle,
            event: "startup.load.begin"
        )
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            let snapshot = await startupRepository.load()
            guard !Task.isCancelled else { return }
            applyStartupSnapshot(snapshot)
            JarvisLog.info(
                category: .lifecycle,
                event: "startup.load.complete",
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1000,
                result: "success",
                fields: [
                    "clipboardRecordCount": String(snapshot.clipboardItems.count),
                    "screenshotRecordCount": String(snapshot.screenshotHistory.count)
                ]
            )
        }
    }

    private func applyStartupSnapshot(_ snapshot: JarvisStartupSnapshot) {
        clipboardItems = snapshot.clipboardItems
        screenshotHistory = snapshot.screenshotHistory
        latestScreenshotData = snapshot.cachedScreenshot
        clipboardCacheUsage = snapshot.clipboardCacheUsage

        let audit = clipboardCacheStore.audit(items: clipboardItems)
        JarvisLog.notice(
            category: .clipboard,
            event: "cache.startupAudit",
            result: audit.missingReferenceCount == 0 ? "healthy" : "missingReferences",
            fields: audit.logFields(autoCleanupEnabled: clipboardCacheAutoCleanupEnabled).merging(
                [
                    "directory": JarvisLogRedactor.path(clipboardCacheDirectoryURL.path)
                ],
                uniquingKeysWith: { _, new in new }
            )
        )

        // 旧版本只有一张工作截图。历史为空时补进历史，但补这一份也不能超出共享空间。
        if screenshotHistory.isEmpty, let cachedScreenshot = snapshot.cachedScreenshot {
            let incoming = Int64(cachedScreenshot.count)
            let clipboard = clipboardCacheStore.usage()
            let latestBytes = screenshotCacheStore.storedBytes()
            let fits = SharedCacheAdmission.allows(
                usedBytes: clipboard.usedBytes + latestBytes,
                capacityBytes: clipboard.capacityBytes,
                incomingBytes: incoming
            )
            if fits, let migratedItem = screenshotHistoryStore.add(data: cachedScreenshot) {
                screenshotHistory = [migratedItem]
            } else if !fits {
                JarvisLog.notice(
                    category: .storage,
                    event: "screenshot.history.migrationSkipped",
                    result: "cacheFull",
                    fields: ["bytes": String(incoming)]
                )
            }
        }

        migrateClipboardTextCache()
        configureClipboardRecording()
        configureClipboardCacheAutoCleanup()
        refreshClipboardCacheUsage()
        if latestScreenshotData != nil {
            statusMessage = "已恢复上次缓存的截图"
        }
        backfillImageText()
        JarvisPerformance.emit("startup services ready")
        JarvisLog.info(
            category: .lifecycle,
            event: "startup.servicesReady",
            fields: [
                "clipboardService": "running",
                "clipboardRecordCount": String(clipboardItems.count),
                "screenshotRecordCount": String(screenshotHistory.count)
            ]
        )
    }
}
