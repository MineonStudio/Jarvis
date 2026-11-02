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
            columns: [GridItem(.adaptive(minimum: 250, maximum: 350), spacing: JarvisSpacing.gridGap)],
            alignment: .leading,
            spacing: JarvisSpacing.gridGap
        ) {
            ForEach(visibleGames) { game in
                GamePosterCard(
                    title: game.title,
                    onStart: {
                        switch game {
                        case .mahjong: onStartMahjong()
                        }
                    }
                )
            }
        }
    }
}

private struct GamePosterCard: View {
    let title: String
    let onStart: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HistoryCardChrome(preview: cover, isSelected: false)
            .overlay(alignment: .bottomTrailing) { startActionOverlay }
            .clipShape(RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            ))
            .contentShape(RoundedRectangle(
                cornerRadius: HistoryGridMetrics.clipboardCornerRadius,
                style: .continuous
            ))
            .onTapGesture(count: 2, perform: onStart)
            .onHover { hovering in
                guard hovering != isHovered else { return }
                withAnimation(JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion)) {
                    isHovered = hovering
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
            .accessibilityHint("双击开始游戏，也可使用右下角悬浮的开始游戏按钮")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "开始游戏", onStart)
            .contextMenu {
                Button(action: onStart) {
                    Label("开始游戏", systemImage: "play.fill")
                }
            }
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(HistoryGridLayout.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { GamePosterArtwork() }
            .clipped()
    }

    @ViewBuilder
    private var startActionOverlay: some View {
        if isHovered {
            Button(action: onStart) {
                Text("开始游戏")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(JarvisCardActionPillButtonStyle())
            .accessibilityLabel("开始游戏，\(title)")
            .padding(JarvisSpacing.controlGap)
            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
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
