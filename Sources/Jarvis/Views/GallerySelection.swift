import SwiftUI

struct GallerySelection<ID: Equatable> {
    private(set) var selectedID: ID?
    private var selectionBeforeClick: (itemID: ID, selectedID: ID?)?

    mutating func toggle(_ id: ID) {
        selectionBeforeClick = nil
        selectedID = selectedID == id ? nil : id
    }

    mutating func clear() {
        selectionBeforeClick = nil
        selectedID = nil
    }

    mutating func retain(_ includes: (ID) -> Bool) {
        if let selectedID, !includes(selectedID) {
            clear()
        } else if let previous = selectionBeforeClick?.selectedID, !includes(previous) {
            selectionBeforeClick?.selectedID = nil
        }
    }

    static func handleClick(_ count: Int, on id: ID, selection: Binding<Self>, open: () -> Void) {
        var updated = selection.wrappedValue
        switch count {
        case 1:
            let previousID = updated.selectedID
            updated.toggle(id)
            updated.selectionBeforeClick = (id, previousID)
            selection.wrappedValue = updated
        case 2:
            if let selectionBeforeClick = updated.selectionBeforeClick, selectionBeforeClick.itemID == id {
                updated.selectedID = selectionBeforeClick.selectedID
            }
            updated.selectionBeforeClick = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            selection.transaction(transaction).wrappedValue = updated
            open()
        default: break
        }
    }
}

extension View {
    func galleryBackground(minHeight: CGFloat, onClearSelection: @escaping () -> Void) -> some View {
        frame(minHeight: minHeight, alignment: .topLeading)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClearSelection)
                    .accessibilityHidden(true)
            }
    }
}
