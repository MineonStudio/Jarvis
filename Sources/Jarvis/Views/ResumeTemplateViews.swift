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
        ResumeTemplateCategory.allCases.first {
            $0 != .all && $0.templates.contains(template)
        }?.title ?? ResumeTemplateCategory.all.title
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

private struct ResumeTemplateThumbnail: View {
    static let size = CGSize(width: 168, height: 237)
    let template: ResumeTemplate

    var body: some View {
        page
            .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
            .background(Color.white)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var page: some View {
        switch template {
        case .creative:
            ZStack(alignment: .topLeading) {
                ResumePaperPalette.violet.opacity(0.09)
                Circle()
                    .fill(ResumePaperPalette.coral.opacity(0.84))
                    .frame(width: 56, height: 56)
                    .offset(x: 112, y: -18)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 5) {
                        Rectangle()
                            .fill(ResumePaperPalette.coral)
                            .frame(width: 26, height: 3)
                        Text("CREATE")
                            .font(.system(size: 5.5, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(ResumePaperPalette.coral)
                    }
                    Text("林知远")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(ResumePaperPalette.ink)
                    Text("产品经理 · 设计思维")
                        .font(.system(size: 6, weight: .medium, design: .rounded))
                        .foregroundStyle(ResumePaperPalette.muted)
                    miniSection(title: "关于我", accent: ResumePaperPalette.coral)
                    miniSkills(["用户研究", "产品策略", "品牌设计"], fill: ResumePaperPalette.coral.opacity(0.12))
                    miniSection(title: "精选项目", accent: ResumePaperPalette.violet)
                }
            }
            .padding(17)
        case .editorial:
            VStack(alignment: .center, spacing: 8) {
                Text("CURRICULUM VITAE")
                    .font(.system(size: 5, weight: .semibold, design: .serif))
                    .kerning(1)
                    .foregroundStyle(ResumePaperPalette.muted)
                Text("林知远")
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(ResumePaperPalette.ink)
                Text("产品经理")
                    .font(.system(size: 6, weight: .medium, design: .serif))
                    .foregroundStyle(ResumePaperPalette.muted)
                divider
                miniSection(title: "教育经历", accent: ResumePaperPalette.ink)
                miniSection(title: "工作经历", accent: ResumePaperPalette.ink)
                miniSkillsTitle("掌握技能")
                miniSkills(["产品规划", "用户研究", "数据分析"], fill: ResumePaperPalette.ink.opacity(0.08))
                miniSection(title: "项目经历", accent: ResumePaperPalette.ink)
            }
            .padding(19)
        case .minimal:
            VStack(alignment: .leading, spacing: 11) {
                Text("林知远")
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .foregroundStyle(ResumePaperPalette.ink)
                Text("产品经理  ·  上海  ·  6年经验")
                    .font(.system(size: 5.5, weight: .medium, design: .rounded))
                    .foregroundStyle(ResumePaperPalette.muted)
                Rectangle()
                    .fill(ResumePaperPalette.ink)
                    .frame(height: 2)
                miniMinimalSection("教育经历")
                miniMinimalSection("工作经历")
                miniSkillsTitle("掌握技能")
                miniSkills(["产品规划", "用户研究", "数据分析"], fill: ResumePaperPalette.blue.opacity(0.12))
                miniMinimalSection("项目经历")
            }
            .padding(18)
        case .timeline:
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 6) {
                    ForEach(0 ..< 5, id: \.self) { _ in
                        Circle()
                            .fill(ResumePaperPalette.teal)
                            .frame(width: 6, height: 6)
                        Rectangle()
                            .fill(ResumePaperPalette.teal.opacity(0.28))
                            .frame(width: 1, height: 28)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("林知远")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(ResumePaperPalette.ink)
                    Text("成长轨迹")
                        .font(.system(size: 6, weight: .semibold))
                        .foregroundStyle(ResumePaperPalette.teal)
                    miniTimelineSection("2021 — 至今", "高级产品经理")
                    miniTimelineSection("2018 — 2021", "产品经理")
                    miniTimelineSection("2015 — 2018", "计算机科学 · 硕士")
                    miniSkills(["产品规划", "用户研究", "数据分析"], fill: ResumePaperPalette.teal.opacity(0.12))
                }
            }
            .padding(16)
        }
    }

    private func miniSection(title: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .foregroundStyle(ResumePaperPalette.ink)
                Spacer(minLength: 0)
            }
            miniLine(width: nil, color: accent.opacity(0.32))
            miniLine(width: 90, color: ResumePaperPalette.body.opacity(0.24))
            miniLine(width: 68, color: ResumePaperPalette.muted.opacity(0.16))
        }
    }

    private func miniLine(width: CGFloat?, color: Color = .black.opacity(0.22)) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: 2)
    }

    private var divider: some View {
        divider(color: ResumePaperPalette.muted)
    }

    private func divider(color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }

    private func miniSkillsTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 5.5, weight: .bold, design: .rounded))
            .foregroundStyle(ResumePaperPalette.muted)
    }

    private func miniSkills(_ skills: [String], fill: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(skills, id: \.self) { skill in
                Text(skill)
                    .font(.system(size: 4.5, weight: .medium, design: .rounded))
                    .foregroundStyle(ResumePaperPalette.body)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(fill, in: Capsule())
            }
        }
    }

    private func miniMinimalSection(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 5.5, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(ResumePaperPalette.muted)
            miniLine(width: nil, color: ResumePaperPalette.softLine)
            miniLine(width: 86, color: ResumePaperPalette.body.opacity(0.35))
            miniLine(width: 61, color: ResumePaperPalette.muted.opacity(0.22))
        }
    }

    private func miniTimelineSection(_ period: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(period)
                .font(.system(size: 5, weight: .bold, design: .rounded))
                .foregroundStyle(ResumePaperPalette.teal)
            Text(title)
                .font(.system(size: 6.5, weight: .semibold, design: .rounded))
                .foregroundStyle(ResumePaperPalette.ink)
            miniLine(width: 86, color: ResumePaperPalette.muted.opacity(0.25))
        }
    }
}
