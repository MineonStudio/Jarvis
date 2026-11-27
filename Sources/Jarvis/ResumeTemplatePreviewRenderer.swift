import AppKit
import SwiftUI

/// Rasterize the preview directly into its final backing pixels. Keeping the
/// paper -> 168pt -> gallery-card transforms would resample small text twice.
@MainActor
enum ResumeTemplatePreviewRenderer {
    private final class CachedImage {
        let image: CGImage
        init(_ image: CGImage) {
            self.image = image
        }
    }

    private static let cache: NSCache<NSString, CachedImage> = {
        let cache = NSCache<NSString, CachedImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    static func image(template: ResumeTemplate, size: CGSize, displayScale: CGFloat) -> CGImage? {
        let width = (size.width * displayScale).rounded(.up)
        let height = (size.height * displayScale).rounded(.up)
        guard displayScale.isFinite, displayScale > 0,
              width.isFinite, height.isFinite, (1 ... 8192).contains(width), (1 ... 8192).contains(height) else { return nil }
        let key = "\(template.rawValue)-\(Int(width))x\(Int(height))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached.image
        }

        let scale = width / ResumePageLayout.pageSize.width
        let content = ResumeTemplateSkeleton(template: template)
            .frame(width: ResumePageLayout.pageSize.width, height: height / scale, alignment: .topLeading)
            .clipped()
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.isOpaque = true
        // Fractional renderer scales can round 168 pixels up to 169. Remove
        // that extra edge pixel without filtering or resizing the glyphs.
        guard let rendered = renderer.cgImage,
              let image = rendered.cropping(to: CGRect(x: 0, y: 0, width: width, height: height)) else { return nil }
        cache.setObject(CachedImage(image), forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
