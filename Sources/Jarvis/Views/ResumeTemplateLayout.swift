import SwiftUI

struct ResumeTemplateLayout<Header: View, SectionContent: View>: View {
    let template: ResumeTemplate
    let includesHeader: Bool
    @ViewBuilder let header: Header
    @ViewBuilder let section: (ResumeSection) -> SectionContent

    var body: some View {
        composition
            .padding(.horizontal, template.pageHorizontalPadding)
            .padding(.vertical, template.pageVerticalPadding)
    }

    @ViewBuilder
    private var composition: some View {
        switch template {
        case .minimal: minimal
        case .business: business
        case .classic: classic
        case .editorial: editorial
        case .creative: creative
        default:
            ResumeVariantLayout(template: template, includesHeader: includesHeader) {
                header
            } section: { section($0) }
        }
    }

    private var minimal: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header.padding(.bottom, 10)
                rule(color: .black, height: 1.2)
            }
            ForEach(template.sectionOrder) { section($0) }
        }
    }

    private var business: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if includesHeader {
                    header.padding(.bottom, 14)
                }
                section(.education)
                section(.skills)
            }
            .padding(.horizontal, 23)
            .padding(.top, 42)
            .padding(.bottom, 36)
            .frame(width: 196, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                section(.experience)
                section(.projects)
            }
            .padding(.horizontal, 30)
            .padding(.top, 22)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var classic: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header.padding(.bottom, 22)
                rule(color: ResumePaperPalette.gold, height: 0.8)
                    .padding(.bottom, 3)
                rule(color: ResumePaperPalette.gold.opacity(0.5), height: 0.5)
            }
            ForEach(template.sectionOrder) { section($0) }
        }
    }

    private var editorial: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header.padding(.bottom, 18)
                rule(color: ResumePaperPalette.ink, height: 3)
            }
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 0) {
                    section(.experience)
                    section(.education)
                    section(.skills)
                }
                .frame(width: 172, alignment: .leading)
                .padding(.trailing, 16)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(ResumePaperPalette.ink.opacity(0.25)).frame(width: 0.6)
                }
                VStack(alignment: .leading, spacing: 0) { section(.projects) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var creative: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header
            }
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 0) { section(.projects) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    section(.skills)
                    section(.education)
                    section(.experience)
                }
                .frame(width: 146, alignment: .leading)
            }
            .padding(.horizontal, 34)
            .padding(.top, includesHeader ? 8 : 20)
            .padding(.bottom, 38)
        }
    }

    private func rule(color: Color, height: CGFloat) -> some View {
        Rectangle().fill(color).frame(height: height)
    }
}
