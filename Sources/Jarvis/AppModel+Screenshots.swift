import AppKit
import Foundation
import UniformTypeIdentifiers

private struct ScreenshotSaveRequest {
    let data: Data
    let historyID: UUID?
    let finalizesHistory: Bool
    /// 保存之后编辑会话是否结束。工具栏上的「保存」不结束（还能接着改），
    /// 所以它不能把 `editingHistoryID` 清掉。
    let endsSession: Bool
    let successMessage: String
}

extension AppModel {
    // MARK: - Screenshot workflow

    /// Starts a screenshot from a global/menu-bar action without changing the
    /// section currently shown in the main window. Callers that originate
    /// inside the main window can select the screenshot tab themselves before
    /// invoking this method.
    func captureScreenshot() {
        refreshPermissionStatus()
        guard screenCapturePermissionGranted else {
            promptForTaskPermission(.screenCapture)
            return
        }
        guard screenshotController.sessionPhase == .idle else {
            showToast(JarvisFeedbackCopy.finishScreenshotFirst)
            return
        }

        editingHistoryID = nil
        // Freeze every display on this run-loop turn, then show the overlay
        // on those pixels. The overlay is created after the snapshot, so it
        // is never included in the screenshot.
        isCapturing = true
        statusMessage = "请在屏幕上框选区域"

        screenshotController.beginCapture { [weak self] result in
            guard let self else { return }
            isCapturing = false

            switch result {
            case let .success(session):
                statusMessage = "截图已保留在冻结画面上，可以直接编辑"
                screenshotController.showResult(
                    session
                ) { [weak self] action in
                    self?.handleScreenshotAction(action)
                }
            case let .failure(error):
                statusMessage = error.localizedDescription
                switch error {
                case ScreenshotError.cancelled, ScreenshotError.permissionDenied:
                    // Keep normal cancellation and native permission failures
                    // from pulling the Jarvis host window in front of the user.
                    break
                case ScreenshotError.invalidSelection:
                    showToast(JarvisFeedbackCopy.recapture)
                case ScreenshotError.noDisplays:
                    showToast(JarvisFeedbackCopy.noDisplays)
                default:
                    showToast(JarvisFeedbackCopy.captureFailed)
                }
            }
        }
    }

    private func handleScreenshotAction(_ action: ScreenshotAction) {
        switch action {
        case .saveRequested, .pinRequested, .confirmRequested:
            // The capture controller consumes these requests and renders the
            // final image before sending the completed action back here.
            break
        case let .save(data):
            let presentingWindow = screenshotController.saveWindow()
            saveScreenshot(
                data,
                historyID: editingHistoryID,
                presentingWindow: presentingWindow
            )
        case let .confirm(data):
            finalizeScreenshot(data, historyID: editingHistoryID)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
            showToast(JarvisFeedbackCopy.copied)
        case let .pin(data):
            finalizeScreenshot(data, historyID: editingHistoryID)
            showToast(JarvisFeedbackCopy.saved)
        case .copiedToClipboard:
            showToast(JarvisFeedbackCopy.copied)
        case .cancel:
            editingHistoryID = nil
            statusMessage = "已取消截图编辑，未执行任何操作"
        default:
            handleEditorStatusAction(action)
        }
    }

    private func handleEditorStatusAction(_ action: ScreenshotAction) {
        switch action {
        case let .tool(tool):
            switch tool {
            case .eyedropper:
                statusMessage = "已选择取色，移动鼠标预览色值，点击或按 C 复制"
            case .comment:
                statusMessage = "已选择批注，点击截图添加说明，拖动圆点或说明可调整位置"
            default:
                statusMessage = "已选择\(tool.title)，在截图上拖动即可使用"
            }
        case .undo:
            statusMessage = "已撤销上一步标注"
        case .redo:
            statusMessage = "已恢复上一步标注"
        case .delete:
            statusMessage = "已删除选中的标注"
        case .duplicate:
            statusMessage = "已复制选中的标注"
        default:
            break
        }
    }

    private func saveScreenshot(
        _ data: Data,
        historyID: UUID?,
        presentingWindow: NSWindow? = nil
    ) {
        presentSavePanel(
            for: data,
            historyID: historyID,
            finalizesHistory: true,
            endsSession: false,
            successMessage: JarvisFeedbackCopy.saved,
            presentingWindow: presentingWindow
        )
    }

    func copyScreenshotHistory(_ item: ScreenshotHistoryItem) {
        guard let data = screenshotHistoryStore.data(for: item) else {
            showToast(JarvisFeedbackCopy.fileMissing)
            reloadScreenshotHistory()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        showToast(JarvisFeedbackCopy.copied)
    }

    private func presentSavePanel(
        for data: Data,
        historyID: UUID?,
        finalizesHistory: Bool,
        endsSession: Bool,
        successMessage: String,
        presentingWindow: NSWindow? = nil
    ) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = ScreenshotFileName.timestamped()
        savePanel.canCreateDirectories = true
        if let presentingWindow {
            // The history preview is a high-level panel. Present the native
            // save dialog as its sheet so it stays above the screenshot and
            // the dimming panel instead of falling behind them.
            savePanel.level = presentingWindow.level
            savePanel.beginSheetModal(for: presentingWindow) { [weak self] response in
                self?.finishSavePanel(
                    savePanel,
                    response: response,
                    request: ScreenshotSaveRequest(
                        data: data,
                        historyID: historyID,
                        finalizesHistory: finalizesHistory,
                        endsSession: endsSession,
                        successMessage: successMessage
                    )
                )
            }
        } else {
            savePanel.begin { [weak self] response in
                self?.finishSavePanel(
                    savePanel,
                    response: response,
                    request: ScreenshotSaveRequest(
                        data: data,
                        historyID: historyID,
                        finalizesHistory: finalizesHistory,
                        endsSession: endsSession,
                        successMessage: successMessage
                    )
                )
            }
        }
    }

    private func finishSavePanel(
        _ savePanel: NSSavePanel,
        response: NSApplication.ModalResponse,
        request: ScreenshotSaveRequest
    ) {
        guard response == .OK, let url = savePanel.url else {
            return
        }
        do {
            try request.data.write(to: url, options: .atomic)
            // 真存下盘了才叫「存过」。保存面板点取消会直接 return 到这里之前，
            // 贴图那场编辑不该因为弹过一次面板就认定自己存过东西。
            screenshotController.notePinnedEditSaved(request.data)
            if request.finalizesHistory {
                finalizeScreenshot(
                    request.data,
                    historyID: request.historyID,
                    endsSession: request.endsSession
                )
            }
            showToast(request.successMessage)
        } catch {
            showToast(JarvisFeedbackCopy.saveFailed)
        }
    }

    @discardableResult
    private func setLatestScreenshot(_ data: Data) -> Bool {
        latestScreenshotData = data
        guard screenshotCacheStore.save(data) else {
            showToast(JarvisFeedbackCopy.cacheSaveFailed)
            return false
        }
        return true
    }

    /// 落盘之后 `editingHistoryID` 该变成什么。
    ///
    /// - 会话结束（「完成」「贴图」）→ 清空。
    /// - 会话继续（「保存」）→ 记住这次落在哪条（新截图第一次保存时本来是空的），
    ///   否则下一次保存/完成会再新增一条一模一样的记录。
    nonisolated static func editingHistoryIDAfterFinalize(
        endsSession: Bool,
        resolvedID: UUID?,
        current: UUID?
    ) -> UUID? {
        endsSession ? nil : (resolvedID ?? current)
    }

    /// - Parameter endsSession: 这次落盘之后编辑会话是否就结束了。点「完成」「贴图」
    ///   会结束；点「保存」不会——用户可以接着编辑。会话没结束时要把这次落在历史里
    ///   的条目 id 记回 `editingHistoryID`，否则下一次保存/完成会再新增一条一模一样
    ///   的记录（新截图第一保存时 id 本来是空的，正好踩中）。
    private func finalizeScreenshot(_ data: Data, historyID: UUID?, endsSession: Bool = true) {
        let historyItem = historyID.flatMap { id in
            screenshotHistory.first(where: { $0.id == id })
        }
        let cacheStore = screenshotCacheStore
        let historyStore = screenshotHistoryStore
        let incomingBytes = Int64(data.count)
        let replacingBytes = historyItem.flatMap { item in
            historyStore.fileSize(ofStored: item)
        } ?? 0
        let clipboardUsage = clipboardCacheStore.usage()
        let screenshotUsage = screenshotHistoryStore.storedUsage()
        guard SharedCacheAdmission.screenshotSaveFits(
            clipboardBytes: clipboardUsage.usedBytes,
            historyBytes: screenshotUsage.bytes,
            replacingHistoryBytes: replacingBytes,
            imageBytes: incomingBytes,
            capacityBytes: clipboardUsage.capacityBytes
        ) else {
            notifySharedCacheFull()
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cacheSaved = cacheStore.save(data)
            // 这次落盘实际对应的条目 id：更新时是原来那条，新建时是刚加进去那条。
            let resolvedID: UUID? = if let historyItem {
                historyStore.update(historyItem, data: data) != nil ? historyItem.id : nil
            } else {
                historyStore.add(data: data)?.id
            }
            let history = historyStore.load()
            DispatchQueue.main.async {
                guard let self else { return }
                self.latestScreenshotData = cacheSaved ? data : self.latestScreenshotData
                self.screenshotHistory = history
                self.editingHistoryID = Self.editingHistoryIDAfterFinalize(
                    endsSession: endsSession,
                    resolvedID: resolvedID,
                    current: self.editingHistoryID
                )
                if !cacheSaved || resolvedID == nil {
                    self.showToast(JarvisFeedbackCopy.historySaveFailed)
                }
                self.refreshClipboardCacheUsage()
            }
        }
    }

    func screenshotHistoryData(for item: ScreenshotHistoryItem) -> Data? {
        screenshotHistoryStore.data(for: item)
    }

    func screenshotHistoryFileURL(for item: ScreenshotHistoryItem) -> URL {
        screenshotHistoryStore.fileURL(for: item)
    }

    func showScreenshotHistoryPreview(_ item: ScreenshotHistoryItem) {
        guard screenshotController.sessionPhase == .idle else {
            showToast(JarvisFeedbackCopy.finishScreenshotFirst)
            return
        }
        guard let data = screenshotHistoryStore.data(for: item) else {
            showToast(JarvisFeedbackCopy.fileMissing)
            reloadScreenshotHistory()
            return
        }
        guard screenshotHistoryPreviewController.show(data: data) else {
            showToast(JarvisFeedbackCopy.cannotPreview)
            return
        }
    }

    func editScreenshotHistory(_ item: ScreenshotHistoryItem) {
        guard screenshotController.sessionPhase == .idle else {
            showToast(JarvisFeedbackCopy.finishScreenshotFirst)
            return
        }
        guard let data = screenshotHistoryStore.data(for: item) else {
            showToast(JarvisFeedbackCopy.fileMissing)
            reloadScreenshotHistory()
            return
        }

        editingHistoryID = item.id
        selectedSection = .skill(.screenshot)
        statusMessage = "正在编辑历史截图"
        screenshotController.showHistoryResult(
            data: data
        ) { [weak self] action in
            self?.handleScreenshotAction(action)
        }
    }

    func deleteScreenshotHistory(_ item: ScreenshotHistoryItem) {
        if editingHistoryID == item.id {
            // 走「取消」那条路，而不是直接把编辑面拆掉：会话以为自己是被人关掉的，
            // 跟着它走的东西（比如贴图）就收不到交代。
            screenshotController.cancelActiveSession()
            editingHistoryID = nil
        }
        let deletedData = screenshotHistoryStore.data(for: item)
        guard screenshotHistoryStore.delete(item) else {
            showToast(JarvisFeedbackCopy.deleteFailed)
            reloadScreenshotHistory()
            return
        }
        reloadScreenshotHistory()

        if let deletedData, latestScreenshotData == deletedData {
            let replacement = screenshotHistory.first.flatMap { item in
                screenshotHistoryStore.data(for: item)
            }
            switch replacement.map(replaceLatestScreenshotIfItFits) {
            case .saved:
                break
            case .failed:
                refreshClipboardCacheUsage()
                return
            case .refused, nil:
                guard screenshotCacheStore.clear() else {
                    showToast(JarvisFeedbackCopy.cacheClearFailed)
                    refreshClipboardCacheUsage()
                    return
                }
                latestScreenshotData = nil
            }
        }
        refreshClipboardCacheUsage()
        showToast(JarvisFeedbackCopy.deleted)
    }

    private enum LatestScreenshotReplacement {
        case saved
        case refused
        case failed
    }

    /// 删掉当前工作截图后，尝试用下一条历史图接上。接上去会超上限时拒绝，调用方改清空。
    private func replaceLatestScreenshotIfItFits(_ data: Data) -> LatestScreenshotReplacement {
        let clipboard = clipboardCacheStore.usage()
        let history = screenshotHistoryStore.storedUsage()
        guard SharedCacheAdmission.allows(
            usedBytes: clipboard.usedBytes + history.bytes,
            capacityBytes: clipboard.capacityBytes,
            incomingBytes: Int64(data.count)
        ) else {
            return .refused
        }
        return setLatestScreenshot(data) ? .saved : .failed
    }

    private func reloadScreenshotHistory() {
        screenshotHistory = screenshotHistoryStore.load()
    }
}
