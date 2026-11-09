import SwiftUI

struct ResumeVariantSectionHeading: View {
    let title: String
    let template: ResumeTemplate
    let isSidebar: Bool

    private var accent: Color {
        ResumePaperPalette.accent(for: template)
    }

    private var text: some View {
        Text(title)
            .font(.system(size: fontSize, weight: template.category == .classic ? .medium : .semibold, design: template.bodyFontDesign))
            .foregroundStyle(isSidebar ? ResumePaperPalette.lime : accent)
    }

    var body: some View {
        switch template {
        case .mono, .slate, .orbit:
            VStack(alignment: .leading, spacing: 7) { text; line }
        case .grid:
            text.tracking(2).padding(.bottom, 4)
        case .summit:
            HStack(spacing: 10) {
                Rectangle().fill(ResumePaperPalette.gold).frame(width: 4, height: 14)
                text
                line
            }
        case .heritage:
            text.frame(maxWidth: .infinity).padding(.vertical, 3)
                .background(accent.opacity(0.05))
                .overlay(alignment: .top) { line }
                .overlay(alignment: .bottom) { line }
        case .scholar:
            text.italic()
        case .journal:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                text
                Spacer(minLength: 0)
                Text("/ " + label).font(.system(size: 7, weight: .medium)).tracking(1)
                    .foregroundStyle(ResumePaperPalette.muted)
            }
        case .gazette:
            Text(title).font(.system(size: 11, weight: .bold, design: .serif)).foregroundStyle(.white)
                .padding(.vertical, 6).padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ResumePaperPalette.ink)
        case .prism:
            Text(title).font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(.white)
                .padding(.vertical, 5).padding(.horizontal, 9).background(accent)
        default: text
        }
    }

    private var line: some View {
        Rectangle().fill(isSidebar ? .white.opacity(0.25) : accent.opacity(0.25)).frame(height: 0.5)
    }

    private var fontSize: CGFloat {
        switch template {
        case .journal: 16
        case .scholar: 14
        default: 11
        }
    }

    private var label: String {
        ["项目经历": "PROJECTS", "工作经历": "EXPERIENCE", "教育经历": "EDUCATION", "掌握技能": "SKILLS"][title] ?? "PROFILE"
    }
}

struct ResumeVariantEntry: View {
    let title: String
    let subtitle: String
    let period: String
    let template: ResumeTemplate
    let isSidebar: Bool

    var body: some View {
        if template == .summit || template == .heritage {
            HStack(alignment: .top, spacing: 18) {
                date.frame(width: 100, alignment: .leading)
                details
            }
        } else if template == .prism {
            HStack(alignment: .top, spacing: 10) {
                details
                date.frame(width: 76, alignment: .trailing)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                details
                date
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11.5, weight: .semibold, design: template.bodyFontDesign))
                .foregroundStyle(isSidebar ? .white : ResumePaperPalette.ink)
            Text(subtitle).font(.system(size: 10.5, design: template.bodyFontDesign))
                .foregroundStyle(isSidebar ? .white.opacity(0.85) : ResumePaperPalette.body)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var date: some View {
        Text(period).font(.system(size: 9, design: template.bodyFontDesign))
            .foregroundStyle(isSidebar ? .white.opacity(0.7) : ResumePaperPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
