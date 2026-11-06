import SwiftUI

/// The file-transfer filter and meeting content switch share the same controls.
public struct JarvisCapsuleFilterBar<Item: Identifiable & Hashable>: View {
    private let items: [Item]
    @Binding private var selection: Item
    private let title: (Item) -> String
    private let accessibilityTitle: String
    @State private var hovered: Item?

    public init(items: [Item], selection: Binding<Item>, accessibilityTitle: String, title: @escaping (Item) -> String) {
        self.items = items
        _selection = selection
        self.accessibilityTitle = accessibilityTitle
        self.title = title
    }

    public var body: some View {
        HStack(spacing: JarvisSpacing.hairline) {
            ForEach(items) { item in
                let isSelected = selection == item
                Button { selection = item } label: {
                    Text(title(item))
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, JarvisSpacing.controlGap)
                        .frame(height: 26)
                        .background {
                            Capsule().fill(isSelected ? Color.accentColor : (hovered == item ? Color.primary.opacity(0.08) : .clear))
                        }
                        .overlay {
                            Capsule().strokeBorder(Color.accentColor.opacity(isSelected ? 0.42 : 0), lineWidth: 0.75)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in hovered = hovering ? item : (hovered == item ? nil : hovered) }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(JarvisSpacing.textGap)
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .modifier(JarvisButtonShadowModifier())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }
}
