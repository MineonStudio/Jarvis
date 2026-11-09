import SwiftUI

struct ResumePageProject: View {
    let project: ResumeProject
    let template: ResumeTemplate
    let index: Int
    let selectedProjectID: UUID?
    let selectedBulletIndex: Int?
    let onSelectProject: (UUID) -> Void
    let onSelectBullet: (UUID, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            projectHeader
            if !project.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(project.summary)
                    .font(.system(size: 10.5, design: template.bodyFontDesign))
                    .foregroundStyle(ResumePaperPalette.body)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(project.bullets.enumerated()), id: \.offset) { bulletIndex, bullet in
                if !bullet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    bulletButton(bullet, index: bulletIndex)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, template == .editorial ? 20 : 15)
    }

    @ViewBuilder
    private var projectHeader: some View {
        switch template {
        case .editorial:
            VStack(alignment: .leading, spacing: 7) {
                Text(String(format: "%02d", index) + " / SELECTED WORK")
                    .font(.system(size: 8, weight: .bold)).tracking(1)
                    .foregroundStyle(ResumePaperPalette.vermilion)
                title
                period
            }
        case .creative:
            HStack(alignment: .top, spacing: 10) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(ResumePaperPalette.cobalt)
                VStack(alignment: .leading, spacing: 5) { title; period }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .business:
            VStack(alignment: .leading, spacing: 6) { period; title }
        case .mono, .grid, .scholar, .gazette:
            VStack(alignment: .leading, spacing: 5) { period; title }
        case .journal:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", index))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ResumePaperPalette.coral)
                title
                Spacer(minLength: 4)
                period
            }
        case .prism:
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(String(format: "%02d", index)).font(.system(size: 19, weight: .light))
                    .foregroundStyle(ResumePaperPalette.coral)
                title
                Spacer(minLength: 4)
                period
            }
        case .orbit:
            HStack(alignment: .top, spacing: 9) {
                Text(String(format: "%02d", index)).font(.system(size: 19, weight: .light))
                    .foregroundStyle(ResumePaperPalette.accent(for: template))
                VStack(alignment: .leading, spacing: 5) { title; period }
            }
        case .minimal, .classic, .summit, .slate, .heritage:
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                title
                Spacer(minLength: 4)
                period
            }
        }
    }

    private func bulletButton(_ bullet: String, index: Int) -> some View {
        Button { onSelectBullet(project.id, index) } label: {
            HStack(alignment: .top, spacing: 7) {
                Text("•").foregroundStyle(ResumePaperPalette.accent(for: template))
                Text(bullet).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 10.5, design: template.bodyFontDesign))
            .foregroundStyle(ResumePaperPalette.body)
            .lineSpacing(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
            .background(
                project.id == selectedProjectID && index == selectedBulletIndex
                    ? ResumePaperPalette.accent(for: template).opacity(0.10) : .clear
            )
        }
        .buttonStyle(.plain)
    }

    private var title: some View {
        Button { onSelectProject(project.id) } label: {
            Text(project.name)
                .font(.system(size: titleSize, weight: template == .editorial ? .regular : .semibold, design: template.bodyFontDesign))
                .foregroundStyle(template.category == .creative ? ResumePaperPalette.accent(for: template) : ResumePaperPalette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
    }

    private var period: some View {
        Text(project.period)
            .font(.system(size: 9, design: template.bodyFontDesign))
            .foregroundStyle(ResumePaperPalette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var titleSize: CGFloat {
        switch template {
        case .minimal: 12
        case .business: 14
        case .classic: 13
        case .editorial: 21
        case .creative: 16
        case .mono, .grid: 12
        case .summit, .slate, .heritage, .scholar, .orbit: 14
        case .journal: 18
        case .gazette: 16
        case .prism: 18
        }
    }
}
