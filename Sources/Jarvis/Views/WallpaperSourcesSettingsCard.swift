import SwiftUI

struct WallpaperSourcesSettingsCard: View {
    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
                SettingsCardHeader(title: "Wallhaven", systemImage: "photo.on.rectangle.angled")
                WallhavenAPIKeySettingsCard()
            }
        }
    }
}
