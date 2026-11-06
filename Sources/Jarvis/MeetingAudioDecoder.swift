import AVFoundation
import Foundation

/// A growing, ordinary 16 kHz mono WAV. The header is refreshed on every append,
/// so a crash leaves a readable file and the Rust reader can consume it live.
final class MeetingWAVWriter {
    let url: URL
    private let file: FileHandle
    private(set) var frames: UInt64 = 0
    init(url: URL) throws {
        self.url = url
        FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0, count: 44))
        file = try FileHandle(forWritingTo: url)
        try updateHeader()
    }

    func append(_ data: Data) throws {
        guard !data.isEmpty else { return }
        try file.seekToEnd()
        try file.write(contentsOf: data)
        frames += UInt64(data.count / 2)
        try updateHeader()
    }

    func silence(frames count: UInt64) throws {
        var remaining = count
        while remaining > 0 {
            let n = min(remaining, 16000)
            try append(Data(repeating: 0, count: Int(n * 2)))
            remaining -= n
        }
    }

    private func updateHeader() throws {
        let count = UInt32(clamping: frames * 2)
        var header = Data()
        func u16(_ v: UInt16) {
            var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) }
        }
        func u32(_ v: UInt32) {
            var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: "RIFF".utf8); u32(36 &+ count)
        header.append(contentsOf: "WAVEfmt ".utf8); u32(16); u16(1); u16(1)
        u32(16000); u32(32000); u16(2); u16(16)
        header.append(contentsOf: "data".utf8); u32(count)
        try file.seek(toOffset: 0); try file.write(contentsOf: header)
    }

    deinit { try? file.synchronize(); try? file.close() }
}

enum MeetingAudioDecoder {
    static func decode(_ source: URL, to output: URL, delay: TimeInterval = 0) async throws {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: source)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard !tracks.isEmpty else { throw MeetingEngineError.failed("文件中没有音轨") }
            let reader = try AVAssetReader(asset: asset)
            let audio = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ])
            reader.add(audio)
            let writer = try MeetingWAVWriter(url: output)
            if delay > 0 {
                try writer.silence(frames: UInt64(delay * 16000))
            }
            guard reader.startReading() else { throw reader.error ?? MeetingEngineError.failed("音频解码失败") }
            do {
                while let sample = audio.copyNextSampleBuffer() {
                    try Task.checkCancellation()
                    guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                    var data = Data(count: CMBlockBufferGetDataLength(block))
                    let status = data.withUnsafeMutableBytes {
                        guard let address = $0.baseAddress, !$0.isEmpty else { return OSStatus(noErr) }
                        return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: $0.count, destination: address)
                    }
                    guard status == noErr else { throw MeetingEngineError.failed("音频数据读取失败") }
                    try writer.append(data)
                }
                guard reader.status == .completed else { throw reader.error ?? MeetingEngineError.failed("音频解码中断") }
            } catch { reader.cancelReading(); throw error }
        }.value
    }
}
