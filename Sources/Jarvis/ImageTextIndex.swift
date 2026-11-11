import Foundation

/// 按图片哈希保存 OCR 文本，并串行识别还没有结果的文件。
///
/// 新图片排在历史补识别前面。同一个哈希只识别一次：空字符串表示图里没有文字，
/// 会落盘且不再重试；识别失败不落盘，下次启动再试。日志只记字数，不记文字本身。
@MainActor
final class ImageTextIndex {
    typealias Recognizer = @Sendable (Data) async -> String?
    typealias HashCallback = @MainActor (String) -> Void

    private struct Job {
        var fileURL: URL
        var hash: String?
        var callbacks: [HashCallback]
    }

    private struct Loaded: Sendable {
        var data: Data
        var hash: String
    }

    private let file: JarvisJSONFile<[String: String]>
    private let recognize: Recognizer
    private var texts: [String: String]
    private var pending: [Job] = []
    private var active: Job?
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// 一段文字刚写入索引时调用。失败和已经有结果的哈希不会再调用。
    var onStored: (@MainActor (_ hash: String, _ text: String) -> Void)?

    var recognizedText: [String: String] {
        texts
    }

    init(
        directoryURL: URL = JarvisAppDirectory.url("ImageText"),
        recognize: @escaping Recognizer = { data in
            await ImageTextRecognition.recognize(data)
        }
    ) {
        file = JarvisJSONFile(
            directoryURL: directoryURL,
            fileName: "recognized-text.json",
            logDomain: "imageText.index"
        )
        self.recognize = recognize
        texts = file.readOrDefault([:])
    }

    func enqueue(
        hash: String?,
        fileURL: URL,
        priority: Bool,
        onHash: HashCallback? = nil
    ) {
        if let hash, texts[hash] != nil {
            onHash?(hash)
            return
        }
        if let index = pending.firstIndex(where: { matches($0, hash: hash, fileURL: fileURL) }) {
            if let onHash {
                pending[index].callbacks.append(onHash)
            }
            return
        }
        if var active, matches(active, hash: hash, fileURL: fileURL) {
            if let onHash {
                active.callbacks.append(onHash)
            }
            self.active = active
            return
        }

        var job = Job(fileURL: fileURL, hash: hash, callbacks: [])
        if let onHash {
            job.callbacks.append(onHash)
        }
        if priority {
            pending.insert(job, at: 0)
        } else {
            pending.append(job)
        }
        pump()
    }

    func waitUntilIdle() async {
        if pending.isEmpty, active == nil {
            return
        }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    /// 丢掉已经没有截图或剪贴板图片引用的文本。还不知道哈希的排队任务按文件路径判断。
    func prune(keeping hashes: Set<String>, filePaths: Set<String>) {
        pending.removeAll { job in
            if let hash = job.hash {
                return !hashes.contains(hash)
            }
            return !filePaths.contains(job.fileURL.path)
        }
        let stale = texts.keys.filter { !hashes.contains($0) }
        guard !stale.isEmpty else { return }
        for key in stale {
            texts.removeValue(forKey: key)
        }
        file.write(texts)
    }

    private func matches(_ job: Job, hash: String?, fileURL: URL) -> Bool {
        if job.fileURL.path == fileURL.path {
            return true
        }
        if let hash, job.hash == hash {
            return true
        }
        return false
    }

    private func pump() {
        guard active == nil else { return }
        guard !pending.isEmpty else {
            let waiters = idleWaiters
            idleWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            return
        }
        let job = pending.removeFirst()
        active = job
        let fileURL = job.fileURL
        Task { [weak self] in
            let loaded = await Self.load(fileURL)
            await self?.continueJob(loaded)
        }
    }

    private static func load(_ fileURL: URL) async -> Loaded? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
            return Loaded(data: data, hash: ImageContentHash.sha256(data))
        }.value
    }

    private func continueJob(_ loaded: Loaded?) async {
        guard let loaded else {
            JarvisLog.notice(
                category: .storage,
                event: "imageText.read.failed",
                result: "retryLater",
                fields: ["path": JarvisLogRedactor.path(active?.fileURL.path ?? "")]
            )
            finish(stored: nil)
            return
        }

        absorbPending(hash: loaded.hash)
        if texts[loaded.hash] != nil {
            finish(stored: nil)
            return
        }

        let text = await recognize(loaded.data)
        guard let text else {
            JarvisLog.notice(
                category: .storage,
                event: "imageText.recognize.failed",
                result: "retryLater"
            )
            finish(stored: nil)
            return
        }

        texts[loaded.hash] = text
        file.write(texts)
        JarvisLog.info(
            category: .storage,
            event: "imageText.recognized",
            result: text.isEmpty ? "empty" : "success",
            fields: ["characters": String(text.count)]
        )
        finish(stored: text)
    }

    private func absorbPending(hash: String) {
        guard var active else { return }
        var callbacks = active.callbacks
        pending.removeAll { job in
            guard job.hash == hash else { return false }
            callbacks.append(contentsOf: job.callbacks)
            return true
        }
        active.hash = hash
        active.callbacks = callbacks
        self.active = active
    }

    private func finish(stored text: String?) {
        let hash = active?.hash
        let callbacks = active?.callbacks ?? []
        active = nil
        if let hash {
            for callback in callbacks {
                callback(hash)
            }
        }
        if let hash, let text {
            onStored?(hash, text)
        }
        pump()
    }
}
