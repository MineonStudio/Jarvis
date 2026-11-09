import SwiftUI

struct ResumePageHeader: View {
    let document: ResumeDocument
    let template: ResumeTemplate
    var showsPlaceholders = false

    var body: some View {
        switch template {
        case .mono, .grid, .summit, .slate, .heritage, .scholar, .journal, .gazette, .prism, .orbit:
            ResumeVariantHeader(document: document, template: template, showsPlaceholders: showsPlaceholders)
        case .minimal:
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    name(size: 44, weight: .light)
                    Spacer(minLength: 4)
                    headline
                }
                contactRow
            }
            .padding(.bottom, 12)
        case .business:
            VStack(alignment: .leading, spacing: 14) {
                eyebrow("RESUME / 个人履历")
                name(size: 32, weight: .semibold)
                headline
                Rectangle().fill(ResumePaperPalette.sky.opacity(0.4)).frame(width: 32, height: 2)
                    .padding(.vertical, 8)
                contactColumn
            }
        case .classic:
            VStack(spacing: 12) {
                eyebrow("C U R R I C U L U M   V I T A E")
                name(size: 38, weight: .regular)
                    .tracking(4)
                headline.italic()
                Text(contact.joined(separator: "  ·  "))
                    .font(.system(size: 9.5, design: .serif))
                    .foregroundStyle(ResumePaperPalette.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        case .editorial:
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    eyebrow("人物志 / THE PROFESSIONAL PROFILE")
                    Spacer()
                    Text("RESUME").font(.system(size: 8, weight: .bold)).tracking(2)
                }
                .foregroundStyle(ResumePaperPalette.vermilion)
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        name(size: 52, weight: .black)
                        headline
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    contactColumn.frame(width: 170, alignment: .leading)
                }
            }
        case .creative:
            VStack(alignment: .leading, spacing: 14) {
                eyebrow("创意履历 / CREATIVE PROFILE")
                name(size: 46, weight: .heavy)
                    .padding(.trailing, 160)
                headline.padding(.trailing, 140)
                contactRow.padding(.top, 8)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                ZStack(alignment: .topTrailing) {
                    ResumePaperPalette.cobalt
                    Circle()
                        .stroke(ResumePaperPalette.lime, lineWidth: 18)
                        .frame(width: 136, height: 136)
                        .offset(x: 24, y: -28)
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        .frame(width: 180, height: 180)
                        .offset(x: 42, y: -46)
                    Rectangle()
                        .fill(ResumePaperPalette.lime)
                        .frame(width: 64, height: 14)
                        .rotationEffect(.degrees(-40))
                        .offset(x: -42, y: 118)
                }
            }
            .clipped()
        }
    }

    private var isReversed: Bool {
        template == .business || template == .creative
    }

    private var titleColor: Color {
        isReversed ? .white : ResumePaperPalette.ink
    }

    private var secondaryColor: Color {
        isReversed ? .white.opacity(0.80) : ResumePaperPalette.muted
    }

    @ViewBuilder
    private func name(size: CGFloat, weight: Font.Weight) -> some View {
        if let text = value(document.basicInfo.name, placeholder: "姓名") {
            Text(text)
                .font(.system(size: size, weight: weight, design: template.bodyFontDesign))
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var headline: some View {
        if let text = value(document.basicInfo.headline, placeholder: "职位标题") {
            Text(text)
                .font(.system(size: template == .creative ? 16 : 13, weight: .medium, design: template.bodyFontDesign))
                .foregroundStyle(template == .creative ? ResumePaperPalette.lime :
                    template == .business ? ResumePaperPalette.sky : ResumePaperPalette.accent(for: template))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func eyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 8, weight: .semibold, design: template.bodyFontDesign))
            .tracking(template == .classic ? 0 : 1.5)
            .foregroundStyle(isReversed ? secondaryColor : ResumePaperPalette.accent(for: template))
    }

    private var contactRow: some View {
        ResumeTextFlowLayout(spacing: 14, lineSpacing: 7) {
            ForEach(Array(contact.enumerated()), id: \.offset) { _, item in
                Text(item).font(.system(size: 9.5)).foregroundStyle(secondaryColor)
            }
        }
    }

    private var contactColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(contact.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.system(size: 9.5, design: template.bodyFontDesign))
                    .foregroundStyle(secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var contact: [String] {
        zip(
            [document.basicInfo.location, document.basicInfo.email, document.basicInfo.jobStatus, document.basicInfo.workYears],
            ["所在地", "联系方式", "岗位状态", "工作年限"]
        ).compactMap { value($0.0, placeholder: $0.1) }
    }

    private func value(_ text: String, placeholder: String) -> String? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (showsPlaceholders ? placeholder : nil) : text
    }
}
