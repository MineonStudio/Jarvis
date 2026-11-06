import AppKit
import SwiftUI

/// Assets are bundled with the app and decoded at the card's display size.
struct HomeTipIllustration: View {
    let theme: String
    var height: CGFloat = 96
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .accessibilityHidden(true)
        .task(id: theme) {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("HomeTips/\(theme).png") else { return }
            image = await JarvisThumbnailCache.loadAsync(fileURL: url, maxPixelSize: 600, token: "home-tip-\(theme)")
        }
    }
}
