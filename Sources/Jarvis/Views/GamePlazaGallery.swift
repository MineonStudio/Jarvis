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
    let gridZoom: HistoryGridZoomLevel
    let onStartMahjong: () -> Void
    @State private var selection = GallerySelection<Game.ID>()

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
        GeometryReader { viewport in
            ScrollView {
                FixedRatioGallery(
                    items: visibleGames, availableWidth: viewport.size.width,
                    targetWidth: gridZoom.cardWidth,
                    card: card
                )
                .padding(.bottom, HistoryGridMetrics.historyPanelInset)
                .galleryBackground(minHeight: viewport.size.height) { selection.clear() }
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: visibleGames.map(\.id)) { _, ids in selection.retain(ids.contains) }
    }

    private func card(_ game: Game, _ size: CGSize) -> some View {
        let isSelected = selection.selectedID == game.id
        return GalleryCard(
            size: size, isSelected: isSelected, enablesHoverZoom: gridZoom.enablesHoverZoom,
            onClick: { count in
                GallerySelection.handleClick(count, on: game.id, selection: $selection) { start(game) }
            },
            preview: { GamePosterArtwork() },
            leading: { Label(game.category.rawValue, systemImage: "gamecontroller") },
            trailing: { Text(game.title) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(game.title)
        .accessibilityHint("点击切换选中，双击开始游戏")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection.toggle(game.id) }
        .accessibilityAction(named: "开始游戏") { start(game) }
        .contextMenu {
            Button("开始游戏", systemImage: "play.fill") { start(game) }
        }
    }

    private func start(_ game: Game) {
        switch game {
        case .mahjong: onStartMahjong()
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
                    .scaledToFit()
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
