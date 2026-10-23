import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

@MainActor
final class MahjongCountdownArcTests: XCTestCase {
    func testColorMovesFromGreenThroughYellowToRed() {
        XCTAssertEqual(MahjongCountdownTint.color(progress: 1), .green)
        XCTAssertEqual(MahjongCountdownTint.color(progress: 0.5), .yellow)
        XCTAssertEqual(MahjongCountdownTint.color(progress: 0), .red)
        let early = MahjongCountdownTint.color(progress: 0.75)
        let late = MahjongCountdownTint.color(progress: 0.25)
        XCTAssertGreaterThan(early.green, early.red)
        XCTAssertGreaterThan(late.red, late.green)
        XCTAssertGreaterThan(late.red, early.red)
    }

    func testFullRingUsesOnlyTheCurrentGreen() throws {
        let bitmap = try renderArc(progress: 1)
        for degrees in [40.0, 180, 270] {
            let sample = try sample(bitmap, degrees: degrees)
            XCTAssertGreaterThan(sample.green, sample.red)
            XCTAssertGreaterThan(sample.green, sample.blue)
        }
    }

    func testGapOpensClockwiseWhileTheRestStaysOneColor() throws {
        let bitmap = try renderArc(progress: 0.5)
        let cleared = try sample(bitmap, degrees: 45)
        let kept = try sample(bitmap, degrees: 270)
        XCTAssertLessThan(cleared.red + cleared.green + cleared.blue, 0.15)
        XCTAssertGreaterThan(kept.red, 0.7)
        XCTAssertGreaterThan(kept.green, 0.55)
        XCTAssertLessThan(kept.blue, 0.45)
    }

    private func renderArc(progress: Double) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content:
            MahjongCountdownArc(progress: progress)
                .frame(width: 120, height: 120)
                .background(Color.black)
        )
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        return try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
    }

    private func sample(
        _ bitmap: NSBitmapImageRep,
        degrees: Double
    ) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let center = Double(bitmap.pixelsWide) / 2
        let radius = center - 3
        let radians = degrees * .pi / 180
        let x = Int((center + sin(radians) * radius).rounded())
        let y = Int((center - cos(radians) * radius).rounded())
        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }
}
