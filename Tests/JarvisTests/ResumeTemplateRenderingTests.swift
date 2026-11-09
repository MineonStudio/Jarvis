import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

@MainActor
final class ResumeTemplateRenderingTests: XCTestCase {
    func testAllFifteenTemplatesRenderDistinctPagesAndGalleryThumbnails() throws {
        var renders = Set<Data>()
        for template in ResumeTemplate.allCases {
            let document = ResumeTemplateThumbnail.sampleDocument(template: template)
            let pages = ResumePageLayout.pages(for: document)
            XCTAssertEqual(pages.count, 1, "\(template.title) 的完整展示内容应排入一页")
            let firstPage = try XCTUnwrap(pages.first)
            XCTAssertLessThanOrEqual(ResumePageLayout.contentHeight(for: document, content: firstPage), 876, template.title)
            let renderer = ImageRenderer(content: ResumePageView(
                document: document,
                selectedProjectID: nil,
                selectedBulletIndex: nil,
                showsEmptyState: false,
                onSelectProject: { _ in },
                onSelectBullet: { _, _ in },
                pageContent: firstPage
            ))
            renderer.scale = 1
            let bitmap = try NSBitmapImageRep(cgImage: XCTUnwrap(renderer.cgImage))
            XCTAssertEqual(bitmap.pixelsWide, 620)
            XCTAssertEqual(bitmap.pixelsHigh, 876)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            renders.insert(png)
            let thumbnail = ImageRenderer(content: ResumeTemplateThumbnail(template: template))
            thumbnail.scale = 1
            let image = try XCTUnwrap(thumbnail.cgImage)
            XCTAssertEqual(image.width, 168)
            XCTAssertEqual(image.height, 237)
            if let directory = ProcessInfo.processInfo.environment["JARVIS_RESUME_PREVIEW_DIR"] {
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(template.rawValue).png"))
            }
        }
        XCTAssertEqual(renders.count, 15)
    }
}
