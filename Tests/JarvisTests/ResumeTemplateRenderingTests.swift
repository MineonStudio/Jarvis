import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

@MainActor
final class ResumeTemplateRenderingTests: XCTestCase {
    func testPreviewBackingPixelsMatchCardSizeAndScreenDensity() throws {
        for size in [CGSize(width: 120.5, height: 170.25), ResumeTemplateThumbnail.size, CGSize(width: 225.25, height: 318)] {
            for scale: CGFloat in [1, 2] {
                let image = try XCTUnwrap(ResumeTemplatePreviewRenderer.image(template: .minimal, size: size, displayScale: scale))
                XCTAssertEqual(image.width, Int((size.width * scale).rounded(.up)))
                XCTAssertEqual(image.height, Int((size.height * scale).rounded(.up)))
            }
        }
    }

    func testPreviewCacheSeparatesDensityAndRejectsInvalidSizes() throws {
        let size = ResumeTemplateThumbnail.size
        let first = try XCTUnwrap(ResumeTemplatePreviewRenderer.image(template: .minimal, size: size, displayScale: 2))
        let cached = try XCTUnwrap(ResumeTemplatePreviewRenderer.image(template: .minimal, size: size, displayScale: 2))
        let standard = try XCTUnwrap(ResumeTemplatePreviewRenderer.image(template: .minimal, size: size, displayScale: 1))
        XCTAssertTrue(first === cached)
        XCTAssertFalse(first === standard)
        XCTAssertNil(ResumeTemplatePreviewRenderer.image(template: .minimal, size: .zero, displayScale: 2))
        XCTAssertNil(ResumeTemplatePreviewRenderer.image(template: .minimal, size: size, displayScale: 0))
        XCTAssertNil(ResumeTemplatePreviewRenderer.image(template: .minimal, size: size, displayScale: .nan))
    }

    func testAllFifteenTemplatesRenderDistinctPagesAndGalleryThumbnails() throws {
        var renders = Set<Data>()
        var thumbnails = Set<Data>()
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
            let thumbnailPNG = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            thumbnails.insert(thumbnailPNG)
            if let directory = ProcessInfo.processInfo.environment["JARVIS_RESUME_PREVIEW_DIR"] {
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(template.rawValue).png"))
                try thumbnailPNG.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(template.rawValue)-thumbnail.png"))
                let retina = try XCTUnwrap(ResumeTemplatePreviewRenderer.image(template: template, size: ResumeTemplateThumbnail.size, displayScale: 2))
                let retinaPNG = try XCTUnwrap(NSBitmapImageRep(cgImage: retina).representation(using: .png, properties: [:]))
                try retinaPNG.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(template.rawValue)-retina.png"))
            }
        }
        XCTAssertEqual(renders.count, 15)
        XCTAssertEqual(thumbnails.count, 15, "骨架缩略图仍需保留每套模板的视觉差异")
    }
}
