import AppKit

/// Samples the frozen image in top-left canvas coordinates, independently of
/// the selection dimming, annotations and the display's Retina scale.
struct ScreenshotColorSample: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var color: NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

/// Decode and color-convert once; pointer movement only reads three cached bytes.
struct ScreenshotColorSampler: Sendable {
    private let width: Int
    private let height: Int
    private let pixels: Data?

    init(image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var storage = Data(count: width * height * 4)
        let rendered = storage.withUnsafeMutableBytes { bytes -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: bytes.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            // Keep the existing white compositing for transparent source images.
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        pixels = rendered ? storage : nil
    }

    func sample(at point: CGPoint, canvasSize: CGSize) -> ScreenshotColorSample? {
        guard canvasSize.width > 0, canvasSize.height > 0,
              canvasSize.width.isFinite, canvasSize.height.isFinite,
              point.x.isFinite, point.y.isFinite,
              CGRect(origin: .zero, size: canvasSize).contains(point),
              let pixels
        else { return nil }
        let x = min(width - 1, Int(point.x / canvasSize.width * CGFloat(width)))
        let y = min(height - 1, Int(point.y / canvasSize.height * CGFloat(height)))
        let offset = (y * width + x) * 4
        return pixels.withUnsafeBytes { bytes in
            let rgba = bytes.bindMemory(to: UInt8.self)
            return ScreenshotColorSample(red: rgba[offset], green: rgba[offset + 1], blue: rgba[offset + 2])
        }
    }
}
