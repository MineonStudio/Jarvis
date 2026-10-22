import SwiftUI

struct MahjongLANRulesetPicker: View {
    @Binding var selection: MahjongRuleset?

    var body: some View {
        HStack(spacing: 12) {
            ForEach(MahjongRuleset.allCases) { ruleset in
                let selected = selection == ruleset
                Button {
                    selection = ruleset
                } label: {
                    HStack(spacing: 8) {
                        Text(ruleset.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? .white : .white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(MahjongGameButtonStyle(kind: selected ? .primary : .secondary, borderShape: .roundedRectangle(radius: 14)))
                .accessibilityLabel(ruleset.title)
                .accessibilityValue(selected ? "已选择" : "未选择")
                .help(ruleset.title)
            }
        }
    }
}

struct MahjongRoomCodeInput: View {
    @Binding var code: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField("输入六位房间码", text: $code)
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(MahjongVisualTheme.ivory)
            .tint(MahjongVisualTheme.accent)
            .focused($focused)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 320)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(focused ? 0.55 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("六位房间码")
            .onChange(of: code) { _, value in
                code = String(value.filter(\.isNumber).prefix(6))
            }
    }
}
