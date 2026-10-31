import AppKit
import AVFoundation
import ScreenCaptureKit

extension ScreenRecordingCoordinator {
    func recover(_ record: ScreenRecordingRecord) async {
        guard !isActive else { return }
        phase = .saving
        var updated = record
        do {
            guard !updated.exists else {
                // Never mistake an unrelated destination file for a successful export and erase the sources.
                throw ScreenRecordingError.message("目标路径已有文件，请先查看该文件，或选择「另存恢复」。")
            }
            try await finalize(&updated, allowIncompleteSegments: true)
            message = "已恢复成功封装的视频片段。"
        } catch { message = "恢复失败：\(error.localizedDescription) 原始片段仍然保留。" }
        phase = .idle
    }

    func relocateAndRecover(_ record: ScreenRecordingRecord) async {
        guard !isActive else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = record.fileURL.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = record; updated.filePath = url.path
        do {
            guard !updated.exists else { throw ScreenRecordingError.message("目标文件已存在，请选择新的文件名。") }
            try repository.save(updated)
            if let index = records.firstIndex(where: { $0.id == updated.id }) {
                records[index] = updated
            }
            await recover(updated)
        } catch {
            message = error.localizedDescription
        }
    }

    func finalize(_ record: inout ScreenRecordingRecord, allowIncompleteSegments: Bool = false) async throws {
        let parts = repository.segments(record.id)
        let temporary = record.fileURL.deletingLastPathComponent().appendingPathComponent(".\(record.id.uuidString)-export.mp4")
        // A failed previous export is never a source segment and is safe to replace on retry.
        if FileManager.default.fileExists(atPath: temporary.path) {
            try FileManager.default.removeItem(at: temporary)
        }
        let duration = try await ScreenRecordingAssembler.assemble(
            segments: parts,
            destination: temporary,
            hevc: record.settings.useHEVC,
            allowIncompleteSegments: allowIncompleteSegments
        )
        try FileManager.default.moveItem(at: temporary, to: record.fileURL)
        record.duration = duration
        try markCompleted(&record)
    }

    func markCompleted(_ record: inout ScreenRecordingRecord) throws {
        record.completed = true
        record.byteCount = try Int64((record.fileURL.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        try repository.save(record)
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        }
        // Only remove source segments after both final output and its metadata are durable.
        try? repository.cleanSegments(record.id)
        let snapshot = record
        Task { await repository.makeThumbnail(for: snapshot) }
    }

    func rename(_ record: ScreenRecordingRecord, title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var updated = record; updated.title = name
        do {
            try repository.save(updated)
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                records[index] = updated
            }
        } catch { message = error.localizedDescription }
    }

    func locate(_ record: ScreenRecordingRecord) async {
        guard !isActive else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw ScreenRecordingError.message("所选文件没有视频轨道。")
            }
            var updated = record
            let size = try await track.load(.naturalSize)
            updated.width = Int(size.width); updated.height = Int(size.height)
            updated.duration = try await asset.load(.duration).seconds
            updated.filePath = url.path
            try markCompleted(&updated)
        } catch { message = "重新定位失败：\(error.localizedDescription)" }
    }

    func delete(_ record: ScreenRecordingRecord) {
        guard current?.id != record.id else { return }
        do {
            try repository.remove(record)
            records.removeAll { $0.id == record.id }
        } catch {
            message = "删除失败：\(error.localizedDescription)"
        }
    }
}
