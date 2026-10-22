import AppKit
@testable import Jarvis
import SceneKit
import XCTest

@MainActor
final class MahjongTableStyleTests: XCTestCase {
    func testStylePersistsAndUnknownSavedStyleFallsBack() throws {
        let name = "MahjongTableStyleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = MahjongTableSettings(defaults: defaults)
        XCTAssertEqual(settings.style, .brocade)
        defaults.set("jade", forKey: "mahjong.table.style")
        XCTAssertEqual(MahjongTableSettings(defaults: defaults).style, .brocade)
        XCTAssertEqual(defaults.string(forKey: "mahjong.table.style"), "brocade")
        settings.style = .walnut
        XCTAssertEqual(MahjongTableSettings(defaults: defaults).style, .walnut)
        defaults.set("unknown-finish", forKey: "mahjong.table.style")
        XCTAssertEqual(MahjongTableSettings(defaults: defaults).style, .brocade)
    }

    func testChangingStyleReplacesOnlyTheSurfaceMaterial() throws {
        let coordinator = MahjongSceneHost.Coordinator { _, _ in }
        let game = MahjongGame()
        coordinator.sync(MahjongSceneModel(game: game))
        let surface = try XCTUnwrap(coordinator.scene.rootNode.childNode(withName: "mahjong-table-surface", recursively: false))
        let firstMaterial = try XCTUnwrap(surface.geometry?.firstMaterial)
        XCTAssertEqual(firstMaterial.diffuse.contents as? NSColor, MahjongTableStyle.brocade.color)
        let roots = coordinator.tileRoot.childNodes
        coordinator.applyTableStyle(.leather)
        let updated = try XCTUnwrap(surface.geometry?.firstMaterial)
        XCTAssertFalse(firstMaterial === updated)
        XCTAssertEqual(updated.diffuse.contents as? NSColor, MahjongTableStyle.leather.color)
        XCTAssertEqual(coordinator.tileRoot.childNodes, roots)
        coordinator.applyTableStyle(.leather)
        XCTAssertTrue(surface.geometry?.firstMaterial === updated)
    }

    func testAllFourMaterialsRenderDistinctNonemptyPreviews() throws {
        XCTAssertEqual(MahjongTableStyle.allCases.count, 4)
        var renders = Set<Data>()
        for style in MahjongTableStyle.allCases {
            let image = MahjongTablePreview.image(for: style)
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
            XCTAssertEqual(bitmap.pixelsWide, 640)
            XCTAssertEqual(bitmap.pixelsHigh, 360)
            let center = try XCTUnwrap(bitmap.colorAt(x: 320, y: 180)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(max(center.redComponent, center.greenComponent, center.blueComponent), 0.06, style.title)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            renders.insert(png)
            if let directory = ProcessInfo.processInfo.environment["JARVIS_TABLE_PREVIEW_DIR"] {
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(style.rawValue).png"))
            }
        }
        XCTAssertEqual(renders.count, 4)
    }
}
