import AppKit
@testable import Jarvis
import PDFKit
import XCTest

@MainActor
final class ResumePaginationTests: XCTestCase {
    func testManySkillsRemainVisibleAcrossPagesInEveryTemplate() throws {
        let skills = (1 ... 45).map { "技能\($0)" }
        for template in ResumeTemplate.allCases {
            let sample = ResumeTemplateThumbnail.sampleDocument(template: template)
            let document = ResumeDocument(template: template, basicInfo: sample.basicInfo, skills: skills)
            let pages = ResumePageLayout.pages(for: document)

            XCTAssertEqual(pages.flatMap(\.skills), skills, template.title)
            for page in pages {
                XCTAssertLessThanOrEqual(
                    ResumePageLayout.contentHeight(for: document, content: page),
                    ResumePageLayout.pageSize.height,
                    "\(template.title) 的技能列表不能超出纸张"
                )
            }
            if template == .creative {
                XCTAssertGreaterThan(pages.count, 1)
            }
            let pdf = try XCTUnwrap(PDFDocument(data: ResumeExportService.data(for: document, format: .pdf)))
            XCTAssertEqual(pdf.pageCount, pages.count, template.title)
        }
    }
}
