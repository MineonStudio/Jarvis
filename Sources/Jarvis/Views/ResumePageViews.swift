import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ResumePageContent: Sendable {
    let includesHeader: Bool
    var education: [ResumeEducation]
    var experience: [ResumeExperience]
    var skills: [String]
    var projects: [ResumeProject]

    /// #31：本 struct 的 hasContent 已删除——分页入口用的是 ResumeDocument.hasContent，
    /// 这里这个零调用。判空直接看四个数组即可。
    static func fullDocument(_ document: ResumeDocument) -> Self {
        Self(
            includesHeader: true,
            education: document.education.filter(\.hasContent),
            experience: document.experience.filter(\.hasContent),
            skills: document.skills.filter(nonEmpty),
            projects: document.projects.filter(\.hasContent)
        )
    }

    private static func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
enum ResumePageLayout {
    static let pageSize = CGSize(width: 620, height: 876)
    static let pageSpacing: CGFloat = 16

    static func pages(for document: ResumeDocument) -> [ResumePageContent] {
        let fullContent = ResumePageContent.fullDocument(document)
        guard document.hasContent else { return [fullContent] }
        let pageItems = document.template.sectionOrder.flatMap { items(for: $0, content: fullContent) }

        var pages: [ResumePageContent] = []
        var current = ResumePageAccumulator(includesHeader: true)
        for item in pageItems {
            var candidate = current
            candidate.append(item)
            if current.hasSectionContent, contentHeight(for: document, content: candidate.content) > pageSize.height {
                pages.append(current.content)
                candidate = ResumePageAccumulator(includesHeader: false)
                candidate.append(item)
            }
            current = candidate
        }
        if current.hasSectionContent {
            pages.append(current.content)
        }
        return pages.isEmpty ? [fullContent] : pages
    }

    private static func items(for section: ResumeSection, content: ResumePageContent) -> [ResumePageItem] {
        switch section {
        case .education: content.education.map(ResumePageItem.education)
        case .experience: content.experience.map(ResumePageItem.experience)
        case .skills: content.skills.isEmpty ? [] : [.skills(content.skills)]
        case .projects: content.projects.map(ResumePageItem.project)
        case .basicInfo: []
        }
    }

    /// Measure the actual template composition: narrow columns, large project titles,
    /// and parallel sections cannot be paginated using a shared character estimate.
    static func contentHeight(for document: ResumeDocument, content: ResumePageContent) -> CGFloat {
        let body = ResumePageBody(
            document: document,
            content: content,
            showsPlaceholders: false,
            selectedProjectID: nil,
            selectedBulletIndex: nil,
            onSelectProject: { _ in },
            onSelectBullet: { _, _ in }
        )
        .frame(width: pageSize.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: body)
        renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: nil)
        var height: CGFloat = 0
        renderer.render { size, _ in height = size.height }
        return height
    }
}

private enum ResumePageItem {
    case education(ResumeEducation)
    case experience(ResumeExperience)
    case skills([String])
    case project(ResumeProject)
}

private struct ResumePageAccumulator {
    let includesHeader: Bool
    var education: [ResumeEducation] = []
    var experience: [ResumeExperience] = []
    var skills: [String] = []
    var projects: [ResumeProject] = []

    var hasSectionContent: Bool {
        !education.isEmpty || !experience.isEmpty || !skills.isEmpty || !projects.isEmpty
    }

    var content: ResumePageContent {
        ResumePageContent(
            includesHeader: includesHeader,
            education: education,
            experience: experience,
            skills: skills,
            projects: projects
        )
    }

    mutating func append(_ item: ResumePageItem) {
        switch item {
        case let .education(value):
            education.append(value)
        case let .experience(value):
            experience.append(value)
        case let .skills(values):
            skills.append(contentsOf: values)
        case let .project(value):
            projects.append(value)
        }
    }
}

struct ResumePageView: View {
    let document: ResumeDocument
    let selectedProjectID: UUID?
    let selectedBulletIndex: Int?
    let showsEmptyState: Bool
    let onSelectProject: (UUID) -> Void
    let onSelectBullet: (UUID, Int) -> Void
    let pageContent: ResumePageContent?

    init(
        document: ResumeDocument,
        selectedProjectID: UUID?,
        selectedBulletIndex: Int?,
        showsEmptyState: Bool,
        onSelectProject: @escaping (UUID) -> Void,
        onSelectBullet: @escaping (UUID, Int) -> Void,
        pageContent: ResumePageContent? = nil
    ) {
        self.document = document
        self.selectedProjectID = selectedProjectID
        self.selectedBulletIndex = selectedBulletIndex
        self.showsEmptyState = showsEmptyState
        self.onSelectProject = onSelectProject
        self.onSelectBullet = onSelectBullet
        self.pageContent = pageContent
    }

    var body: some View {
        let content = pageContent ?? ResumePageContent.fullDocument(document)
        Group {
            if document.hasContent {
                templateLayout(content)
            } else if showsEmptyState {
                templatePlaceholderLayout
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(width: 620, height: 876, alignment: .topLeading)
        .background { ResumePaperDecoration(template: document.template) }
        .foregroundStyle(ResumePaperPalette.ink)
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .strokeBorder(ResumePaperPalette.softLine, lineWidth: 0.8)
        }
    }

    private func templateLayout(_ content: ResumePageContent) -> some View {
        ResumePageBody(
            document: document,
            content: content,
            showsPlaceholders: false,
            selectedProjectID: selectedProjectID,
            selectedBulletIndex: selectedBulletIndex,
            onSelectProject: onSelectProject,
            onSelectBullet: onSelectBullet
        )
    }

    private var templatePlaceholderLayout: some View {
        ResumePageBody(
            document: document,
            content: .fullDocument(document),
            showsPlaceholders: true,
            selectedProjectID: nil,
            selectedBulletIndex: nil,
            onSelectProject: { _ in },
            onSelectBullet: { _, _ in }
        )
    }
}

struct ResumePagePlaceholderField: View {
    let title: String
    let template: ResumeTemplate
    var isSidebar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(
                    size: template.category == .classic ? 10 : 9.5,
                    weight: .regular,
                    design: template.bodyFontDesign
                ))
                .foregroundStyle(isSidebar ? .white.opacity(0.8) : ResumePaperPalette.muted.opacity(0.78))
                .lineLimit(1)
            Rectangle()
                .fill(isSidebar ? .white.opacity(0.25) : ResumePaperPalette.softLine)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ResumePagedView: View {
    let document: ResumeDocument
    let selectedProjectID: UUID?
    let selectedBulletIndex: Int?
    let showsEmptyState: Bool
    let onSelectProject: (UUID) -> Void
    let onSelectBullet: (UUID, Int) -> Void

    var body: some View {
        let pages = ResumePageLayout.pages(for: document)
        VStack(spacing: ResumePageLayout.pageSpacing) {
            ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                ResumePageView(
                    document: document,
                    selectedProjectID: selectedProjectID,
                    selectedBulletIndex: selectedBulletIndex,
                    showsEmptyState: showsEmptyState,
                    onSelectProject: onSelectProject,
                    onSelectBullet: onSelectBullet,
                    pageContent: page
                )
            }
        }
    }
}

enum ResumeExportService {
    @MainActor
    static func data(for document: ResumeDocument, format: ResumeExportFormat) throws -> Data {
        switch format {
        case .pdf:
            try pdfData(for: document)
        case .markdown:
            Data(ResumeTextFormatter.markdown(for: document).utf8)
        case .json:
            try ResumeDocumentCodec.encodedData(for: document)
        }
    }

    @MainActor
    private static func pdfData(for document: ResumeDocument) throws -> Data {
        let pages = ResumePageLayout.pages(for: document)
        let pageRect = CGRect(
            origin: .zero,
            size: ResumePageLayout.pageSize
        )
        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ResumeExportError.renderingFailed
        }

        for page in pages {
            let printablePage = ResumePageView(
                document: document,
                selectedProjectID: nil,
                selectedBulletIndex: nil,
                showsEmptyState: false,
                onSelectProject: { _ in },
                onSelectBullet: { _, _ in },
                pageContent: page
            )
            let renderer = ImageRenderer(content: printablePage)
            renderer.proposedSize = ProposedViewSize(
                width: ResumePageLayout.pageSize.width,
                height: ResumePageLayout.pageSize.height
            )
            renderer.scale = 2

            guard let image = renderer.nsImage,
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                throw ResumeExportError.renderingFailed
            }

            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(pageRect)
            context.draw(cgImage, in: pageRect)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

private enum ResumeExportError: Error {
    case renderingFailed
}
