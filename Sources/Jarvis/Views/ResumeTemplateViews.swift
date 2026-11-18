import SwiftUI

struct ResumeTemplateSelectionView: View {
    let category: ResumeTemplateCategory
    let gridZoom: HistoryGridZoomLevel
    let onSelect: (ResumeTemplate) -> Void
    @State private var selection = GallerySelection<ResumeTemplate.ID>()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                FixedRatioGallery(
                    items: category.templates,
                    availableWidth: proxy.size.width - JarvisMetrics.shellHorizontalPadding * 2,
                    targetWidth: ResumeTemplateThumbnail.size.width * gridZoom.cardWidth / HistoryGridZoomLevel.regular.cardWidth,
                    aspectRatio: ResumeTemplateThumbnail.size.width / ResumeTemplateThumbnail.size.height,
                    card: card
                )
                .padding(.horizontal, JarvisMetrics.shellHorizontalPadding)
                .padding(.bottom, HistoryGridMetrics.historyPanelInset)
                .galleryBackground(minHeight: max(proxy.size.height, 430)) { selection.clear() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.jarvisBackground)
        .onChange(of: category) { _, category in
            selection.retain(Set(category.templates.map(\.id)).contains)
        }
    }

    private func card(_ template: ResumeTemplate, _ size: CGSize) -> some View {
        let isSelected = selection.selectedID == template.id
        return GalleryCard(
            size: size, isSelected: isSelected, enablesHoverZoom: gridZoom.enablesHoverZoom,
            onClick: { count in
                GallerySelection.handleClick(count, on: template.id, selection: $selection) { onSelect(template) }
            },
            preview: {
                ResumeTemplateThumbnail(template: template)
                    .scaleEffect(size.width / ResumeTemplateThumbnail.size.width, anchor: .topLeading)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
            },
            leading: { Label(template.category.title, systemImage: template.icon) },
            trailing: { Text(template.title) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(template.category.title)，\(template.title)模板")
        .accessibilityHint("点击切换选中，双击使用模板")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection.toggle(template.id) }
        .accessibilityAction(named: "使用模板") { onSelect(template) }
        .contextMenu {
            Button("使用") { onSelect(template) }
        }
    }
}

struct ResumeTemplateThumbnail: View {
    static let size = CGSize(width: 168, height: 237)
    let template: ResumeTemplate

    var body: some View {
        let document = Self.sampleDocument(template: template)
        ResumePageView(
            document: document,
            selectedProjectID: nil,
            selectedBulletIndex: nil,
            showsEmptyState: false,
            onSelectProject: { _ in },
            onSelectBullet: { _, _ in },
            pageContent: ResumePageLayout.pages(for: document).first
        )
        .scaleEffect(Self.size.width / ResumePageLayout.pageSize.width, anchor: .topLeading)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Only the gallery uses sample content; selecting a template still creates a blank resume.
    static func sampleDocument(template: ResumeTemplate) -> ResumeDocument {
        ResumeDocument(
            template: template,
            basicInfo: ResumeBasicInfo(
                name: "林知远", headline: "高级产品经理", email: "zhiyuan.lin@example.com",
                location: "上海", jobStatus: "在职 · 寻找新机会", workYears: "6 年经验"
            ),
            education: [ResumeEducation(
                school: "上海交通大学", degree: "硕士", major: "计算机科学", period: "2017 — 2020"
            )],
            experience: [
                ResumeExperience(company: "星云科技", role: "高级产品经理", period: "2023 — 至今"),
                ResumeExperience(company: "远航软件", role: "产品经理", period: "2020 — 2023")
            ],
            skills: ["产品策略", "用户研究", "数据分析", "交互设计", "SQL / Figma", "跨团队协作"],
            projects: [
                ResumeProject(
                    name: "企业协作平台", period: "2024 — 2025",
                    summary: "面向中大型企业的一体化协作产品，覆盖需求管理、项目推进与知识沉淀，支持多团队异步协作。",
                    bullets: [
                        "访谈 30 家企业客户，梳理核心协作流程，制定产品路线图并推进三个版本落地。",
                        "联合设计与研发优化任务分派和进度追踪，关键任务完成率由 68% 提升至 89%。"
                    ]
                ),
                ResumeProject(
                    name: "客户增长计划", period: "2022 — 2023",
                    summary: "围绕客户全生命周期，搭建增长实验与运营分析体系，将产品使用数据转化为可执行的运营策略。",
                    bullets: [
                        "建立从注册到付费的指标体系，通过分层实验改善关键转化环节。",
                        "协同运营建立客户反馈闭环，推动新用户激活率提升 24%。"
                    ]
                ),
                ResumeProject(
                    name: "设计系统与体验升级", period: "2021 — 2022",
                    summary: "统一核心产品的交互规范与组件语言，提升跨端使用体验及团队交付效率。",
                    bullets: ["整理 40 余个常用组件，建立设计评审与体验验收机制，减少重复设计和沟通成本。"]
                )
            ]
        )
    }
}
