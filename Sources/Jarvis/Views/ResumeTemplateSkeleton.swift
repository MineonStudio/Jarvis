import SwiftUI

/// Gallery-only preview: readable identity and section headings, with simplified
/// body lines. The actual document and export keep their original typography.
struct ResumeTemplateSkeleton: View {
    let template: ResumeTemplate

    var body: some View {
        ResumeTemplateLayout(template: template, includesHeader: true) {
            ResumeSkeletonHeader(template: template)
        } section: { kind in
            ResumeSkeletonSection(template: template, kind: kind)
        }
        .frame(width: ResumePageLayout.pageSize.width, height: ResumePageLayout.pageSize.height, alignment: .topLeading)
        .background { ResumePaperDecoration(template: template) }
        .clipped()
    }
}

private struct ResumeSkeletonBar: View {
    var fraction: CGFloat = 1
    var height: CGFloat = 5.5
    var color = ResumePaperPalette.body.opacity(0.18)
    var alignment: Alignment = .leading

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: min(3, height / 2))
                .fill(color)
                .frame(width: proxy.size.width * fraction, height: height)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .frame(height: height)
    }
}

private struct ResumeSkeletonHeader: View {
    let template: ResumeTemplate

    private var accent: Color {
        ResumePaperPalette.accent(for: template)
    }

    var body: some View {
        switch template {
        case .minimal:
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    name()
                    Spacer(minLength: 12)
                    role()
                }
                ResumeSkeletonBar(fraction: 0.6, height: 5)
            }.padding(.bottom, 12)
        case .mono, .classic, .heritage:
            identity(centered: true)
                .padding(.horizontal, template == .heritage ? 50 : 0)
                .padding(.vertical, template == .heritage ? 10 : 0)
                .overlay {
                    if template == .heritage {
                        Rectangle().stroke(accent.opacity(0.35), lineWidth: 1)
                    }
                }
        case .business, .grid, .orbit:
            VStack(alignment: .leading, spacing: 20) {
                if template == .orbit {
                    Circle().stroke(ResumePaperPalette.lime, lineWidth: 3)
                        .frame(width: 106, height: 106)
                        .overlay { name(reversed: true) }
                    role(reversed: true)
                } else {
                    identity(narrow: true, reversed: template == .business)
                }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach([0.85, 0.6], id: \.self) { fraction in
                        ResumeSkeletonBar(fraction: fraction, height: 5, color: template.usesDarkSidebar ? .white.opacity(0.35) : ResumePaperPalette.body.opacity(0.18))
                    }
                }
            }
        case .summit, .gazette, .creative:
            banner
        case .editorial, .slate:
            HStack(alignment: .top, spacing: 32) {
                identity()
                VStack(spacing: 12) {
                    ResumeSkeletonBar(fraction: 0.85, height: 5)
                    ResumeSkeletonBar(fraction: 0.65, height: 5)
                }.frame(width: 150).padding(.top, 8)
            }
        case .scholar, .journal:
            identity()
        case .prism:
            identity()
                .padding(.trailing, 80)
                .overlay(alignment: .topTrailing) {
                    Rectangle().stroke(accent, lineWidth: 8)
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(35)).offset(x: 22, y: -18)
                }
                .clipped()
        }
    }

    private var banner: some View {
        identity(reversed: true)
            .padding(34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(template == .gazette ? ResumePaperPalette.ink : accent)
            .overlay(alignment: .bottom) {
                if template != .creative {
                    Rectangle().fill(template == .summit ? ResumePaperPalette.gold : ResumePaperPalette.amber).frame(height: 5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if template == .creative {
                    Circle().stroke(ResumePaperPalette.lime, lineWidth: 18)
                        .frame(width: 136, height: 136).offset(x: 28, y: -40)
                }
            }
            .clipped()
    }

    private func identity(centered: Bool = false, narrow: Bool = false, reversed: Bool = false) -> some View {
        let alignment: Alignment = centered ? .center : .leading
        return VStack(alignment: centered ? .center : .leading, spacing: 12) {
            ResumeSkeletonBar(fraction: narrow ? 0.3 : 0.15, height: 3, color: reversed ? .white.opacity(0.35) : accent.opacity(0.35), alignment: alignment)
            name(reversed: reversed)
            role(reversed: reversed)
            if !narrow {
                ResumeSkeletonBar(fraction: 0.56, height: 5, color: reversed ? .white.opacity(0.3) : ResumePaperPalette.body.opacity(0.18), alignment: alignment)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var nameSize: CGFloat {
        switch template {
        case .business, .grid: 36
        case .orbit: 30
        case .classic, .heritage: 42
        case .editorial, .journal, .prism: 48
        default: 44
        }
    }

    private var nameWeight: Font.Weight {
        switch template {
        case .minimal, .mono, .classic, .heritage, .scholar: .regular
        case .creative, .prism, .gazette: .bold
        default: .semibold
        }
    }

    private func name(reversed: Bool = false) -> some View {
        Text("林知远")
            .font(.system(size: nameSize, weight: nameWeight, design: template.bodyFontDesign))
            .foregroundStyle(reversed ? .white : ResumePaperPalette.ink)
            .lineLimit(1).minimumScaleFactor(0.85)
    }

    private func role(reversed: Bool = false) -> some View {
        Text("产品经理")
            .font(.system(size: 24, weight: .medium, design: template.bodyFontDesign))
            .foregroundStyle(reversed ? (template == .creative || template == .orbit ? ResumePaperPalette.lime : .white.opacity(0.85)) : accent)
            .lineLimit(1).minimumScaleFactor(0.85)
    }
}

private struct ResumeSkeletonSection: View {
    let template: ResumeTemplate
    let kind: ResumeSection

    private var sidebar: Bool {
        template.usesDarkSidebar && [.education, .skills].contains(kind)
    }

    private var ink: Color {
        sidebar ? .white.opacity(0.35) : ResumePaperPalette.body.opacity(0.18)
    }

    private var accent: Color {
        sidebar ? (template == .orbit ? ResumePaperPalette.lime : ResumePaperPalette.sky) : ResumePaperPalette.accent(for: template)
    }

    var body: some View {
        Group {
            if template == .minimal {
                HStack(alignment: .top, spacing: 22) {
                    heading.frame(width: 88, alignment: .leading)
                    entries
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    heading
                    entries
                }
            }
        }
        .padding(.top, template.sectionSpacing)
    }

    @ViewBuilder
    private var heading: some View {
        if template == .classic {
            HStack(spacing: 16) {
                Rectangle().fill(ResumePaperPalette.gold.opacity(0.35)).frame(height: 1)
                headingText.fixedSize()
                Rectangle().fill(ResumePaperPalette.gold.opacity(0.35)).frame(height: 1)
            }
        } else {
            headingText
                .frame(maxWidth: .infinity, alignment: template == .heritage ? .center : .leading)
                .padding(.horizontal, highlighted ? 8 : 0)
                .padding(.vertical, highlighted ? 6 : 0)
                .background(highlighted ? headingBackground : .clear)
                .overlay(alignment: .bottom) {
                    if !highlighted, template != .minimal {
                        Rectangle().fill(accent.opacity(0.18)).frame(height: 1).offset(y: 6)
                    }
                }
        }
    }

    private var headingText: some View {
        Text(kind.title)
            .font(.system(size: template == .minimal ? 20 : 24, weight: .semibold, design: template.bodyFontDesign))
            .foregroundStyle(template == .gazette || template == .prism ? .white : accent)
            .lineLimit(1).minimumScaleFactor(0.85)
    }

    private var highlighted: Bool {
        [.creative, .gazette, .prism, .heritage].contains(template)
    }

    private var headingBackground: Color {
        switch template {
        case .creative: ResumePaperPalette.lime.opacity(0.6)
        case .gazette: ResumePaperPalette.ink
        case .prism: accent
        default: accent.opacity(0.08)
        }
    }

    @ViewBuilder
    private var entries: some View {
        if kind == .skills {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([0.7, 0.88, 0.54], id: \.self) { fraction in
                    ResumeSkeletonBar(fraction: fraction, color: ink)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: kind == .projects ? 28 : 20) {
                ForEach(0 ..< entryCount, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 11) {
                        ResumeSkeletonBar(fraction: index.isMultiple(of: 2) ? 0.56 : 0.66, height: 8, color: sidebar ? .white.opacity(0.65) : ResumePaperPalette.body.opacity(0.32))
                        ResumeSkeletonBar(fraction: 0.94, color: ink)
                        ResumeSkeletonBar(fraction: index.isMultiple(of: 2) ? 0.7 : 0.82, color: ink)
                    }
                }
            }
        }
    }

    private var entryCount: Int {
        switch kind {
        case .projects: 3
        case .experience: 2
        default: 1
        }
    }
}
