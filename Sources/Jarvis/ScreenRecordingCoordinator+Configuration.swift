import AppKit
import AVFoundation
import ScreenCaptureKit

extension ScreenRecordingCoordinator {
    func authorizeMicrophone() async throws {
        guard settings.microphone else { return }
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else { throw ScreenRecordingError.message("麦克风未授权，请关闭麦克风录制或前往系统设置授权。") }
        if !settings.microphoneID.isEmpty, !microphones.contains(where: { $0.uniqueID == settings.microphoneID }) {
            throw ScreenRecordingError.message("所选麦克风已断开，请重新选择。")
        }
    }

    func makeConfiguration(filter: SCContentFilter, content: SCShareableContent) throws -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        var sourceSize = filter.contentRect.size
        if mode == .region {
            guard let display = content.displays.first(where: { $0.displayID == displayID }),
                  let region, let valid = ScreenRecordingGeometry.validRegion(region, in: CGRect(origin: .zero, size: display.frame.size)),
                  valid == region else { throw ScreenRecordingError.message("录制区域已失效，请重新框选。") }
            config.sourceRect = ScreenRecordingGeometry.sourceRect(from: region, screenHeight: display.frame.height)
            sourceSize = region.size
        }
        let pixelSize = CGSize(
            width: sourceSize.width * CGFloat(filter.pointPixelScale),
            height: sourceSize.height * CGFloat(filter.pointPixelScale)
        )
        let outputSize = settings.quality.outputSize(for: pixelSize)
        config.width = Int(outputSize.width); config.height = Int(outputSize.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(settings.frameRate == 60 ? 60 : 30))
        config.queueDepth = 4
        config.scalesToFit = true; config.preservesAspectRatio = true
        config.showsCursor = settings.showsCursor
        config.showMouseClicks = settings.showsMouseClicks == true
        config.capturesAudio = false // System output is captured independently of the video target.
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = settings.microphone
        if settings.microphone, !settings.microphoneID.isEmpty {
            config.microphoneCaptureDeviceID = settings.microphoneID
        }
        config.sampleRate = 48000; config.channelCount = 2
        config.captureDynamicRange = .SDR
        return config
    }

    func prepareSession(filter: SCContentFilter, configuration config: SCStreamConfiguration) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try checkCapacity(at: outputDirectory)
        try checkCapacity(at: repository.root)
        let id = UUID()
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let title = "屏幕录制_\(formatter.string(from: Date()))"
        let destination = outputDirectory.appendingPathComponent("\(title)_\(id.uuidString.prefix(6)).mp4")
        let record = ScreenRecordingRecord(
            id: id,
            title: title,
            createdAt: Date(),
            mode: mode,
            targetName: targetName,
            settings: settings,
            width: config.width,
            height: config.height,
            filePath: destination.path
        )
        try repository.save(record)
        current = record
        records.insert(record, at: 0)
        segmentIndex = 0; completedDuration = 0; elapsed = 0
        sessionFilter = filter; sessionConfiguration = config
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "jarvis.screen-recording.settings")
        }
    }
}
