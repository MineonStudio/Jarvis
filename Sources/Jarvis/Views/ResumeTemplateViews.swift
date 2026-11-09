import SwiftUI

struct ResumeTemplateSelectionView: View {
    let category: ResumeTemplateCategory
    let onSelect: (ResumeTemplate) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(
                        .adaptive(minimum: ResumeTemplateThumbnail.size.width, maximum: ResumeTemplateThumbnail.size.width),
                        spacing: HistoryGridMetrics.clipboardGridSpacing,
                        alignment: .leading
                    )],
                    alignment: .leading,
                    spacing: HistoryGridMetrics.clipboardGridSpacing
                ) {
                    ForEach(category.templates) { template in
                        ResumeTemplateCard(template: template, onSelect: onSelect)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, JarvisMetrics.shellHorizontalPadding)
                .padding(.bottom, HistoryGridMetrics.historyPanelInset)
                .frame(minHeight: max(proxy.size.height, 430), alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.jarvisBackground)
    }
}

private struct ResumeTemplateCard: View {
    let template: ResumeTemplate
    let onSelect: (ResumeTemplate) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var styleTitle: String {
        template.category.title
    }

    var body: some View {
        VStack(spacing: JarvisSpacing.controlGap) {
            HistoryCardChrome(
                preview: cover,
                width: ResumeTemplateThumbnail.size.width,
                height: ResumeTemplateThumbnail.size.height,
                isSelected: false,
                cornerRadius: 0
            )
            .overlay(alignment: .topTrailing) { useActionOverlay }
            .clipShape(Rectangle())
            .jarvisGridCardShadow(cornerRadius: 0)
            metadataRow
        }
        .frame(width: ResumeTemplateThumbnail.size.width)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onSelect(template) }
        .onHover { hovering in
            guard hovering != isHovered else { return }
            withAnimation(JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(styleTitle)，\(template.title)模板")
        .accessibilityHint("双击或点击悬浮的使用按钮来使用模板")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect(template) }
        .contextMenu {
            Button("使用") { onSelect(template) }
        }
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(ResumeTemplateThumbnail.size.width / ResumeTemplateThumbnail.size.height, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { geometry in
                    ResumeTemplateThumbnail(template: template)
                        .scaleEffect(geometry.size.width / ResumeTemplateThumbnail.size.width, anchor: .topLeading)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
            }
            .clipped()
    }

    private var metadataRow: some View {
        HStack(spacing: JarvisSpacing.iconGap) {
            Image(systemName: template.icon)
                .font(JarvisTypography.captionEmphasis)
                .fixedSize()
            Text(styleTitle)
                .font(JarvisTypography.caption)
                .lineLimit(1)
            Spacer(minLength: JarvisSpacing.textGap)
            Text(template.title)
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, JarvisSpacing.textGap)
    }

    @ViewBuilder
    private var useActionOverlay: some View {
        if isHovered {
            Button { onSelect(template) } label: {
                Text("使用")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(JarvisCardActionPillButtonStyle())
            .accessibilityLabel("使用\(template.title)模板")
            .padding(JarvisSpacing.controlGap)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
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
