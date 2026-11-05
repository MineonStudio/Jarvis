import SwiftUI

struct WallpaperSourcesSettingsCard: View {
    var body: some View {
        SettingsSectionCard("Wallhaven") {
            WallhavenAPIKeySettingsCard()
        }
    }
}
