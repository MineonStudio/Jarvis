import SwiftUI

struct ResumePageBody: View {
    let document: ResumeDocument
    let content: ResumePageContent
    let showsPlaceholders: Bool
    let selectedProjectID: UUID?
    let selectedBulletIndex: Int?
    let onSelectProject: (UUID) -> Void
    let onSelectBullet: (UUID, Int) -> Void

    private var template: ResumeTemplate {
        document.template
    }

    var body: some View {
        ResumeTemplateLayout(template: template, includesHeader: content.includesHeader) {
            ResumePageHeader(document: document, template: template, showsPlaceholders: showsPlaceholders)
        } section: { kind in
            if showsPlaceholders {
                placeholder(kind)
            } else {
                populatedSection(kind)
            }
        }
    }

    @ViewBuilder
    private func populatedSection(_ kind: ResumeSection) -> some View {
        switch kind {
        case .education:
            if !content.education.isEmpty {
                ResumePageSection(title: kind.title, template: template, isSidebar: isSidebar(kind)) {
                    ForEach(content.education) { ResumePageEducation(item: $0, template: template) }
                }
            }
        case .experience:
            if !content.experience.isEmpty {
                ResumePageSection(title: kind.title, template: template, isSidebar: isSidebar(kind)) {
                    ForEach(content.experience) { ResumePageExperience(item: $0, template: template) }
                }
            }
        case .skills:
            if !content.skills.isEmpty {
                ResumePageSection(title: kind.title, template: template, isSidebar: isSidebar(kind)) {
                    ResumePageSkills(skills: content.skills, template: template)
                }
            }
        case .projects:
            if !content.projects.isEmpty {
                ResumePageSection(title: kind.title, template: template, isSidebar: isSidebar(kind)) {
                    ForEach(Array(content.projects.enumerated()), id: \.element.id) { index, project in
                        ResumePageProject(
                            project: project,
                            template: template,
                            index: (document.projects.firstIndex { $0.id == project.id } ?? index) + 1,
                            selectedProjectID: selectedProjectID,
                            selectedBulletIndex: selectedBulletIndex,
                            onSelectProject: onSelectProject,
                            onSelectBullet: onSelectBullet
                        )
                    }
                }
            }
        case .basicInfo: EmptyView()
        }
    }

    private func placeholder(_ kind: ResumeSection) -> some View {
        ResumePageSection(title: kind.title, template: template, isSidebar: isSidebar(kind)) {
            switch kind {
            case .education:
                VStack(alignment: .leading, spacing: 7) {
                    ResumePagePlaceholderField(title: "学校", template: template, isSidebar: isSidebar(kind))
                    ResumePagePlaceholderField(title: "学历 · 专业 / 时间", template: template, isSidebar: isSidebar(kind))
                }
            case .experience:
                VStack(alignment: .leading, spacing: 7) {
                    ResumePagePlaceholderField(title: "公司 · 职位", template: template, isSidebar: isSidebar(kind))
                    ResumePagePlaceholderField(title: "任职时间", template: template, isSidebar: isSidebar(kind))
                }
            case .skills:
                ResumePagePlaceholderField(title: "技能 · 专长", template: template, isSidebar: isSidebar(kind))
            case .projects:
                VStack(alignment: .leading, spacing: 10) {
                    ResumePagePlaceholderField(title: "项目名称 / 时间", template: template, isSidebar: isSidebar(kind))
                    ResumePagePlaceholderField(title: "项目简介", template: template, isSidebar: isSidebar(kind))
                    ResumePagePlaceholderField(title: "项目要点", template: template, isSidebar: isSidebar(kind))
                }
            case .basicInfo: EmptyView()
            }
        }
    }

    private func isSidebar(_ kind: ResumeSection) -> Bool {
        template.usesDarkSidebar && (kind == .education || kind == .skills)
    }
}
