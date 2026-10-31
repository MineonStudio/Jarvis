import AppKit
import AVFoundation
import ScreenCaptureKit

extension ScreenRecordingCoordinator {
    func checkCapacity(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values.volumeAvailableCapacityForImportantUsage, capacity < 512 * 1024 * 1024 {
            throw ScreenRecordingError.message("可用磁盘空间不足 512 MB，请释放空间或选择其他保存位置。")
        }
    }

    func beginTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            var ticks = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, current != nil else { return }
                if phase == .recording {
                    let activeDuration = segment?.duration ?? 0
                    elapsed = completedDuration + (activeDuration.isFinite ? activeDuration : 0)
                }
                updateMenuBar()
                ticks += 1
                guard ticks % 3 == 0, phase == .recording || phase == .paused else { continue }
                do {
                    try checkCapacity(at: repository.root)
                    try checkCapacity(at: outputDirectory)
                    guard try await validateCurrentTarget() else { continue }
                    if phase == .recording, (segment?.duration ?? 0) >= 60 {
                        // Periodically seal a recoverable file. No raw frame ring buffer.
                        phase = .changing
                        try await closeSegment()
                        try await startSegment()
                        phase = .recording
                    }
                } catch {
                    if phase == .changing {
                        phase = .paused
                    }
                    await stop(reason: error.localizedDescription)
                    return
                }
            }
        }
    }

    func validateCurrentTarget() async throws -> Bool {
        guard let current else { return false }
        let expectedPhase = phase
        let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        // Do not let a slow monitor result mutate a session the user has already paused/stopped.
        guard self.current?.id == current.id, phase == expectedPhase else { return false }
        guard let content else { throw ScreenRecordingError.message("无法验证录制目标，请检查屏幕录制权限。") }
        if current.mode == .window {
            guard let target = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenRecordingError.message("目标窗口已关闭。")
            }
            if target.isOnScreen, phase == .paused {
                await togglePause()
                message = nil
                return false
            }
            if !target.isOnScreen {
                if phase == .recording {
                    await togglePause(); message = "目标窗口不可见，录制已暂停。恢复窗口后自动继续。"
                    return false
                } else if phase == .changing {
                    throw ScreenRecordingError.message("请先恢复目标窗口。")
                }
            }
        } else if !content.displays.contains(where: { $0.displayID == displayID }) {
            throw ScreenRecordingError.message("录制显示器已断开。")
        }
        return true
    }

    func updateMenuBar() {
        JarvisMenuBarController.shared.updateScreenRecordingState(active: isActive, paused: phase == .paused, elapsed: elapsed)
    }
}
