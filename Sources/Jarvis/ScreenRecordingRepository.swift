import AppKit
import AVFoundation
import Foundation

/// Each session has an independent atomic manifest. A failed save cannot erase other sessions.
struct ScreenRecordingRepository: Sendable {
    let root: URL

    init(root: URL = JarvisAppDirectory.url("ScreenRecordings")) {
        self.root = root
        JarvisProtectedStorage.prepareDirectory(root)
    }

    var movieDirectory: URL {
        root.appendingPathComponent("Videos", isDirectory: true)
    }

    func directory(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func thumbnail(_ id: UUID) -> URL {
        directory(id).appendingPathComponent("thumbnail.jpg")
    }

    func segment(_ id: UUID, index: Int) -> URL {
        directory(id).appendingPathComponent(String(format: "segment-%06d.mp4", index))
    }

    func segments(_ id: UUID) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory(id), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("segment-") && $0.pathExtension == "mp4" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func load() -> [ScreenRecordingRecord] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let id = UUID(uuidString: folder.lastPathComponent) else { return nil }
            return try? manifest(id).readForWriting(default: nil)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ record: ScreenRecordingRecord) throws {
        try manifest(record.id).writeOrThrow(record)
    }

    private func manifest(_ id: UUID) -> JarvisJSONFile<ScreenRecordingRecord?> {
        JarvisJSONFile(directoryURL: directory(id), fileName: "session.json", logDomain: "screenRecording")
    }

    func remove(_ record: ScreenRecordingRecord) throws {
        if record.completed, record.exists {
            // Finder Trash is recoverable and respects external/custom storage volumes.
            try FileManager.default.trashItem(at: record.fileURL, resultingItemURL: nil)
        }
        try FileManager.default.removeItem(at: directory(record.id))
    }

    func cleanSegments(_ id: UUID) throws {
        for url in segments(id) {
            try FileManager.default.removeItem(at: url)
            for companion in [ScreenRecordingAudioTiming.audioURL(for: url), ScreenRecordingAudioTiming.metadataURL(for: url)]
                where FileManager.default.fileExists(atPath: companion.path)
            {
                try FileManager.default.removeItem(at: companion)
            }
        }
    }

    func makeThumbnail(for record: ScreenRecordingRecord) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: record.fileURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 400)
        guard let result = try? await generator.image(at: .zero) else { return }
        let bitmap = NSBitmapImageRep(cgImage: result.image)
        if let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? JarvisProtectedStorage.write(data, to: thumbnail(record.id))
        }
    }
}
