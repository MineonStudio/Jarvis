import AppKit

/// 画布与操作栏共享真正的 key window，让原生玻璃随编辑窗口正常激活。
/// 画布坐标不变；历史图片编辑时窗口扩展到容纳图外操作栏的范围。
final class ScreenshotEditingSurface: NSView {
    let canvas: NSView
    let toolbar: NSView

    init(canvas: NSView, toolbar: NSView) {
        self.canvas = canvas
        self.toolbar = toolbar
        super.init(frame: .zero)
        addSubview(canvas)
        addSubview(toolbar, positioned: .above, relativeTo: canvas)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var canvasFrameOnScreen: CGRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(canvas.frame, to: nil))
    }

    func place(canvasFrame: CGRect, toolbarFrame: CGRect, in window: NSWindow) {
        let frame = canvasFrame.union(toolbarFrame)
        window.setFrame(frame, display: false, animate: false)
        self.frame = CGRect(origin: .zero, size: frame.size)
        canvas.frame = canvasFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        toolbar.frame = toolbarFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    func isCanvasLocation(_ pointInWindow: NSPoint) -> Bool {
        let point = convert(pointInWindow, from: nil)
        return canvas.frame.contains(point) && !toolbar.frame.contains(point)
    }
}
