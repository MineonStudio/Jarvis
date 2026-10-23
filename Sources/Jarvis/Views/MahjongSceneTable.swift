import SceneKit
import SwiftUI

/// Orthographic camera straight above the felt. North is the top of the window.
/// Shared base tile size; crowded rivers compact within their own regions.
/// The other three hands stand, so the camera sees their tops.
/// The local hand, melds, and discards lie face-up.
struct MahjongSceneTable: View {
    let game: MahjongGame
    @State private var tableSettings = MahjongTableSettings.shared

    var body: some View {
        MahjongSceneHost(model: MahjongSceneModel(game: game), tableStyle: tableSettings.style) { tile, drawn in
            if drawn {
                game.discardDrawnTile()
            } else {
                game.discard(tile)
            }
        }
    }
}

struct MahjongScenePiece: Equatable {
    var tile: MahjongTile?
    var faceUp: Bool
    var missing: Bool
}

struct MahjongSceneSeat: Equatable {
    var hand: [MahjongScenePiece]
    var melds: [[MahjongScenePiece]]
    var discards: [MahjongScenePiece]
}

@MainActor
struct MahjongSceneModel: Equatable {
    var seats: [MahjongSceneSeat]
    var canDiscard: Bool

    init(game: MahjongGame) {
        canDiscard = game.isHumanTurn
        seats = (0 ..< 4).map { view in
            let seat = (game.localSeat + view) % 4
            return MahjongSceneSeat(
                hand: Self.hand(seat: seat, game: game),
                melds: Self.melds(seat: seat, game: game),
                discards: Self.discards(seat: seat, game: game)
            )
        }
    }

    private static func hand(seat: Int, game: MahjongGame) -> [MahjongScenePiece] {
        let reveal = game.phase == .roundEnded
        let face = reveal || seat == game.visibleHandSeat
        let source: [MahjongTile] = if face, seat == game.visibleHandSeat, !reveal {
            game.visibleHand
        } else {
            game.hands.indices.contains(seat) ? game.hands[seat] : []
        }
        let separates = game.justDrew && seat == game.turn && source.count > 1
        let body = separates ? Array(source.dropLast()) : source
        var pieces = body.map { piece($0, face: face, seat: seat, game: game) }
        if separates, let drawn = source.last {
            pieces.append(MahjongScenePiece(tile: nil, faceUp: false, missing: false))
            pieces.append(piece(drawn, face: face, seat: seat, game: game))
        }
        return pieces
    }

    private static func melds(seat: Int, game: MahjongGame) -> [[MahjongScenePiece]] {
        guard game.melds.indices.contains(seat) else { return [] }
        return game.melds[seat].map { meld in
            let sorted = meld.tiles.sorted { $0.sortKey < $1.sortKey }
            let faced: [(MahjongTile, Bool)] = if meld.kind == .concealedKong, sorted.count == 4 {
                [(sorted[0], false), (sorted[1], true), (sorted[2], true), (sorted[3], false)]
            } else {
                sorted.map { ($0, true) }
            }
            return faced.map { tile, up in
                MahjongScenePiece(tile: tile, faceUp: up, missing: false)
            }
        }
    }

    private static func discards(seat: Int, game: MahjongGame) -> [MahjongScenePiece] {
        guard game.discards.indices.contains(seat) else { return [] }
        return game.discards[seat].map { MahjongScenePiece(tile: $0, faceUp: true, missing: false) }
    }

    private static func piece(_ tile: MahjongTile, face: Bool, seat: Int, game: MahjongGame) -> MahjongScenePiece {
        MahjongScenePiece(tile: tile, faceUp: face, missing: face && missing(tile, seat: seat, game: game))
    }

    private static func missing(_ tile: MahjongTile, seat: Int, game: MahjongGame) -> Bool {
        guard game.ruleset == .sichuan,
              game.missingSuits.indices.contains(seat),
              let suit = game.missingSuits[seat],
              case let .suited(tileSuit, _) = tile else { return false }
        return tileSuit == suit
    }
}

@MainActor
struct MahjongSceneHost: NSViewRepresentable {
    var model: MahjongSceneModel
    var tableStyle: MahjongTableStyle
    var onDiscard: (MahjongTile, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDiscard: onDiscard)
    }

    func makeNSView(context: Context) -> MahjongSceneInteractionView {
        let view = MahjongSceneInteractionView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = MahjongTableSettings.shared.style.color
        view.rendersContinuously = false
        let coordinator = context.coordinator
        coordinator.view = view
        view.onPointer = { [weak coordinator, weak view] point in
            coordinator?.handInteraction.updatePointer(point, animated: view?.window?.isKeyWindow == true && NSApp.isActive)
        }
        view.containsTile = { [weak coordinator] point in coordinator?.handInteraction.tile(at: point) != nil }
        view.onTileClick = { [weak coordinator] point in coordinator?.discard(at: point) }
        coordinator.sync(model)
        coordinator.applyTableStyle(tableStyle)
        return view
    }

    func updateNSView(_: MahjongSceneInteractionView, context: Context) {
        context.coordinator.onDiscard = onDiscard
        context.coordinator.sync(model)
        context.coordinator.applyTableStyle(tableStyle)
    }

    static func dismantleNSView(_ view: MahjongSceneInteractionView, coordinator _: Coordinator) {
        view.stopMonitoring()
    }

    @MainActor
    final class Coordinator: NSObject {
        let scene = SCNScene()
        let camera = SCNNode()
        let tileRoot = SCNNode()
        private let feltNode = SCNNode()
        private var tableStyle: MahjongTableStyle = .brocade
        private let handRoots = (0 ..< 4).map { _ in SCNNode() }
        private let meldRoots = (0 ..< 4).map { _ in SCNNode() }
        private let discardRoots = (0 ..< 4).map { _ in SCNNode() }
        private var applied: MahjongSceneModel?
        private let textures = MahjongTileTextures()
        let handInteraction = MahjongSceneHandInteraction()
        weak var view: MahjongSceneInteractionView?
        var onDiscard: (MahjongTile, Bool) -> Void

        init(onDiscard: @escaping (MahjongTile, Bool) -> Void) {
            self.onDiscard = onDiscard
            super.init()
            buildTable()
            handInteraction.onAnimation = { [weak self] in self?.view?.needsDisplay = true }
        }

        func discard(at point: CGPoint) {
            guard applied?.canDiscard == true, let tile = handInteraction.tile(at: point) else { return }
            onDiscard(tile.value, tile.drawn)
        }

        func applyTableStyle(_ style: MahjongTableStyle) {
            guard tableStyle != style else { return }
            tableStyle = style
            feltNode.geometry?.materials = [MahjongFeltCloth.material(style: style)]
            view?.backgroundColor = style.color
            SCNTransaction.flush()
            view?.needsDisplay = true
        }

        func sync(_ model: MahjongSceneModel) {
            guard model != applied else { return }
            let previous = applied
            applied = model
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            for view in 0 ..< 4 {
                if previous?.seats[view].hand != model.seats[view].hand {
                    if view == 0 {
                        handInteraction.replaceTiles([])
                    }
                    handRoots[view].childNodes.forEach { $0.removeFromParentNode() }
                    placeHand(model.seats[view].hand, view: view)
                }
                if previous?.seats[view].melds != model.seats[view].melds {
                    meldRoots[view].childNodes.forEach { $0.removeFromParentNode() }
                    placeMelds(model.seats[view].melds, view: view)
                }
                if previous?.seats[view].discards != model.seats[view].discards {
                    discardRoots[view].childNodes.forEach { $0.removeFromParentNode() }
                    placeDiscards(model.seats[view].discards, view: view)
                }
            }
            SCNTransaction.commit()
            // Commit every deal packet now; a paused renderer must also redraw changed models.
            SCNTransaction.flush()
            view?.needsDisplay = true
            view?.refreshPointer()
        }

        private func buildTable() {
            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            // Half the vertical world size. The window locks 1280:1000, so the horizontal half is 8.4 * 1.28.
            camera.camera?.orthographicScale = Double(MahjongHandLayout.cameraHalfHeight)
            camera.camera?.zNear = 0.05
            camera.camera?.zFar = 80
            camera.simdPosition = SIMD3(0, 30, 0)
            // View direction is world -Y. Up is world -Z, so north is the top of the screen.
            // Check: view (0,-1,0) × up (0,0,-1) = screen right (1,0,0). East stays on the right.
            camera.look(
                at: SCNVector3(0, 0, 0),
                up: SCNVector3(0, 0, -1),
                localFront: SCNVector3(0, 0, -1)
            )
            scene.rootNode.addChildNode(camera)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 520
            ambient.light?.color = NSColor(white: 0.92, alpha: 1)
            scene.rootNode.addChildNode(ambient)

            let sun = SCNNode()
            sun.light = SCNLight()
            sun.light?.type = .directional
            sun.light?.intensity = 780
            sun.light?.castsShadow = true
            sun.light?.shadowMode = .deferred
            sun.light?.shadowSampleCount = 8
            sun.light?.shadowRadius = 8
            sun.light?.shadowColor = NSColor(white: 0, alpha: 0.32)
            sun.light?.orthographicScale = 14
            sun.eulerAngles = SCNVector3(-1.05, 0.35, 0)
            scene.rootNode.addChildNode(sun)

            // One cloth. The window shows about ±10.8 by ±8.4, so the plane only has to cover that.
            let extent: Float = 48
            let felt = SCNBox(width: CGFloat(extent), height: 0.05, length: CGFloat(extent), chamferRadius: 0)
            felt.materials = [MahjongFeltCloth.material()]
            feltNode.geometry = felt
            feltNode.name = "mahjong-table-surface"
            feltNode.simdPosition = SIMD3(0, -0.015, 0)
            feltNode.castsShadow = false
            scene.rootNode.addChildNode(feltNode)

            scene.rootNode.addChildNode(tileRoot)
            for root in handRoots + meldRoots + discardRoots {
                tileRoot.addChildNode(root)
            }
        }

        private func placeHand(_ pieces: [MahjongScenePiece], view: Int) {
            let standing = view != 0
            let separator = pieces.firstIndex { $0.tile == nil }
            let row = separator.map { Array(pieces[..<$0]) } ?? pieces
            let drawn = separator == nil ? nil : pieces.last
            let size = MahjongTileBox.tile
            let seat = SeatAxes.frame(view)
            let offsets = MahjongHandLayout.centeredOffsets(count: row.count, tileWidth: size.footprint, gap: MahjongHandLayout.tileGap)
            var localTiles: [MahjongSceneHandInteraction.Tile] = []
            @MainActor func add(_ piece: MahjongScenePiece, across: Float, isDrawn: Bool) {
                guard let tile = piece.tile else { return }
                let position = seat.origin + seat.right * across
                let node = makeTile(
                    tile: tile,
                    faceUp: piece.faceUp,
                    missing: piece.missing,
                    size: size,
                    yaw: standing ? seat.standingYaw : seat.lyingYaw,
                    standing: standing
                )
                node.simdPosition = SIMD3(position.x, standing ? size.standingRestY : size.restY, position.z)
                node.castsShadow = view != 0
                handRoots[view].addChildNode(node)
                if view == 0, piece.faceUp {
                    localTiles.append(.init(node: node, value: tile, drawn: isDrawn))
                }
            }
            for (index, piece) in row.enumerated() {
                add(piece, across: offsets[index], isDrawn: false)
            }
            if let drawn {
                add(drawn, across: MahjongHandLayout.drawnOffset(after: row.count, tileWidth: size.footprint, gap: MahjongHandLayout.tileGap), isDrawn: true)
            }
            if view == 0 {
                handInteraction.replaceTiles(localTiles)
            }
        }

        /// Each seat's melds sit in the corner on that player's left. Two groups per row.
        /// Facing matches that seat's discards: lyingYaw, short side along seat.right.
        private func placeMelds(_ groups: [[MahjongScenePiece]], view: Int) {
            let groups = groups.filter { !$0.isEmpty }
            guard !groups.isEmpty else { return }
            let size = MahjongTileBox.tile
            let seat = SeatAxes.frame(view)
            let corner = Self.meldAnchor(view)
            let tileGap: Float = 0.012
            let tileStep = size.footprint + tileGap
            let groupGap: Float = 0.16
            let rowStep = size.depthStep + groupGap
            // The anchor is the outer corner on that player's left, nearest their hand.
            // Every row shares that left edge. A group runs along +right, and the next
            // row steps toward the center along forward. From the seat, that is
            // bottom-to-top, then left-to-right.
            // Check, south: left is screen-left, so the group runs rightward and the glyph
            // top (yaw 0) points up, the same way a south discard does.
            let alongDir = seat.right
            let inward = seat.forward
            for row in stride(from: 0, to: groups.count, by: 2) {
                let line = groups[row ..< min(row + 2, groups.count)]
                var cursor = size.footprint / 2
                let depth = size.depthStep / 2 + rowStep * Float(row / 2)
                for group in line {
                    for (index, piece) in group.enumerated() {
                        guard let tile = piece.tile else { continue }
                        let across = cursor + tileStep * Float(index)
                        let position = corner + alongDir * across + inward * depth
                        let node = makeTile(
                            tile: tile,
                            faceUp: piece.faceUp,
                            missing: piece.missing,
                            size: size,
                            yaw: seat.lyingYaw
                        )
                        node.simdPosition = SIMD3(position.x, size.restY, position.z)
                        node.castsShadow = view != 0
                        meldRoots[view].addChildNode(node)
                    }
                    cursor += tileStep * Float(group.count) - tileGap + groupGap
                }
            }
        }

        /// Outer corner on that player's left. World -Z is the top of the screen.
        /// At orthographicScale 8.4 the cloth runs about x ±10.75 and z ±8.4.
        private static func meldAnchor(_ view: Int) -> SIMD3<Float> {
            switch view {
            case 1: SIMD3(-10.40, 0, -7.50) // west, top-left
            case 2: SIMD3(10.40, 0, -7.50) // north, top-right
            case 3: SIMD3(10.40, 0, 8.30) // east, bottom-right
            default: SIMD3(-10.40, 0, 8.30) // south, bottom-left
            }
        }

        private func placeDiscards(_ pieces: [MahjongScenePiece], view: Int) {
            guard !pieces.isEmpty else { return }
            let seat = SeatAxes.frame(view)
            // Each river has a fixed region, clear of hands, other rivers and the compass.
            // Fit a growing river inside that region instead of adding rows through the center.
            let base = MahjongTileBox.tile
            let regionWidth: Float = 6
            let regionDepth: Float = 2.85
            var columns = 1
            var fit: Float = 0
            for candidate in 1 ... min(12, pieces.count) {
                let rows = (pieces.count + candidate - 1) / candidate
                let scale = min(
                    1,
                    (regionWidth - Float(candidate - 1) * 0.03) / (Float(candidate) * base.footprint),
                    (regionDepth - Float(rows - 1) * 0.08) / (Float(rows) * base.depthStep)
                )
                if scale > fit + 0.001 || (abs(scale - fit) < 0.001 && abs(candidate - 6) < abs(columns - 6)) {
                    columns = candidate
                    fit = scale
                }
            }
            let size = MahjongTileBox(width: base.width * fit, height: base.height * fit, thickness: base.thickness * fit)
            let step = size.footprint + 0.03
            let handDepth = view == 0 ? base.depthStep : base.thickness
            let handClearance: Float = view == 0 ? 0.34 : 0.22
            let start = handDepth / 2 + handClearance + size.depthStep / 2
            for (index, piece) in pieces.enumerated() {
                guard let tile = piece.tile else { continue }
                let column = index % columns
                let row = index / columns
                let across = (Float(column) - Float(columns - 1) / 2) * step
                let inward = start + Float(row) * (size.depthStep + 0.08)
                let position = seat.origin + seat.right * across + seat.forward * inward
                let node = makeTile(tile: tile, faceUp: true, missing: false, size: size, yaw: seat.lyingYaw)
                node.simdPosition = SIMD3(position.x, size.restY, position.z)
                node.castsShadow = view != 0
                discardRoots[view].addChildNode(node)
            }
        }

        private func makeTile(
            tile: MahjongTile,
            faceUp: Bool,
            missing: Bool,
            size: MahjongTileBox,
            yaw: Float,
            standing: Bool = false
        ) -> SCNNode {
            let round = min(CGFloat(size.thickness) * 0.28, CGFloat(size.width) * 0.13)
            let box = SCNBox(
                width: CGFloat(size.width),
                height: CGFloat(size.height),
                length: CGFloat(size.thickness),
                chamferRadius: round
            )
            box.chamferSegmentCount = 8
            let face = faceUp ? textures.face(tile, missing: missing) : textures.back
            box.materials = [face, textures.edgeRight, textures.back, textures.edgeLeft, textures.edgeTop, textures.edgeBottom]
            let node = SCNNode(geometry: box)
            let spin = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
            if standing {
                // Yaw only. Face (+Z) stays vertical and points at that player. +Y (edgeTop) faces the camera.
                node.simdOrientation = spin
            } else {
                // Lie first, so the face normal (+Z) points at the ceiling. Yaw then turns the glyph.
                // simd_quatf multiplies on the right, so `spin * lie` applies the lie first.
                let lie = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
                node.simdOrientation = spin * lie
            }
            return node
        }
    }
}

private struct MahjongTileBox {
    var width: Float
    var height: Float
    var thickness: Float

    /// Along the row. Standing and lying tiles both keep their width across the row.
    var footprint: Float {
        width
    }

    var depthStep: Float {
        height
    }

    /// Lying center height. The box center is the node position.
    var restY: Float {
        thickness / 2 + 0.02
    }

    /// Standing center height. The face length is vertical, so this is not restY.
    var standingRestY: Float {
        height / 2 + 0.02
    }

    /// Base size for hands and melds; rivers fit down only when their region fills up.
    static let tile = MahjongTileBox(width: MahjongHandLayout.tileWidth, height: MahjongHandLayout.tileHeight, thickness: 0.53)
}

private struct SeatAxes {
    var origin: SIMD3<Float>
    var right: SIMD3<Float>
    var forward: SIMD3<Float>
    var lyingYaw: Float
    var standingYaw: Float

    // Camera looks straight down. World +X is screen right, world -Z is screen up.
    // Lying: face points up. lyingYaw turns the glyph top toward the center.
    // Standing: no lie. standingYaw points face +Z at that player.
    // The two yaws match. Check, west standing yaw -π/2: +Z maps to world -X (toward the
    // west seat) and local +X maps to world +Z, which is seat.right.
    // Check, yaw 0 lie: face +Z maps to +Y and the glyph top (local +Y) maps to world -Z.
    static func frame(_ view: Int) -> SeatAxes {
        // Both side hands share one center and reserve a full draw slot at their right end.
        let sideCenter: Float = 0.4
        switch view {
        case 0:
            return SeatAxes(
                origin: SIMD3(0, 0, MahjongHandLayout.localRowDepth), right: SIMD3(1, 0, 0), forward: SIMD3(0, 0, -1),
                lyingYaw: 0, standingYaw: 0
            )
        case 1:
            return SeatAxes(
                origin: SIMD3(-7.3, 0, sideCenter), right: SIMD3(0, 0, 1), forward: SIMD3(1, 0, 0),
                lyingYaw: -.pi / 2, standingYaw: -.pi / 2
            )
        case 2:
            return SeatAxes(
                origin: SIMD3(0, 0, -5.6), right: SIMD3(-1, 0, 0), forward: SIMD3(0, 0, 1),
                lyingYaw: .pi, standingYaw: .pi
            )
        default:
            return SeatAxes(
                origin: SIMD3(7.3, 0, sideCenter), right: SIMD3(0, 0, -1), forward: SIMD3(-1, 0, 0),
                lyingYaw: .pi / 2, standingYaw: .pi / 2
            )
        }
    }
}

@MainActor
private final class MahjongTileTextures {
    private var faces: [String: SCNMaterial] = [:]
    private let backMaterial: SCNMaterial
    let edgeRight: SCNMaterial
    let edgeLeft: SCNMaterial
    let edgeTop: SCNMaterial
    let edgeBottom: SCNMaterial

    init() {
        backMaterial = Self.colorMaterial(Self.jade)
        // Side UVs run from the face (+Z) to the back (-Z) in different directions on each side.
        edgeRight = Self.imageMaterial(Self.band(horizontal: true, backFirst: false))
        edgeLeft = Self.imageMaterial(Self.band(horizontal: true, backFirst: true))
        edgeTop = Self.imageMaterial(Self.band(horizontal: false, backFirst: true))
        edgeBottom = Self.imageMaterial(Self.band(horizontal: false, backFirst: false))
    }

    var back: SCNMaterial {
        backMaterial
    }

    private static let cream = NSColor(red: 0.98, green: 0.95, blue: 0.89, alpha: 1)
    /// Deep jade distinguishes the lacquered tile back from the brighter table felt.
    private static let jade = NSColor(red: 0.12, green: 0.31, blue: 0.22, alpha: 1)

    /// Two solid bands. Jade is one third, toward the back of the tile. Cream is the other two thirds.
    private static func band(horizontal: Bool, backFirst: Bool) -> NSImage {
        let pixels = 96
        let backSpan = pixels / 3
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        Self.cream.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        Self.jade.setFill()
        if horizontal {
            let x = backFirst ? 0 : pixels - backSpan
            NSRect(x: x, y: 0, width: backSpan, height: pixels).fill()
        } else {
            // Image y grows upward. SceneKit v = 0 is the top of the image.
            let y = backFirst ? pixels - backSpan : 0
            NSRect(x: 0, y: y, width: pixels, height: backSpan).fill()
        }
        image.unlockFocus()
        return image
    }

    func face(_ tile: MahjongTile, missing: Bool) -> SCNMaterial {
        let key = "\(tile.id)-\(missing)"
        if let cached = faces[key] {
            return cached
        }
        let image = Self.render(Self.faceView(tile, missing: missing), size: CGSize(width: 48, height: 68))
        let material = Self.imageMaterial(image)
        faces[key] = material
        return material
    }

    private static func imageMaterial(_ image: NSImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.diffuse.wrapS = .clamp
        material.diffuse.wrapT = .clamp
        material.lightingModel = .blinn
        material.locksAmbientWithDiffuse = true
        return material
    }

    private static func colorMaterial(_ color: NSColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .blinn
        material.locksAmbientWithDiffuse = true
        return material
    }

    private static func render(_ view: some View, size: CGSize) -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 4
        return renderer.nsImage ?? NSImage(size: size)
    }

    private static func faceView(_ tile: MahjongTile, missing: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 0.98, green: 0.95, blue: 0.89)
            MahjongTileFace(tile: tile, compact: false, fullness: 1.55)
                .frame(width: 48, height: 68)
            if missing {
                MahjongMissingSuitFold()
            }
        }
        .frame(width: 48, height: 68)
        .clipped()
    }
}
