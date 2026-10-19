@testable import Jarvis
import SceneKit
import XCTest

final class MahjongSceneHandInteractionTests: XCTestCase {
    @MainActor
    func testNativeCoordinatesHitTheSameModelAtDifferentWindowSizesAndFlips() throws {
        for size in [CGSize(width: 960, height: 750), CGSize(width: 1280, height: 1000)] {
            for flipped in [false, true] {
                let unit = size.height / CGFloat(MahjongHandLayout.cameraHalfHeight * 2)
                let topY = size.height / 2 + CGFloat(MahjongHandLayout.localRowDepth) * unit
                let local = CGPoint(x: size.width / 2, y: flipped ? topY : size.height - topY)
                let world = try XCTUnwrap(MahjongHandLayout.worldPoint(local, size: size, isFlipped: flipped))
                let interaction = makeHand()
                XCTAssertEqual(interaction.tile(at: world)?.value, .honor(0))
            }
        }
    }

    @MainActor
    func testRestingAndRaisedFootprintsStayActiveUntilPointerLeaves() {
        let interaction = makeHand()
        let rest = interaction.tiles[0].rest
        interaction.updatePointer(CGPoint(x: 0, y: CGFloat(rest.z)), animated: false)
        XCTAssertEqual(interaction.hoveredIndex, 0)
        XCTAssertEqual(interaction.tiles[0].node.simdPosition.z, rest.z - 0.275, accuracy: 0.00001)
        // The lower resting edge remains active even after the model has moved away.
        interaction.updatePointer(CGPoint(x: 0, y: CGFloat(rest.z + 0.54)), animated: false)
        XCTAssertEqual(interaction.hoveredIndex, 0)
        // The visible raised top also remains active.
        interaction.updatePointer(CGPoint(x: 0, y: CGFloat(rest.z - 0.80)), animated: false)
        XCTAssertEqual(interaction.hoveredIndex, 0)
        interaction.updatePointer(CGPoint(x: 0, y: CGFloat(rest.z - 0.9)), animated: false)
        XCTAssertNil(interaction.hoveredIndex)
        XCTAssertEqual(interaction.tiles[0].node.simdPosition, rest)
    }

    @MainActor
    func testDrawnTileKeepsItsDiscardIdentityAndGapDoesNotRespond() throws {
        let interaction = makeHand()
        let rest = interaction.tiles[0].rest
        let drawn = interaction.tiles[1].rest
        XCTAssertNil(interaction.tile(at: CGPoint(x: CGFloat((rest.x + drawn.x) / 2), y: CGFloat(rest.z))))
        XCTAssertTrue(try XCTUnwrap(interaction.tile(at: CGPoint(x: CGFloat(drawn.x), y: CGFloat(drawn.z)))?.drawn))
        XCTAssertFalse(try XCTUnwrap(interaction.tile(at: CGPoint(x: CGFloat(rest.x), y: CGFloat(rest.z)))?.drawn))
    }

    @MainActor
    func testReplacingTheHandClearsHoverAndRestoresOldModel() {
        let interaction = makeHand()
        let tile = interaction.tiles[0]
        interaction.updatePointer(CGPoint(x: 0, y: CGFloat(tile.rest.z)), animated: false)
        interaction.updatePointer(nil)
        interaction.replaceTiles([])
        XCTAssertNil(interaction.hoveredIndex)
        XCTAssertEqual(tile.node.simdPosition, tile.rest)
        XCTAssertNil(tile.node.action(forKey: "hand.hover"))
    }

    @MainActor
    func testSceneKitRendersIntermediateHoverFramesAndSmoothReversal() {
        let interaction = makeHand()
        let tile = interaction.tiles[0]
        let scene = SCNScene()
        scene.rootNode.addChildNode(tile.node)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 8.4
        camera.position = SCNVector3(0, 30, 0)
        camera.look(at: SCNVector3Zero, up: SCNVector3(0, 0, -1), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        renderer.isPlaying = true
        func render(_ time: TimeInterval) {
            _ = renderer.snapshot(atTime: time, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
        }
        render(0)
        interaction.updatePointer(CGPoint(x: 0, y: CGFloat(tile.rest.z)))
        render(0.01)
        render(0.01 + 1.0 / 60)
        XCTAssertLessThan(
            tile.node.presentation.simdPosition.z,
            tile.rest.z - 0.005,
            "The first frame after entry should already show upward motion"
        )
        render(0.11)
        let midpoint = tile.node.presentation.simdPosition.z
        XCTAssertLessThan(midpoint, tile.rest.z - 0.01)
        XCTAssertGreaterThan(midpoint, tile.rest.z - 0.265)
        interaction.updatePointer(nil)
        XCTAssertEqual(tile.node.simdPosition.z, midpoint, accuracy: 0.001)
        render(0.12)
        render(0.22)
        let returning = tile.node.presentation.simdPosition.z
        XCTAssertGreaterThan(returning, midpoint)
        XCTAssertLessThan(returning, tile.rest.z)
        render(0.40)
        XCTAssertEqual(tile.node.presentation.simdPosition.z, tile.rest.z, accuracy: 0.001)
        XCTAssertFalse(interaction.isAnimating)
    }

    @MainActor
    func testEachDealPacketIsRenderedBeforeTheHandIsComplete() {
        let game = MahjongGame()
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: false)
        var snapshot = game.makeLANSnapshot()
        snapshot.phase = .dealing
        snapshot.hands = Array(repeating: [], count: 4)
        let coordinator = MahjongSceneHost.Coordinator(onDiscard: { _, _ in })
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = coordinator.scene
        renderer.pointOfView = coordinator.camera
        game.applyLANSnapshot(snapshot)
        coordinator.sync(MahjongSceneModel(game: game))
        var previousFrame = renderer.snapshot(atTime: 0, with: CGSize(width: 256, height: 200), antialiasingMode: .none).tiffRepresentation
        // Verify the first card and subsequent partial packets, before dealing has finished.
        for count in [1, 4, 8, 13] {
            snapshot.hands[0] = Array(repeating: .suited(.dots, 2), count: count)
            snapshot.dealtCount = count
            game.applyLANSnapshot(snapshot)
            coordinator.sync(MahjongSceneModel(game: game))
            XCTAssertEqual(coordinator.handInteraction.tiles.count, count)
            XCTAssertTrue(coordinator.handInteraction.tiles.allSatisfy {
                $0.node.geometry is SCNBox && $0.node.parent != nil && !$0.node.isHidden && $0.node.opacity == 1
            })
            let frame = renderer.snapshot(atTime: Double(count) / 60, with: CGSize(width: 256, height: 200), antialiasingMode: .none).tiffRepresentation
            XCTAssertNotNil(frame)
            XCTAssertNotEqual(frame, previousFrame, "The next frame must show each partial deal packet")
            previousFrame = frame
        }
    }

    @MainActor
    func testReducedMotionMovesImmediatelyWithoutSchedulingAnimation() {
        let interaction = makeHand(reduceMotion: true)
        let tile = interaction.tiles[0]
        interaction.updatePointer(CGPoint(x: 0, y: CGFloat(tile.rest.z)))
        XCTAssertEqual(tile.node.simdPosition.z, tile.rest.z - 0.275, accuracy: 0.00001)
        XCTAssertFalse(interaction.isAnimating)
        interaction.updatePointer(nil)
        XCTAssertEqual(tile.node.simdPosition, tile.rest)
        XCTAssertFalse(interaction.isAnimating)
    }

    @MainActor
    private func makeHand(reduceMotion: Bool = false) -> MahjongSceneHandInteraction {
        let interaction = MahjongSceneHandInteraction(reduceMotion: reduceMotion)
        let node = SCNNode(geometry: SCNBox(width: 0.78, height: 1.10, length: 0.53, chamferRadius: 0.1))
        node.simdPosition = SIMD3(0, 0.285, MahjongHandLayout.localRowDepth)
        let drawn = node.clone()
        drawn.simdPosition.x = MahjongHandLayout.drawnOffset(after: 1, tileWidth: 0.78, gap: 0.02)
        interaction.replaceTiles([
            .init(node: node, value: .honor(0), drawn: false),
            .init(node: drawn, value: .honor(1), drawn: true)
        ])
        return interaction
    }
}
