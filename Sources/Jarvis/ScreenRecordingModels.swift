import CoreGraphics
import Foundation

enum ScreenRecordingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case display, window, region
    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .display: "全屏"
        case .window: "窗口"
        case .region: "自定义区域"
        }
    }

    var recordingHint: String {
        switch self {
        case .display: "录制整个屏幕"
        case .window: "录制指定窗口"
        case .region: "录制自定义区域"
        }
    }

    var icon: String {
        switch self {
        case .display: "display"
        case .window: "macwindow"
        case .region: "rectangle.dashed"
        }
    }
}

enum ScreenRecordingQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case hd, fullHD, original
    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .hd: "720p 上限"
        case .fullHD: "1080p 上限"
        case .original: "原始分辨率"
        }
    }

    func outputSize(for source: CGSize) -> CGSize {
        let limit: CGSize = switch self {
        case .hd: CGSize(width: 1280, height: 720)
        case .fullHD: CGSize(width: 1920, height: 1080)
        case .original: source
        }
        let scale = min(1, limit.width / max(1, source.width), limit.height / max(1, source.height))
        // H.264 requires even dimensions. Never upscale a small selected region.
        return CGSize(
            width: max(2, floor(source.width * scale / 2) * 2),
            height: max(2, floor(source.height * scale / 2) * 2)
        )
    }
}

struct ScreenRecordingSettings: Codable, Equatable, Sendable {
    static let countdownOptions = [0, 3, 5]
    var systemAudio = true
    var microphone = false
    var microphoneID = ""
    var quality: ScreenRecordingQuality = .fullHD
    var frameRate = 30
    var showsMouseClicks: Bool? = false
    var showsCursor = true
    var countdown = 3
    var useHEVC = false
}

enum ScreenRecordingPhase: Equatable {
    case idle, countdown(Int), starting, recording, paused, changing, saving
    var isActive: Bool {
        self != .idle
    }

    var title: String {
        switch self {
        case .idle: "准备录制"
        case let .countdown(seconds): "\(seconds) 秒后开始"
        case .starting: "正在启动"
        case .recording: "录制中"
        case .paused: "已暂停"
        case .changing: "正在切换"
        case .saving: "正在保存"
        }
    }
}

struct ScreenRecordingRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var createdAt: Date
    var mode: ScreenRecordingMode
    var targetName: String
    var settings: ScreenRecordingSettings
    var width: Int
    var height: Int
    var duration: Double = 0
    var byteCount: Int64 = 0
    var filePath: String
    var completed = false
    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: filePath)
    }
}

enum ScreenRecordingGeometry {
    static func windowFrame(_ quartzRect: CGRect, desktopTop: CGFloat = WindowSelectionDetector.quartzDesktopTop) -> CGRect {
        CGRect(x: quartzRect.minX, y: desktopTop - quartzRect.maxY, width: quartzRect.width, height: quartzRect.height)
    }

    /// AppKit screen-local coordinates (bottom left) -> ScreenCaptureKit (top left points).
    static func sourceRect(from rect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: screenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func validRegion(_ rect: CGRect, in bounds: CGRect) -> CGRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite else { return nil }
        let clipped = rect.standardized.intersection(bounds)
        guard !clipped.isNull, clipped.width >= 24, clipped.height >= 24 else { return nil }
        return clipped
    }
}

enum ScreenRecordingError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case let .message(text): text
        }
    }
}
