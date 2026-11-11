import Foundation

extension AppModel {
    /// 启动时把已经落盘的识别结果放进内存，再把还没有结果的截图和剪贴板图片排进后台队列。
    /// 视频和复制的文件不进这个队列。
    func backfillImageText() {
        imageTextByHash = imageTextIndex.recognizedText
        for item in screenshotHistory {
            enqueueImageText(
                hash: item.contentHash,
                fileURL: screenshotHistoryStore.fileURL(for: item),
                priority: false,
                screenshotID: item.id
            )
        }
        for item in clipboardItems where item.kind == .image {
            guard let hash = item.fingerprintValue, let path = item.imagePath else { continue }
            enqueueImageText(hash: hash, fileURL: URL(fileURLWithPath: path), priority: false)
        }
    }

    func enqueueReceivedClipboardImage(_ item: ClipboardItem) {
        // 视频和复制的文件只按文件名搜索，不进 OCR。
        guard item.kind == .image, let hash = item.fingerprintValue, let path = item.imagePath else { return }
        enqueueImageText(hash: hash, fileURL: URL(fileURLWithPath: path), priority: true)
    }

    func enqueueImageText(
        hash: String?,
        fileURL: URL,
        priority: Bool,
        screenshotID: UUID? = nil
    ) {
        imageTextIndex.enqueue(hash: hash, fileURL: fileURL, priority: priority) { [weak self] resolved in
            guard let screenshotID else { return }
            self?.bindScreenshotContentHash(id: screenshotID, hash: resolved)
        }
    }

    func bindScreenshotContentHash(id: UUID, hash: String) {
        guard let index = screenshotHistory.firstIndex(where: { $0.id == id }) else { return }
        guard screenshotHistory[index].contentHash != hash else { return }
        screenshotHistory[index].contentHash = hash
        screenshotHistoryStore.setContentHash(id: id, hash: hash)
    }

    func noteImageTextStored(hash: String, text: String) {
        var updated = imageTextByHash
        updated[hash] = text
        imageTextByHash = updated
        let keeping = referencedImageHashes()
        guard keeping.contains(hash) else {
            pruneUnreferencedImageText()
            return
        }
    }

    func pruneUnreferencedImageText() {
        imageTextIndex.prune(keeping: referencedImageHashes(), filePaths: referencedImageFilePaths())
        imageTextByHash = imageTextIndex.recognizedText
    }

    func referencedImageHashes() -> Set<String> {
        var hashes = Set(screenshotHistory.compactMap(\.contentHash))
        for item in clipboardItems where item.kind == .image {
            if let hash = item.fingerprintValue {
                hashes.insert(hash)
            }
        }
        return hashes
    }

    func referencedImageFilePaths() -> Set<String> {
        var paths = Set(screenshotHistory.map { screenshotHistoryStore.fileURL(for: $0).path })
        for item in clipboardItems where item.kind == .image {
            if let path = item.imagePath {
                paths.insert(path)
            }
        }
        return paths
    }
}
