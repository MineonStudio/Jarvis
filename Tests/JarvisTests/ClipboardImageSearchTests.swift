import Foundation
@testable import Jarvis
import XCTest

final class ClipboardImageSearchTests: XCTestCase {
    func testImageTextSearchKeepsTextFileNameAndVideoFileNameMatches() {
        let text = ClipboardItem(kind: .text, text: "Swift quality audit")
        let image = imageItem(path: "/tmp/a.png", fingerprint: "hash-image")
        let blankImage = imageItem(path: "/tmp/blank.png", fingerprint: "hash-blank")
        let file = ClipboardItem(
            kind: .file, filePath: "/tmp/notes.pdf", fileName: "notes.pdf", fingerprintValue: "hash-image"
        )
        let namedFile = ClipboardItem(kind: .file, filePath: "/tmp/大模型.png", fileName: "大模型.png")
        let video = ClipboardItem(
            kind: .video, filePath: "/tmp/demo.mov", fileName: "demo.mov", fingerprintValue: "hash-image"
        )
        let items = [text, image, blankImage, file, namedFile, video]
        let imageText = ["hash-image": "画面里有大模型", "hash-blank": ""]

        XCTAssertEqual(ids(items, query: "大模型", imageText: imageText), [image.id, namedFile.id])
        XCTAssertEqual(ids(items, query: "quality", imageText: imageText), [text.id])
        XCTAssertEqual(ids(items, query: "demo", imageText: imageText), [video.id])
        XCTAssertEqual(ids(items, query: "notes", imageText: imageText), [file.id])
        XCTAssertEqual(ids(items, query: "", imageText: imageText, filter: .image), [image.id, blankImage.id])
        XCTAssertTrue(ids([blankImage], query: "大模型", imageText: imageText).isEmpty)
        XCTAssertEqual(ids([image], query: "图片", imageText: imageText), [image.id])
    }

    private func imageItem(path: String, fingerprint: String) -> ClipboardItem {
        ClipboardItem(kind: .image, imagePath: path, fingerprintValue: fingerprint)
    }

    private func ids(
        _ items: [ClipboardItem],
        query: String,
        imageText: [String: String],
        filter: ClipboardViewFilter = .all
    ) -> [UUID] {
        ClipboardFilterLogic.filteredItems(
            from: items,
            searchText: query,
            filter: filter,
            imageTextByHash: imageText
        ).map(\.id)
    }
}
