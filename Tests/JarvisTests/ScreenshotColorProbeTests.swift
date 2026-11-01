import AppKit
import ImageIO
@testable import Jarvis
import UniformTypeIdentifiers
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

    func testRepeatedSamplingOfCompressedDesktopImage() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 3840, height: 2160, bitsPerComponent: 8, bytesPerRow: 3840 * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        try context.setFillColor(XCTUnwrap(CGColor(colorSpace: space, components: [1, 0, 0, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 3840, height: 2160))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data, nil))
        let compressed = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let sampler = ScreenshotColorSampler(image: compressed)
        let start = CFAbsoluteTimeGetCurrent()
        var redTotal = 0
        for index in 0 ..< 128 {
            let sample = try XCTUnwrap(sampler.sample(
                at: CGPoint(x: index * 13 % 1920, y: index * 7 % 1080),
                canvasSize: CGSize(width: 1920, height: 1080)
            ))
            redTotal += Int(sample.red)
        }
        print("Color probe: 128 samples of a compressed 4K desktop took \(CFAbsoluteTimeGetCurrent() - start)s")
        XCTAssertEqual(redTotal, 128 * 255)
    }

    func testTransparentPixelsStillCompositeOverWhite() throws {
        let bytes = Data([128, 0, 0, 128, 0, 0, 0, 0])
        let provider = try XCTUnwrap(CGDataProvider(data: bytes as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try XCTUnwrap(CGImage(
            width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let sampler = ScreenshotColorSampler(image: image)
        XCTAssertEqual(sampler.sample(at: .zero, canvasSize: CGSize(width: 2, height: 1))?.hex, "#FF7F7F")
        XCTAssertEqual(sampler.sample(at: CGPoint(x: 1, y: 0), canvasSize: CGSize(width: 2, height: 1))?.hex, "#FFFFFF")
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
