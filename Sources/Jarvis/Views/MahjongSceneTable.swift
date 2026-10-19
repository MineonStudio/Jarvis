import SceneKit
import SwiftUI

/// Orthographic camera straight above the felt. North is the top of the window.
/// One tile size. The other three hands stand, so the camera sees their tops.
/// The local hand, melds, and discards lie face-up.
struct MahjongSceneTable: View {
    let game: MahjongGame

    var body: some View {
        MahjongSceneHost(model: MahjongSceneModel(game: game)) { tile in
            game.discard(tile)
        }
    }
}

private struct MahjongScenePiece: Equatable {
    var tile: MahjongTile?
    var faceUp: Bool
    var missing: Bool
}

private struct MahjongSceneSeat: Equatable {
    var hand: [MahjongScenePiece]
    var melds: [[MahjongScenePiece]]
    var discards: [MahjongScenePiece]
}

@MainActor
private struct MahjongSceneModel: Equatable {
    var seats: [MahjongSceneSeat]
    var canDiscard: Bool

    init(game: MahjongGame) {
        canDiscard = game.isHumanTurn
        seats = (0..<4).map { view in
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
        let source: [MahjongTile]
        if face, seat == game.visibleHandSeat, !reveal {
            source = game.visibleHand
        } else {
            source = game.hands.indices.contains(seat) ? game.hands[seat] : []
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
            let faced: [(MahjongTile, Bool)]
            if meld.kind == .concealedKong, sorted.count == 4 {
                faced = [(sorted[0], false), (sorted[1], true), (sorted[2], true), (sorted[3], false)]
            } else {
                faced = sorted.map { ($0, true) }
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
private struct MahjongSceneHost: NSViewRepresentable {
    var model: MahjongSceneModel
    var onDiscard: (MahjongTile) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDiscard: onDiscard)
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor(red: 0.055, green: 0.22, blue: 0.11, alpha: 1)
        view.rendersContinuously = false
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.click(_:)))
        view.addGestureRecognizer(click)
        let tracking = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: context.coordinator,
            userInfo: nil
        )
        view.addTrackingArea(tracking)
        context.coordinator.view = view
        context.coordinator.sync(model)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        view.window?.acceptsMouseMovedEvents = true
        context.coordinator.onDiscard = onDiscard
        context.coordinator.view = view
        context.coordinator.sync(model)
    }

    @MainActor
    final class Coordinator: NSObject {
        var onDiscard: (MahjongTile) -> Void
        weak var view: SCNView?
        let scene = SCNScene()
        let camera = SCNNode()
        let tileRoot = SCNNode()
        private var applied: MahjongSceneModel?
        private var hovered: SCNNode?
        private var restPositions: [ObjectIdentifier: SIMD3<Float>] = [:]
        /// Straight up, off the felt. A top-down tile has no camera-facing tilt to lift along.
        private let handLift = SIMD3<Float>(0, 0.22, 0)
        private let textures = MahjongTileTextures()

        init(onDiscard: @escaping (MahjongTile) -> Void) {
            self.onDiscard = onDiscard
            super.init()
            buildTable()
        }

        func sync(_ model: MahjongSceneModel) {
            guard model != applied else { return }
            applied = model
            hovered = nil
            restPositions.removeAll()
            tileRoot.childNodes.forEach { $0.removeFromParentNode() }
            for view in 0..<4 {
                placeHand(model.seats[view].hand, view: view, canDiscard: view == 0 && model.canDiscard)
                placeMelds(model.seats[view].melds, view: view)
                placeDiscards(model.seats[view].discards, view: view)
            }
        }

        @objc func click(_ recognizer: NSClickGestureRecognizer) {
            guard let view, let model = applied, model.canDiscard else { return }
            let point = recognizer.location(in: view)
            guard let node = view.hitTest(point, options: nil).first?.node else { return }
            guard let index = Self.localIndex(of: node), model.seats[0].hand.indices.contains(index),
                  let tile = model.seats[0].hand[index].tile else { return }
            onDiscard(tile)
        }

        @objc func mouseMoved(with event: NSEvent) {
            guard let view, applied?.canDiscard == true else { return }
            let point = view.convert(event.locationInWindow, from: nil)
            let node = view.hitTest(point, options: nil).first?.node
            let target = node.flatMap { Self.carrier(of: $0) }
            guard target !== hovered else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.12
            if let hovered, let rest = restPositions[ObjectIdentifier(hovered)] {
                hovered.simdPosition = rest
            }
            if let target, target.name?.hasPrefix("local:") == true, let rest = restPositions[ObjectIdentifier(target)] {
                target.simdPosition = rest + handLift
                hovered = target
                NSCursor.pointingHand.set()
            } else {
                hovered = nil
                NSCursor.arrow.set()
            }
            SCNTransaction.commit()
        }

        private func buildTable() {
            camera.camera = SCNCamera()
            camera.camera?.usesOrthographicProjection = true
            // Half the vertical world size. The window locks 1280:1000, so the horizontal half is 8.4 * 1.28.
            camera.camera?.orthographicScale = 8.4
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
            let feltNode = SCNNode(geometry: felt)
            feltNode.simdPosition = SIMD3(0, -0.015, 0)
            feltNode.castsShadow = false
            scene.rootNode.addChildNode(feltNode)

            scene.rootNode.addChildNode(tileRoot)
        }

        private func placeHand(_ pieces: [MahjongScenePiece], view: Int, canDiscard: Bool) {
            // Views 1–3 stand. A straight-down camera then sees edgeTop, not the indigo back.
            let standing = view != 0
            lay(
                pieces,
                view: view,
                size: .tile,
                distance: 0,
                gap: 0.02,
                standing: standing
            ) { index, piece, node in
                guard view == 0 else { return }
                self.restPositions[ObjectIdentifier(node)] = node.simdPosition
                if canDiscard, piece.faceUp {
                    node.name = "local:\(index)"
                }
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
            let groupGap = size.footprint
            let rowStep = size.depthStep + 0.10
            // The anchor is the outer corner on the player's left. A group runs toward
            // the hand along +right, and the next row steps toward the center along forward.
            // Check, south: left is screen-left, so the group runs rightward and the glyph
            // top (yaw 0) points up, the same way a south discard does.
            let alongDir = seat.right
            let inward = seat.forward
            for row in stride(from: 0, to: groups.count, by: 2) {
                let line = groups[row..<min(row + 2, groups.count)]
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
                        tileRoot.addChildNode(node)
                    }
                    cursor += tileStep * Float(group.count) - tileGap + groupGap
                }
            }
        }

        /// Outer corner on that player's left. World -Z is the top of the screen.
        /// At orthographicScale 8.4 the cloth runs about x ±10.75 and z ±8.4.
        private static func meldAnchor(_ view: Int) -> SIMD3<Float> {
            switch view {
            case 1: return SIMD3(-10.40, 0, -8.26) // west, top-left
            case 2: return SIMD3(10.40, 0, -8.26) // north, top-right
            case 3: return SIMD3(10.40, 0, 8.26) // east, bottom-right
            default: return SIMD3(-10.40, 0, 8.26) // south, bottom-left
            }
        }

        private func placeDiscards(_ pieces: [MahjongScenePiece], view: Int) {
            let seat = SeatAxes.frame(view)
            let size = MahjongTileBox.tile
            let step = size.footprint + 0.03
            // South sits farther out, with a gap above the hand for the action tray.
            // The other rivers start just inside their walls and still stop short of the compass.
            let start: Float = view == 0 ? 1.88 : 1.32
            for (index, piece) in pieces.enumerated() {
                guard let tile = piece.tile else { continue }
                let column = index % 6
                let row = index / 6
                let across = (Float(column) - 2.5) * step
                let inward = start + Float(row) * (size.depthStep + 0.08)
                let position = seat.origin + seat.right * across + seat.forward * inward
                let node = makeTile(tile: tile, faceUp: true, missing: false, size: size, yaw: seat.lyingYaw)
                node.simdPosition = SIMD3(position.x, size.restY, position.z)
                node.castsShadow = view != 0
                tileRoot.addChildNode(node)
            }
        }

        private func lay(
            _ pieces: [MahjongScenePiece],
            view: Int,
            size: MahjongTileBox,
            distance: Float,
            gap: Float,
            standing: Bool = false,
            tag: ((Int, MahjongScenePiece, SCNNode) -> Void)?
        ) {
            let seat = SeatAxes.frame(view)
            let step = size.footprint + gap
            let span = step * Float(max(pieces.count - 1, 0))
            let yaw = standing ? seat.standingYaw : seat.lyingYaw
            let lift = standing ? size.standingRestY : size.restY
            for (index, piece) in pieces.enumerated() {
                guard let tile = piece.tile else { continue }
                let across = -span / 2 + step * Float(index)
                let position = seat.origin + seat.right * across + seat.forward * distance
                let node = makeTile(
                    tile: tile,
                    faceUp: piece.faceUp,
                    missing: piece.missing,
                    size: size,
                    yaw: yaw,
                    standing: standing
                )
                node.simdPosition = SIMD3(position.x, lift, position.z)
                node.castsShadow = view != 0
                tag?(index, piece, node)
                tileRoot.addChildNode(node)
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

        private static func carrier(of node: SCNNode) -> SCNNode? {
            var current: SCNNode? = node
            while let cursor = current {
                if cursor.name?.hasPrefix("local:") == true { return cursor }
                current = cursor.parent
            }
            return nil
        }

        private static func localIndex(of node: SCNNode) -> Int? {
            guard let name = carrier(of: node)?.name, name.hasPrefix("local:") else { return nil }
            return Int(name.dropFirst("local:".count))
        }
    }
}

private struct MahjongTileBox {
    var width: Float
    var height: Float
    var thickness: Float

    /// Along the row. Standing and lying tiles both keep their width across the row.
    var footprint: Float { width }
    var depthStep: Float { height }
    /// Lying center height. The box center is the node position.
    var restY: Float { thickness / 2 + 0.02 }
    /// Standing center height. The face length is vertical, so this is not restY.
    var standingRestY: Float { height / 2 + 0.02 }

    /// One size for hands, melds, and discards. Face is 0.72 by 1.01.
    /// Thickness is 0.48 so a top-down standing tile reads as a top, not a hairline.
    static let tile = MahjongTileBox(width: 0.72, height: 1.01, thickness: 0.48)
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
        switch view {
        case 0:
            return SeatAxes(
                origin: SIMD3(0, 0, 5.48), right: SIMD3(1, 0, 0), forward: SIMD3(0, 0, -1),
                lyingYaw: 0, standingYaw: 0
            )
        case 1:
            return SeatAxes(
                origin: SIMD3(-6.72, 0, 0), right: SIMD3(0, 0, 1), forward: SIMD3(1, 0, 0),
                lyingYaw: -.pi / 2, standingYaw: -.pi / 2
            )
        case 2:
            return SeatAxes(
                origin: SIMD3(0, 0, -5.05), right: SIMD3(-1, 0, 0), forward: SIMD3(0, 0, 1),
                lyingYaw: .pi, standingYaw: .pi
            )
        default:
            return SeatAxes(
                origin: SIMD3(6.72, 0, 0), right: SIMD3(0, 0, -1), forward: SIMD3(-1, 0, 0),
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
        backMaterial = Self.colorMaterial(Self.indigo)
        // Side UVs run from the face (+Z) to the back (-Z) in different directions on each side.
        edgeRight = Self.imageMaterial(Self.band(horizontal: true, backFirst: false))
        edgeLeft = Self.imageMaterial(Self.band(horizontal: true, backFirst: true))
        edgeTop = Self.imageMaterial(Self.band(horizontal: false, backFirst: true))
        edgeBottom = Self.imageMaterial(Self.band(horizontal: false, backFirst: false))
    }

    var back: SCNMaterial { backMaterial }

    private static let cream = NSColor(red: 0.98, green: 0.95, blue: 0.89, alpha: 1)
    /// Lacquered cobalt. Bright enough to read under the overhead light, and distinct from the green felt.
    private static let indigo = NSColor(red: 0.18, green: 0.34, blue: 0.68, alpha: 1)

    /// Two solid bands. Indigo is one third, toward the back of the tile. Cream is the other two thirds.
    private static func band(horizontal: Bool, backFirst: Bool) -> NSImage {
        let pixels = 96
        let backSpan = pixels / 3
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        Self.cream.setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        Self.indigo.setFill()
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
        if let cached = faces[key] { return cached }
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

    private static func render<V: View>(_ view: V, size: CGSize) -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 4
        return renderer.nsImage ?? NSImage(size: size)
    }

    private static func faceView(_ tile: MahjongTile, missing: Bool) -> some View {
        ZStack {
            Color(red: 0.98, green: missing ? 0.74 : 0.95, blue: missing ? 0.74 : 0.89)
            MahjongTileFace(tile: tile, compact: false, fullness: 1.55)
                .frame(width: 48, height: 68)
        }
        .frame(width: 48, height: 68)
        .clipped()
    }

}
