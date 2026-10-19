import SceneKit

/// Stable resting footprints prevent the moving model from toggling its own hover state.
@MainActor
final class MahjongSceneHandInteraction {
    struct Tile {
        let node: SCNNode
        let value: MahjongTile
        let drawn: Bool
        let rest: SIMD3<Float>

        init(node: SCNNode, value: MahjongTile, drawn: Bool) {
            self.node = node
            self.value = value
            self.drawn = drawn
            rest = node.simdPosition
        }
    }

    private(set) var tiles: [Tile] = []
    private(set) var hoveredIndex: Int?
    var onAnimation: (() -> Void)?

    var isAnimating: Bool {
        tiles.contains { $0.node.action(forKey: "hand.hover") != nil }
    }

    func replaceTiles(_ tiles: [Tile]) {
        updatePointer(nil, animated: false)
        self.tiles = tiles
    }

    func tile(at point: CGPoint) -> Tile? {
        index(at: point).map { tiles[$0] }
    }

    func updatePointer(_ point: CGPoint?, animated: Bool = true) {
        let next = point.flatMap { index(at: $0) }
        guard next != hoveredIndex else {
            if !animated {
                // Also settle a return animation when a window loses focus or a hand is rebuilt.
                for (index, tile) in tiles.enumerated() {
                    move(tile, raised: index == next, animated: false)
                }
            }
            return
        }
        if let hoveredIndex {
            move(tiles[hoveredIndex], raised: false, animated: animated)
        }
        hoveredIndex = next
        if let next {
            move(tiles[next], raised: true, animated: animated)
        }
        if animated {
            onAnimation?()
        }
    }

    private func index(at point: CGPoint) -> Int? {
        // Prefer each tile's original slot when rapidly sweeping across the hand.
        if let index = tiles.firstIndex(where: { footprint($0).contains(point) }) {
            return index
        }
        if let hoveredIndex {
            let rect = footprint(tiles[hoveredIndex])
            let travel = CGFloat(MahjongHandLayout.hoverTravel(tileHeight: MahjongHandLayout.tileHeight))
            if rect.union(rect.offsetBy(dx: 0, dy: -travel)).contains(point) {
                return hoveredIndex
            }
        }
        return nil
    }

    private func footprint(_ tile: Tile) -> CGRect {
        CGRect(
            x: CGFloat(tile.rest.x - MahjongHandLayout.tileWidth / 2),
            y: CGFloat(tile.rest.z - MahjongHandLayout.tileHeight / 2),
            width: CGFloat(MahjongHandLayout.tileWidth),
            height: CGFloat(MahjongHandLayout.tileHeight)
        )
    }

    private func move(_ tile: Tile, raised: Bool, animated: Bool) {
        let travel = raised ? MahjongHandLayout.hoverTravel(tileHeight: MahjongHandLayout.tileHeight) : 0
        let target = tile.rest - SIMD3(0, 0, travel)
        let animates = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let visible = tile.node.action(forKey: "hand.hover") == nil
            ? tile.node.simdPosition : tile.node.presentation.simdPosition
        tile.node.removeAction(forKey: "hand.hover")
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        tile.node.simdPosition = animates ? visible : target
        SCNTransaction.commit()
        guard animates else { return }
        // Reverse from the current rendered position, so fast entry/exit cannot snap.
        let action = SCNAction.move(to: SCNVector3(target), duration: 0.2)
        // Entry has no slow ease-in: the very next frame should visibly move.
        action.timingMode = raised ? .easeOut : .easeInEaseOut
        tile.node.runAction(action, forKey: "hand.hover")
    }
}
