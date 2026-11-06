import Foundation

enum MeetingModelStorage {
    static let requiredFiles = ["paraformer/model.int8.onnx", "paraformer/tokens.txt", "silero_vad.onnx", "punct/model.int8.onnx", "campplus_zh.onnx", "verified.json"]
    static func availability(fileManager _: FileManager = .default) -> MeetingModelAvailability {
        let ready = requiredFiles.allSatisfy { name in
            let url = MeetingEnginePaths.models.appendingPathComponent(name)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 0
        }
        return MeetingModelAvailability(paraformerReady: ready)
    }

    static func markVerified() throws {
        let directory = MeetingEnginePaths.models
        JarvisProtectedStorage.prepareDirectory(directory)
        try Data("{\"pipeline\":1,\"model\":\"Paraformer-large\"}".utf8)
            .write(to: directory.appendingPathComponent("verified.json"), options: .atomic)
    }

    static func removeModel(for _: MeetingModelPreparationStage, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: MeetingEnginePaths.models.path) {
            try fileManager.removeItem(at: MeetingEnginePaths.models)
        }
    }
}
