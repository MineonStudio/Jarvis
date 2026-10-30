import AppKit
@testable import Jarvis
import XCTest

final class ScreenshotColorProbeTests: XCTestCase {
    private func sampler() throws -> ScreenshotColorSampler {
        // Top row red/green, bottom row blue/white. Explicit RGBA avoids
        // display profiles and tests the image's actual pixel row order.
        let data = Data([
            255,
            0,
            0,
            255,
            0,
            255,
            0,
            255,
            0,
            0,
            255,
            255,
            255,
            255,
            255,
            255
        ])
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try XCTUnwrap(CGImage(
            width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        return ScreenshotColorSampler(image: image)
    }

    func testTopLeftCoordinatesAndScaledCanvas() throws {
        let sampler = try sampler()
        let size = CGSize(width: 100, height: 100)
        XCTAssertEqual(sampler.sample(at: CGPoint(x: 0, y: 0), canvasSize: size)?.hex, "#FF0000")
        XCTAssertEqual(sampler.sample(at: CGPoint(x: 75, y: 25), canvasSize: size)?.hex, "#00FF00")
        XCTAssertEqual(sampler.sample(at: CGPoint(x: 25, y: 75), canvasSize: size)?.hex, "#0000FF")
        XCTAssertEqual(sampler.sample(at: CGPoint(x: 99.9, y: 99.9), canvasSize: size)?.hex, "#FFFFFF")
        XCTAssertEqual(sampler.sample(at: CGPoint(x: 0.75, y: 0.25), canvasSize: CGSize(width: 1, height: 1))?.hex, "#00FF00")
    }

    func testOutsideAndInvalidCoordinatesDoNotSampleEdgePixels() throws {
        let sampler = try sampler()
        let size = CGSize(width: 100, height: 100)
        for point in [
            CGPoint(x: -1, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 0, y: 100),
            CGPoint(x: CGFloat.nan, y: 0)
        ] {
            XCTAssertNil(sampler.sample(at: point, canvasSize: size))
        }
        XCTAssertNil(sampler.sample(at: .zero, canvasSize: .zero))
    }
}
