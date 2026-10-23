import SceneKit

/// Stable resting footprints prevent the moving model from toggling its own hover state.
/// A fast sweep often leaves a tile before the next frame, so that visit finishes its pop
/// instead of reversing from the rest position. Tiles skipped between pointer events pop too.
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
    private let reduceMotionOverride: Bool?
    private var lastPoint: CGPoint?
    private static let hoverKey = "hand.hover"
    private static let riseDuration: TimeInterval = 0.2
    private static let fallDuration: TimeInterval = 0.2
    /// Starts on the first frame, then keeps moving through the rest of the duration.
    private static let easeOut: (Float) -> Float = { time in
        let remaining = 1 - time
        return 1 - remaining * remaining
    }

    init(reduceMotion: Bool? = nil) {
        reduceMotionOverride = reduceMotion
    }

    var isAnimating: Bool {
        tiles.contains { $0.node.action(forKey: Self.hoverKey) != nil }
    }

    func replaceTiles(_ tiles: [Tile]) {
        updatePointer(nil, animated: false)
        for tile in self.tiles {
            tile.node.removeAction(forKey: Self.hoverKey)
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            tile.node.simdPosition = tile.rest
            SCNTransaction.commit()
        }
        self.tiles = tiles
        lastPoint = nil
    }

    func tile(at point: CGPoint) -> Tile? {
        index(at: point).map { tiles[$0] }
    }

    func updatePointer(_ point: CGPoint?, animated: Bool = true) {
        let next = point.flatMap { index(at: $0) }
        let passed = animated ? passedTiles(from: lastPoint, to: point, holding: next) : []
        if next == hoveredIndex, passed.isEmpty {
            if !animated {
                // Also settle a return animation when a window loses focus or a hand is rebuilt.
                for (index, tile) in tiles.enumerated() {
                    move(tile, raised: index == next, animated: false)
                }
            }
            lastPoint = point
            return
        }
        if let hoveredIndex, hoveredIndex != next {
            leave(tiles[hoveredIndex], animated: animated)
        }
        for index in passed where tiles.indices.contains(index) {
            if animated, !prefersReducedMotion {
                flick(tiles[index])
            } else {
                move(tiles[index], raised: false, animated: false)
            }
        }
        hoveredIndex = next
        if let next {
            move(tiles[next], raised: true, animated: animated)
        }
        if animated {
            onAnimation?()
        }
        lastPoint = point
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

    private var prefersReducedMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var hoverTravel: Float {
        MahjongHandLayout.hoverTravel(tileHeight: MahjongHandLayout.tileHeight)
    }

    /// Tiles whose resting slots the pointer crossed, excluding the tile it is holding now.
    private func passedTiles(from start: CGPoint?, to end: CGPoint?, holding: Int?) -> [Int] {
        guard let start, let end else { return [] }
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) > 0.0001 else { return [] }
        var hits: [(index: Int, time: CGFloat)] = []
        for index in tiles.indices where index != holding && index != hoveredIndex {
            if let time = entryTime(footprint(tiles[index]), from: start, dx: dx, dy: dy) {
                hits.append((index, time))
            }
        }
        return hits.sorted { $0.time < $1.time }.map(\.index)
    }

    private func entryTime(_ rect: CGRect, from start: CGPoint, dx: CGFloat, dy: CGFloat) -> CGFloat? {
        var tMin: CGFloat = 0
        var tMax: CGFloat = 1
        func clip(_ p: CGFloat, _ q: CGFloat) -> Bool {
            if abs(p) < 0.000_000_1 {
                return q >= 0
            }
            let ratio = q / p
            if p < 0 {
                if ratio > tMax {
                    return false
                }
                if ratio > tMin {
                    tMin = ratio
                }
            } else {
                if ratio < tMin {
                    return false
                }
                if ratio < tMax {
                    tMax = ratio
                }
            }
            return true
        }
        guard clip(-dx, start.x - rect.minX),
              clip(dx, rect.maxX - start.x),
              clip(-dy, start.y - rect.minY),
              clip(dy, rect.maxY - start.y),
              tMin <= tMax else { return nil }
        return tMin
    }

    private func visiblePosition(_ tile: Tile) -> SIMD3<Float> {
        tile.node.action(forKey: Self.hoverKey) == nil ? tile.node.simdPosition : tile.node.presentation.simdPosition
    }

    private func leave(_ tile: Tile, animated: Bool) {
        let risen = tile.rest.z - visiblePosition(tile).z
        if animated, !prefersReducedMotion, risen < hoverTravel * 0.8 {
            flick(tile)
        } else {
            move(tile, raised: false, animated: animated)
        }
    }

    /// Finish the lift, then return. Used when the pointer has already moved on.
    private func flick(_ tile: Tile) {
        let raised = tile.rest - SIMD3(0, 0, hoverTravel)
        let visible = visiblePosition(tile)
        tile.node.removeAction(forKey: Self.hoverKey)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        tile.node.simdPosition = visible
        SCNTransaction.commit()
        let risen = max(0, tile.rest.z - visible.z)
        let remaining = max(0, hoverTravel - risen)
        var steps: [SCNAction] = []
        if remaining > 0.001 {
            let up = SCNAction.move(to: SCNVector3(raised), duration: Self.riseDuration * Double(remaining / hoverTravel))
            up.timingFunction = Self.easeOut
            steps.append(up)
        }
        let down = SCNAction.move(to: SCNVector3(tile.rest), duration: Self.fallDuration)
        down.timingFunction = Self.easeOut
        steps.append(down)
        tile.node.runAction(.sequence(steps), forKey: Self.hoverKey)
    }

    private func move(_ tile: Tile, raised: Bool, animated: Bool) {
        let target = tile.rest - SIMD3(0, 0, raised ? hoverTravel : 0)
        let visible = visiblePosition(tile)
        tile.node.removeAction(forKey: Self.hoverKey)
        let distance = abs(target.z - visible.z)
        let animates = animated && !prefersReducedMotion && distance > 0.001
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        tile.node.simdPosition = animates ? visible : target
        SCNTransaction.commit()
        guard animates else { return }
        // Reverse from the current rendered position, so a settled hover does not snap.
        let duration = (raised ? Self.riseDuration : Self.fallDuration) * Double(distance / hoverTravel)
        let action = SCNAction.move(to: SCNVector3(target), duration: max(duration, 0.01))
        action.timingFunction = Self.easeOut
        tile.node.runAction(action, forKey: Self.hoverKey)
    }
}
