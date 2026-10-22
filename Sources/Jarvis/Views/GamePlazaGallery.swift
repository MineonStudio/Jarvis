import AppKit
import SwiftUI

enum GamePlazaCategory: String, CaseIterable, Identifiable {
    case all = "全部"
    case casual = "休闲"

    var id: String {
        rawValue
    }
}

struct GamePlazaGallery: View {
    let category: GamePlazaCategory
    let onStartMahjong: () -> Void

    private enum Game: String, CaseIterable, Identifiable {
        case mahjong

        var id: String {
            rawValue
        }

        var category: GamePlazaCategory {
            .casual
        }

        var title: String {
            "欢乐麻将"
        }
    }

    private var visibleGames: [Game] {
        Game.allCases.filter { category == .all || $0.category == category }
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 18)],
            alignment: .leading,
            spacing: 18
        ) {
            ForEach(visibleGames) { game in
                GamePosterCard(title: game.title) {
                    switch game {
                    case .mahjong: onStartMahjong()
                    }
                }
            }
        }
    }
}

private struct GamePosterCard: View {
    let title: String
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onStart) {
                GamePosterArtwork()
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始游戏，\(title)")

            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Button("开始游戏", action: onStart)
                    .buttonStyle(JarvisPrimaryButtonStyle())
                    .fixedSize()
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct GamePosterArtwork: View {
    private static let poster: NSImage? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("GameArtwork/mahjong-poster.png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        return image
    }()

    var body: some View {
        GeometryReader { geometry in
            if let poster = Self.poster {
                Image(nsImage: poster)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                fallback
            }
        }
        .accessibilityLabel("欢乐麻将游戏海报：暖灯茶室与麻将牌")
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.17, blue: 0.16), Color(red: 0.12, green: 0.38, blue: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: -8) {
                MahjongTileView(tile: .suited(.bamboo, 3)).rotationEffect(.degrees(-9))
                MahjongTileView(tile: .honor(4)).rotationEffect(.degrees(4))
                MahjongTileView(tile: .suited(.dots, 5)).rotationEffect(.degrees(12))
            }
        }
    }
}
