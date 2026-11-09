import SwiftUI

extension ResumeTemplate {
    var bodyFontDesign: Font.Design {
        category == .classic || category == .editorial ? .serif : .default
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .minimal: 25
        case .business: 25
        case .classic: 19
        case .editorial: 24
        case .creative: 22
        default: 18
        }
    }

    var pageHorizontalPadding: CGFloat {
        switch self {
        case .minimal: 48
        case .business, .creative: 0
        case .classic: 52
        case .editorial: 38
        case .grid, .summit, .orbit, .gazette: 0
        default: 38
        }
    }

    var pageVerticalPadding: CGFloat {
        switch self {
        case .minimal: 46
        case .business, .creative: 0
        case .classic: 44
        case .editorial: 30
        case .grid, .summit, .orbit, .gazette: 0
        default: 34
        }
    }

    var paperColor: Color {
        switch self {
        case .classic: Color(red: 0.985, green: 0.970, blue: 0.936)
        case .editorial: Color(red: 0.976, green: 0.968, blue: 0.946)
        case .heritage: Color(red: 0.98, green: 0.96, blue: 0.92)
        case .scholar: Color(red: 0.96, green: 0.97, blue: 0.94)
        case .journal: Color(red: 0.99, green: 0.98, blue: 0.96)
        case .prism: Color(red: 1, green: 0.94, blue: 0.88)
        case .orbit: Color(red: 0.96, green: 0.95, blue: 1)
        default: .white
        }
    }
}

enum ResumePaperPalette {
    static let ink = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let body = Color(red: 0.23, green: 0.25, blue: 0.28)
    static let muted = Color(red: 0.43, green: 0.45, blue: 0.48)
    static let softLine = Color(red: 0.83, green: 0.84, blue: 0.85)
    static let navy = Color(red: 0.08, green: 0.17, blue: 0.27)
    static let sky = Color(red: 0.72, green: 0.84, blue: 0.90)
    static let burgundy = Color(red: 0.42, green: 0.22, blue: 0.19)
    static let gold = Color(red: 0.65, green: 0.53, blue: 0.32)
    static let vermilion = Color(red: 0.73, green: 0.20, blue: 0.14)
    static let cobalt = Color(red: 0.20, green: 0.22, blue: 0.82)
    static let lime = Color(red: 0.86, green: 0.95, blue: 0.40)

    static let forest = Color(red: 0.13, green: 0.34, blue: 0.30)
    static let plum = Color(red: 0.30, green: 0.14, blue: 0.44)
    static let coral = Color(red: 0.85, green: 0.28, blue: 0.17)
    static let amber = Color(red: 0.96, green: 0.64, blue: 0.28)

    static func accent(for template: ResumeTemplate) -> Color {
        switch template {
        case .minimal, .mono, .grid, .gazette: ink
        case .business, .summit: navy
        case .classic, .heritage: burgundy
        case .editorial: vermilion
        case .creative: cobalt
        case .slate, .scholar: forest
        case .journal, .prism: coral
        case .orbit: plum
        }
    }
}

struct ResumePaperDecoration: View {
    let template: ResumeTemplate

    var body: some View {
        ZStack(alignment: .topLeading) {
            template.paperColor
            switch template {
            case .business:
                ResumePaperPalette.navy.frame(width: 196)
            case .classic:
                Rectangle().strokeBorder(ResumePaperPalette.gold.opacity(0.65), lineWidth: 0.7).padding(18)
                Rectangle().strokeBorder(ResumePaperPalette.gold.opacity(0.28), lineWidth: 0.5).padding(22)
            case .editorial:
                ResumePaperPalette.vermilion.frame(height: 8)
            case .creative:
                VStack { Spacer(); ResumePaperPalette.cobalt.frame(height: 10) }
            case .minimal: EmptyView()
            default: ResumeVariantDecoration(template: template)
            }
        }
        .allowsHitTesting(false)
    }
}
