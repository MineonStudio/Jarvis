import SwiftUI

struct ResumePageSection<Content: View>: View {
    let title: String
    let template: ResumeTemplate
    var isSidebar = false
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if template.isVariant {
                VStack(alignment: .leading, spacing: 10) {
                    ResumeVariantSectionHeading(title: title, template: template, isSidebar: isSidebar)
                    content
                }
            } else if template == .minimal {
                HStack(alignment: .top, spacing: 22) {
                    heading.frame(width: 66, alignment: .leading)
                    VStack(alignment: .leading, spacing: 9) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: template == .classic ? 10 : 13) {
                    sectionHeading
                    content
                }
            }
        }
        .padding(.top, template.sectionSpacing)
    }

    private var heading: some View {
        Text(title)
            .font(.system(size: headingSize, weight: template == .classic ? .medium : .bold, design: template.bodyFontDesign))
            .foregroundStyle(isSidebar ? ResumePaperPalette.sky : ResumePaperPalette.accent(for: template))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var sectionHeading: some View {
        switch template {
        case .classic:
            HStack(spacing: 12) {
                line
                heading
                line
            }
        case .business:
            VStack(alignment: .leading, spacing: 9) { heading; line }
        case .creative:
            heading
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(ResumePaperPalette.lime)
        case .editorial:
            VStack(alignment: .leading, spacing: 8) {
                heading
                line
            }
        case .minimal: heading
        default: EmptyView()
        }
    }

    private var headingSize: CGFloat {
        switch template {
        case .minimal: 10
        case .business: 12
        case .classic: 12
        case .editorial: 19
        case .creative: 11
        default: 11
        }
    }

    private var line: some View {
        Rectangle()
            .fill(isSidebar ? Color.white.opacity(0.25) : ResumePaperPalette.accent(for: template).opacity(0.3))
            .frame(height: 0.6)
    }
}

struct ResumePageEducation: View {
    let item: ResumeEducation
    let template: ResumeTemplate

    var body: some View {
        ResumeEntryRow(
            title: item.school,
            subtitle: [item.degree, item.major].filter { !$0.isEmpty }.joined(separator: " · "),
            period: item.period,
            template: template,
            isSidebar: template.usesDarkSidebar
        )
    }
}

struct ResumePageExperience: View {
    let item: ResumeExperience
    let template: ResumeTemplate

    var body: some View {
        ResumeEntryRow(title: item.company, subtitle: item.role, period: item.period, template: template)
    }
}

struct ResumeEntryRow: View {
    let title: String
    let subtitle: String
    let period: String
    let template: ResumeTemplate
    var isSidebar = false

    var body: some View {
        Group {
            if template.isVariant {
                ResumeVariantEntry(title: title, subtitle: subtitle, period: period, template: template, isSidebar: isSidebar)
            } else if template == .classic {
                HStack(alignment: .top, spacing: 18) {
                    periodText.frame(width: 104, alignment: .leading)
                    details
                }
            } else if template == .minimal {
                HStack(alignment: .top, spacing: 12) {
                    details
                    Spacer(minLength: 4)
                    periodText
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    if template == .business && !isSidebar {
                        periodText
                    }
                    details
                    if template != .business || isSidebar {
                        periodText
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: template == .business && !isSidebar ? 13 : 11.5, weight: .semibold, design: template.bodyFontDesign))
                .foregroundStyle(isSidebar ? .white : ResumePaperPalette.ink)
            Text(subtitle)
                .font(.system(size: 10.5, design: template.bodyFontDesign))
                .foregroundStyle(isSidebar ? .white.opacity(0.85) : ResumePaperPalette.body)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var periodText: some View {
        Text(period)
            .font(.system(size: 9, design: template.bodyFontDesign))
            .foregroundStyle(isSidebar ? ResumePaperPalette.sky : ResumePaperPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ResumePageSkills: View {
    let skills: [String]
    let template: ResumeTemplate

    var body: some View {
        if template == .business || template == .creative || template == .editorial || [.mono, .grid, .slate, .scholar, .gazette, .orbit].contains(template) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in skillText(skill) }
            }
        } else {
            ResumeTextFlowLayout(spacing: 14, lineSpacing: 8) {
                ForEach(Array(skills.enumerated()), id: \.offset) { _, skill in skillText(skill) }
            }
        }
    }

    private func skillText(_ skill: String) -> some View {
        Text(skill)
            .font(.system(size: 10.5, design: template.bodyFontDesign))
            .foregroundStyle(template.usesDarkSidebar ? .white.opacity(0.9) : ResumePaperPalette.body)
    }
}

struct ResumeTextFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = measuredSize(of: subview, maxWidth: maxWidth)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, lineCount: Int) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var lineCount = 1
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = measuredSize(of: subview, maxWidth: maxWidth)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
                lineCount += 1
            }
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
        }
        let width = maxWidth.isFinite ? maxWidth : usedWidth
        return (CGSize(width: width, height: y + lineHeight), lineCount)
    }

    private func measuredSize(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let naturalSize = subview.sizeThatFits(.unspecified)
        return subview.sizeThatFits(ProposedViewSize(width: min(naturalSize.width, maxWidth), height: nil))
    }
}
