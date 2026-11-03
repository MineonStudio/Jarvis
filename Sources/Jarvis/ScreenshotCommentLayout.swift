import AppKit

enum ScreenshotCommentPart {
    case anchor
    case bubble
}

/// 预览、命中、拖动和 PNG 导出共用几何与绘制，避免气泡与导出的文字错位。
enum ScreenshotCommentLayout {
    static let padding: CGFloat = 12
    static let anchorRadius: CGFloat = 12

    static func textAttributes(for annotation: ScreenshotAnnotation) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return [
            .font: ScreenshotAnnotationText.font(for: annotation),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .strikethroughStyle: annotation.isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
        ]
    }

    static func bubbleRect(of annotation: ScreenshotAnnotation) -> CGRect {
        let maxWidth = max(24, annotation.commentWidth - 2 * padding)
        let rawText = annotation.text ?? ""
        let content = rawText.isEmpty ? "输入批注" : rawText
        let text = (content.hasSuffix("\n") ? content + " " : content) as NSString
        let attributes = textAttributes(for: annotation)
        let measured = text.boundingRect(
            with: CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes
        )
        let wraps = content.components(separatedBy: "\n").contains {
            ($0 as NSString).size(withAttributes: attributes).width > maxWidth
        }
        return CGRect(
            origin: annotation.end,
            size: CGSize(
                width: min(annotation.commentWidth, max(72, (wraps ? maxWidth : ceil(measured.width)) + 2 * padding)),
                height: max(ceil(measured.height), ceil(ScreenshotAnnotationText.font(for: annotation).ascender
                        - ScreenshotAnnotationText.font(for: annotation).descender)) + 2 * padding
            )
        )
    }

    static func anchorRect(of annotation: ScreenshotAnnotation) -> CGRect {
        CGRect(
            x: annotation.start.x - anchorRadius,
            y: annotation.start.y - anchorRadius,
            width: anchorRadius * 2,
            height: anchorRadius * 2
        )
    }

    static func bounds(of annotation: ScreenshotAnnotation) -> CGRect {
        anchorRect(of: annotation).union(bubbleRect(of: annotation)).insetBy(dx: -2, dy: -2)
    }

    static func clampedOrigin(_ origin: CGPoint, size: CGSize, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: max(rect.minX, min(origin.x, rect.maxX - size.width)),
            y: max(rect.minY, min(origin.y, rect.maxY - size.height))
        )
    }

    static func clampedAnchor(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        let inset = min(anchorRadius + 2, min(rect.width, rect.height) / 2)
        return CGPoint(
            x: min(max(point.x, rect.minX + inset), rect.maxX - inset),
            y: min(max(point.y, rect.minY + inset), rect.maxY - inset)
        )
    }

    static func draw(_ annotation: ScreenshotAnnotation, in context: CGContext, opacity: CGFloat = 1, showsBubble: Bool = true) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(opacity)
        let color = annotation.textColor.nsColor
        let bubble = bubbleRect(of: annotation)
        let attachment = CGPoint(
            x: min(max(annotation.start.x, bubble.minX), bubble.maxX),
            y: min(max(annotation.start.y, bubble.minY), bubble.maxY)
        )
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.move(to: annotation.start)
        context.addLine(to: attachment)
        context.strokePath()

        if showsBubble {
            context.addPath(CGPath(roundedRect: bubble, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.setFillColor(color.cgColor)
            context.fillPath()
        }
        let anchor = anchorRect(of: annotation)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: anchor)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let text = (annotation.text ?? "") as NSString
        if showsBubble {
            text.draw(
                with: bubble.insetBy(dx: padding, dy: padding),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: textAttributes(for: annotation)
            )
        }
        let number = String(annotation.commentNumber) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let numberSize = number.size(withAttributes: attributes)
        number.draw(at: CGPoint(
            x: anchor.midX - numberSize.width / 2,
            y: anchor.midY - numberSize.height / 2
        ), withAttributes: attributes)
    }
}
