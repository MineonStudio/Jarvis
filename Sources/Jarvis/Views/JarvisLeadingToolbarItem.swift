import SwiftUI

/// Match the AI provider picker's 36pt surface and navigation placement.
/// Native toolbar backgrounds add their own leading margin; owning this
/// surface keeps text buttons aligned with the app's grouped pickers.
struct JarvisLeadingToolbarItem<Content: View>: ToolbarContent {
    let id: String
    var alignment: HistoryToolbarAlignment?
    @ViewBuilder let content: Content

    var body: some ToolbarContent {
        JarvisLeadingToolbarSurface(id: id) {
            content
                .frame(height: JarvisToolbarMetrics.controlSize)
                .padding(JarvisSegmentedMetrics.padding(
                    containerHeight: JarvisToolbarMetrics.nativeSurfaceHeight,
                    itemHeight: JarvisToolbarMetrics.controlSize
                ))
                .jarvisGlass(in: Capsule(), interactive: false)
                .background {
                    if let alignment {
                        HistoryToolbarFrameProbe(alignment: alignment, edge: .leading)
                    }
                }
        }
    }
}

/// Keep the same toolbar height on modules without toolbar actions.
struct JarvisToolbarPlaceholder: ToolbarContent {
    let id: String

    var body: some ToolbarContent {
        JarvisLeadingToolbarSurface(id: id) {
            Color.clear
                .frame(width: 1, height: JarvisToolbarMetrics.nativeSurfaceHeight)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

/// All module-leading toolbar content starts on the same 8pt line as the body.
/// Apply the adjustment outside the glass so the capsule's own insets stay equal.
struct JarvisLeadingToolbarSurface<Content: View>: ToolbarContent {
    let id: String
    @ViewBuilder let content: Content

    var body: some ToolbarContent {
        JarvisToolbarSurface(id: id, placement: .navigation) {
            content.padding(.leading, JarvisToolbarMetrics.leadingAdjustment)
        }
    }
}
