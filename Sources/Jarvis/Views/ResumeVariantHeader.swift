import SwiftUI

struct ResumeVariantHeader: View {
    let document: ResumeDocument
    let template: ResumeTemplate
    let showsPlaceholders: Bool

    private var reversed: Bool {
        [.summit, .gazette, .orbit].contains(template)
    }

    private var ink: Color {
        reversed ? .white : ResumePaperPalette.ink
    }

    private var muted: Color {
        reversed ? .white.opacity(0.78) : ResumePaperPalette.muted
    }

    private var accent: Color {
        ResumePaperPalette.accent(for: template)
    }

    var body: some View {
        switch template {
        case .mono:
            VStack(spacing: 12) {
                eyebrow("P E R S O N A L   R E S U M E")
                name(38, weight: .light)
                role
                contactRow
            }
            .frame(maxWidth: .infinity)
        case .grid:
            VStack(alignment: .leading, spacing: 16) {
                Rectangle().fill(.black).frame(width: 28, height: 4)
                eyebrow("PROFILE")
                name(30, weight: .medium)
                role
                contactColumn.padding(.top, 10)
            }
        case .summit:
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    eyebrow("PROFESSIONAL / 职业履历")
                    name(38, weight: .semibold)
                    role
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                contactColumn.frame(width: 176, alignment: .leading)
            }
            .padding(34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ResumePaperPalette.navy)
            .overlay(alignment: .bottom) { ResumePaperPalette.gold.frame(height: 5) }
        case .slate:
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    eyebrow("CAREER / 简历")
                    name(40, weight: .semibold)
                    role
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                contactColumn.frame(width: 138, alignment: .leading)
            }
        case .heritage:
            VStack(spacing: 13) {
                eyebrow("R É S U M É")
                name(34, weight: .regular)
                    .tracking(5)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 10)
                    .overlay { Rectangle().stroke(accent, lineWidth: 0.7) }
                role
                contactRow
            }
            .frame(maxWidth: .infinity)
        case .scholar:
            VStack(alignment: .leading, spacing: 12) {
                eyebrow("履历 / CURRICULUM VITAE")
                name(40, weight: .regular)
                role
                contactRow
            }
        case .journal:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    eyebrow("专栏 / CAREER STORIES")
                    Spacer()
                    Text("PROFILE").font(.system(size: 8, weight: .bold)).tracking(2)
                }
                HStack(alignment: .firstTextBaseline) {
                    name(52, weight: .regular)
                    Spacer(minLength: 12)
                    role
                }
                contactRow
            }
        case .gazette:
            VStack(alignment: .leading, spacing: 14) {
                eyebrow("THE CAREER REVIEW / 职业档案")
                HStack(alignment: .firstTextBaseline) {
                    name(44, weight: .black)
                    Spacer(minLength: 12)
                    role
                }
                contactRow
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ResumePaperPalette.ink)
            .overlay(alignment: .bottom) { ResumePaperPalette.amber.frame(height: 7) }
        case .prism:
            VStack(alignment: .leading, spacing: 12) {
                eyebrow("HELLO / 你好")
                name(58, weight: .heavy).padding(.trailing, 110)
                role
                contactRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .topTrailing) {
                Rectangle()
                    .stroke(accent, lineWidth: 9)
                    .frame(width: 84, height: 84)
                    .rotationEffect(.degrees(35))
                    .offset(x: 26, y: -18)
            }
            .clipped()
        case .orbit:
            VStack(alignment: .leading, spacing: 16) {
                eyebrow("CREATIVE / CV")
                name(28, weight: .bold)
                    .frame(width: 120, height: 120)
                    .overlay { Circle().stroke(ResumePaperPalette.lime, lineWidth: 2) }
                role
                contactColumn.padding(.top, 8)
            }
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func name(_ size: CGFloat, weight: Font.Weight) -> some View {
        if let text = value(document.basicInfo.name, placeholder: "姓名") {
            Text(text)
                .font(.system(size: size, weight: weight, design: template.bodyFontDesign))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var role: some View {
        if let text = value(document.basicInfo.headline, placeholder: "职位标题") {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: template.bodyFontDesign))
                .foregroundStyle(reversed ? (template == .orbit ? ResumePaperPalette.lime : .white) : accent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: template.bodyFontDesign))
            .tracking(1)
            .foregroundStyle(reversed ? .white.opacity(0.7) : accent)
    }

    @ViewBuilder
    private var contactRow: some View {
        if template == .mono || template == .heritage {
            Text(contact.joined(separator: "  ·  "))
                .font(.system(size: 9, design: template.bodyFontDesign))
                .foregroundStyle(muted)
                .multilineTextAlignment(.center)
        } else {
            ResumeTextFlowLayout(spacing: 12, lineSpacing: 6) {
                ForEach(Array(contact.enumerated()), id: \.offset) { _, text in
                    Text(text).font(.system(size: 9)).foregroundStyle(muted)
                }
            }
        }
    }

    private var contactColumn: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(contact.enumerated()), id: \.offset) { _, text in
                Text(text)
                    .font(.system(size: 9, design: template.bodyFontDesign))
                    .foregroundStyle(muted)
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
