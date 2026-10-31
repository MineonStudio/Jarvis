import AppKit
import SwiftUI

@MainActor
final class ClipboardMediaPreviewController {
    private let previewController = FullscreenMediaPreviewController()
    private let videoPreviewController = EntertainmentVideoPreviewController()

    func show(item: ClipboardItem) {
        dismiss()

        let frames = PreviewWindowSupport.screenFrames()
        let maximumSize = PreviewWindowSupport.maximumContentSize(
            for: frames.screen,
            topChromeHeight: 0
        )

        switch item.kind {
        case .text:
            guard let text = item.resolvedText else { return }
            previewController.show(
                displaySize: FullscreenMediaPreviewSizing.textDisplaySize(
                    for: text,
                    maximumSize: maximumSize
                ),
                allowsHitTesting: true,
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            ) {
                FullscreenTextPreviewContent(text: text)
            }
        case .image, .video:
            showMedia(item: item, maximumSize: maximumSize)
        case .file:
            return
        }
    }

    private func showMedia(item: ClipboardItem, maximumSize: CGSize) {
        let path = item.kind == .image ? item.imagePath : item.filePath
        guard let path, FileManager.default.fileExists(atPath: path) else { return }

        if item.kind == .image, let image = NSImage(contentsOfFile: path) {
            previewController.show(
                displaySize: FullscreenMediaPreviewSizing.displaySize(
                    for: image.size,
                    maximumSize: maximumSize
                ),
                onDismiss: { [weak self] in
                    self?.dismiss()
                }
            ) {
                Image(nsImage: image)
                    .interpolation(.high)
                    .resizable()
                    .scaledToFit()
            }
            return
        }

        videoPreviewController.show(url: URL(fileURLWithPath: path))
    }

    func dismiss() {
        videoPreviewController.dismiss()
        previewController.dismiss()
    }
}
