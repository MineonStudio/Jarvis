import SwiftUI

struct ResumeVariantDecoration: View {
    let template: ResumeTemplate

    var body: some View {
        switch template {
        case .grid:
            HStack(spacing: 0) {
                Color.clear.frame(width: 174)
                Rectangle().fill(ResumePaperPalette.ink.opacity(0.25)).frame(width: 0.6)
                Spacer()
            }
        case .summit:
            VStack { Spacer(); ResumePaperPalette.navy.frame(height: 12) }
        case .slate:
            HStack { Spacer(); Color(red: 0.90, green: 0.94, blue: 0.92).frame(width: 182) }
        case .heritage:
            Rectangle().strokeBorder(ResumePaperPalette.burgundy.opacity(0.5), lineWidth: 1).padding(20)
        case .scholar:
            HStack { ResumePaperPalette.forest.frame(width: 7); Spacer() }
        case .journal:
            VStack { Spacer(); ResumePaperPalette.coral.frame(height: 8) }
        case .gazette:
            VStack { Spacer(); ResumePaperPalette.ink.frame(height: 12) }
        case .prism:
            HStack { ResumePaperPalette.coral.frame(width: 10); Spacer() }
        case .orbit:
            HStack(spacing: 0) {
                ResumePaperPalette.plum.frame(width: 190)
                Spacer()
            }
            .overlay(alignment: .bottomTrailing) {
                Circle().stroke(ResumePaperPalette.plum.opacity(0.08), lineWidth: 16)
                    .frame(width: 150, height: 150).offset(x: 44, y: 44)
            }
            .clipped()
        default: EmptyView()
        }
    }
}
