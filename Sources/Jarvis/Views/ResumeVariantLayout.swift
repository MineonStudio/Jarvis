import SwiftUI

struct ResumeVariantLayout<Header: View, SectionContent: View>: View {
    let template: ResumeTemplate
    let includesHeader: Bool
    @ViewBuilder let header: Header
    @ViewBuilder let section: (ResumeSection) -> SectionContent

    var body: some View {
        switch template {
        case .mono: mono
        case .grid: grid
        case .summit: summit
        case .slate: slate
        case .heritage: heritage
        case .scholar: scholar
        case .journal: journal
        case .gazette: gazette
        case .prism: prism
        case .orbit: orbit
        default: EmptyView()
        }
    }

    private var mono: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header.padding(.bottom, 20); rule
            }
            HStack(alignment: .top, spacing: 28) {
                column([.experience, .education, .skills]).frame(width: 156, alignment: .leading)
                column([.projects]).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if includesHeader {
                    header.padding(.bottom, 8)
                }
                column([.education, .skills])
            }
            .padding(.horizontal, 22).padding(.vertical, 38)
            .frame(width: 174, alignment: .leading)
            column([.projects, .experience])
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 34)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var summit: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header
            }
            VStack(alignment: .leading, spacing: 0) {
                section(.experience)
                section(.projects)
                HStack(alignment: .top, spacing: 32) {
                    column([.education]).frame(maxWidth: .infinity, alignment: .leading)
                    column([.skills]).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 38).padding(.top, includesHeader ? 6 : 24).padding(.bottom, 34)
        }
    }

    private var slate: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header.padding(.bottom, 20); rule
            }
            HStack(alignment: .top, spacing: 30) {
                column([.projects, .experience]).frame(maxWidth: .infinity, alignment: .leading)
                column([.skills, .education]).frame(width: 138, alignment: .leading)
            }
        }
    }

    private var heritage: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header.padding(.bottom, 18); rule
            }
            section(.experience)
            section(.projects)
            HStack(alignment: .top, spacing: 30) {
                column([.education]).frame(maxWidth: .infinity, alignment: .leading)
                column([.skills]).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var scholar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header.padding(.bottom, 18); rule
            }
            HStack(alignment: .top, spacing: 28) {
                column([.education, .experience, .skills]).frame(width: 156, alignment: .leading)
                column([.projects]).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var journal: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header.padding(.bottom, 18); rule
            }
            section(.projects)
            HStack(alignment: .top, spacing: 34) {
                column([.experience]).frame(maxWidth: .infinity, alignment: .leading)
                column([.education]).frame(maxWidth: .infinity, alignment: .leading)
            }
            section(.skills)
        }
    }

    private var gazette: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header
            }
            HStack(alignment: .top, spacing: 28) {
                column([.projects]).frame(maxWidth: .infinity, alignment: .leading)
                column([.experience, .education, .skills]).frame(width: 146, alignment: .leading)
            }
            .padding(.horizontal, 34).padding(.top, includesHeader ? 4 : 24).padding(.bottom, 34)
        }
    }

    private var prism: some View {
        VStack(alignment: .leading, spacing: 0) {
            if includesHeader {
                header.padding(.bottom, 12)
            }
            section(.skills)
            section(.projects)
            HStack(alignment: .top, spacing: 32) {
                column([.experience]).frame(maxWidth: .infinity, alignment: .leading)
                column([.education]).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var orbit: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if includesHeader {
                    header.padding(.bottom, 8)
                }
                column([.education, .skills])
            }
            .padding(.horizontal, 24).padding(.vertical, 36)
            .frame(width: 190, alignment: .leading)
            column([.projects, .experience])
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 34)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func column(_ kinds: [ResumeSection]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(kinds) { section($0) }
        }
    }

    private var rule: some View {
        Rectangle().fill(ResumePaperPalette.accent(for: template).opacity(0.6)).frame(height: 0.6)
    }
}
