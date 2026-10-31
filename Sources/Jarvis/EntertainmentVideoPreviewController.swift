import AppKit
import AVKit
import SwiftUI

/// Shared native video preview for recording history, clipboard videos and downloads.
/// Uses the same screen-wide canvas and zoom model as image previews.
@MainActor
final class EntertainmentVideoPreviewController {
    private let previewController = FullscreenMediaPreviewController()
    private var player: AVPlayer?
    private var loadTask: Task<Void, Never>?

    func show(url: URL) {
        dismiss()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let maximumSize = PreviewWindowSupport.maximumContentSize(
            for: PreviewWindowSupport.screenFrames().screen,
            topChromeHeight: 0
        )
        loadTask = Task { [weak self] in
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let naturalSize = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform),
                  !Task.isCancelled, let self else { return }
            let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
            let size = CGSize(width: abs(bounds.width), height: abs(bounds.height))
            let mediaPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            mediaPlayer.isMuted = true
            player = mediaPlayer
            let dismissAction: () -> Void = { [weak self] in self?.dismiss() }
            previewController.show(
                displaySize: FullscreenMediaPreviewSizing.displaySize(for: size, maximumSize: maximumSize),
                allowsHitTesting: true,
                capturesAllScrollEvents: true,
                onDismiss: dismissAction
            ) {
                NativeVideoPreviewView(player: mediaPlayer)
            }
        }
    }

    func dismiss() {
        loadTask?.cancel()
        loadTask = nil
        player?.pause()
        player = nil
        previewController.dismiss()
    }
}

/// An unconstrained AppKit container prevents AVPlayerView's preferred size from
/// limiting the SwiftUI zoom frame. The native view always fills the actual video ratio.
struct NativeVideoPreviewView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context _: Context) -> NativeVideoPreviewSurface {
        let view = NativeVideoPreviewSurface()
        view.playerView.player = player
        DispatchQueue.main.async {
            guard view.playerView.player === player else { return }
            player.play()
        }
        return view
    }

    func updateNSView(_ view: NativeVideoPreviewSurface, context _: Context) {
        if view.playerView.player !== player {
            view.playerView.player?.pause()
            view.playerView.player = player
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: NativeVideoPreviewSurface, context _: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    static func dismantleNSView(_ view: NativeVideoPreviewSurface, coordinator _: ()) {
        view.playerView.player?.pause()
        view.playerView.player = nil
    }
}

final class NativeVideoPreviewSurface: NSView {
    let playerView = AVPlayerView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        playerView.showsFullScreenToggleButton = false
        playerView.allowsVideoFrameAnalysis = false
        playerView.allowsMagnification = false
        playerView.autoresizingMask = [.width, .height]
        playerView.frame = bounds
        addSubview(playerView)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        playerView.frame = bounds
    }
}
