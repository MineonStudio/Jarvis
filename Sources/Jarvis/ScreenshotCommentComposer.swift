import AppKit
import SwiftUI

struct ScreenshotCommentComposer: View {
    @ObservedObject var editor: ScreenshotEditorModel

    var body: some View {
        if let comment = editor.pendingComment {
            let panel = ScreenshotCommentLayout.bubbleRect(of: comment)
            ZStack(alignment: .topLeading) {
                if editor.commentDraft.isEmpty {
                    Text("输入批注")
                        .font(.system(size: comment.fontSize))
                        .foregroundStyle(.white.opacity(0.6))
                        .allowsHitTesting(false)
                }
                ScreenshotCommentTextInput(
                    text: $editor.commentDraft, annotation: comment,
                    onCommit: { editor.commitCommentEditing() }
                )
            }
            .frame(
                width: max(1, panel.width - 2 * ScreenshotCommentLayout.padding),
                height: max(1, panel.height - 2 * ScreenshotCommentLayout.padding)
            )
            .padding(ScreenshotCommentLayout.padding)
            .background(comment.textColor.color, in: RoundedRectangle(cornerRadius: 10))
            .offset(x: panel.minX, y: panel.minY)
            .help("直接输入批注，⌘↵ 完成，Esc 取消")
            .id(editor.editingCommentID?.uuidString ?? "new-comment")
        }
    }
}

/// 放在选区变换层之上：即使当前选择了其它工具，也能直接点选已有批注。
struct ScreenshotCommentInteractionView: View {
    @ObservedObject var editor: ScreenshotEditorModel
    let annotation: ScreenshotAnnotation
    @State private var movingPart: ScreenshotCommentPart?
    @State private var previousDrag = CGSize.zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            hitRegion(ScreenshotCommentLayout.anchorRect(of: annotation).insetBy(dx: -5, dy: -5), part: .anchor)
            hitRegion(ScreenshotCommentLayout.bubbleRect(of: annotation), part: .bubble)
        }
        .frame(width: editor.canvasSize.width, height: editor.canvasSize.height, alignment: .topLeading)
    }

    private func hitRegion(_ rect: CGRect, part: ScreenshotCommentPart) -> some View {
        Color.clear
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .offset(x: rect.minX, y: rect.minY)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if movingPart == nil {
                        editor.selectComment(id: annotation.id)
                        editor.beginMove(id: annotation.id)
                        movingPart = part
                    }
                    if hypot(value.translation.width, value.translation.height) >= 4 {
                        editor.moveAnnotation(
                            id: annotation.id,
                            by: CGPoint(
                                x: value.translation.width - previousDrag.width,
                                y: value.translation.height - previousDrag.height
                            ),
                            within: editor.editingRect, commentPart: part
                        )
                        previousDrag = value.translation
                    }
                }
                .onEnded { value in
                    editor.endMove()
                    if hypot(value.translation.width, value.translation.height) < 4 {
                        editor.beginCommentEditing(id: annotation.id)
                    }
                    movingPart = nil
                    previousDrag = .zero
                }
            )
            .accessibilityElement()
            .accessibilityLabel("批注 \(annotation.commentNumber)：\(annotation.text ?? "")")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { editor.beginCommentEditing(id: annotation.id) }
            .contextMenu {
                Button("编辑批注") { editor.beginCommentEditing(id: annotation.id) }
                Button("删除批注", role: .destructive) { editor.deleteAnnotation(id: annotation.id) }
            }
    }
}

/// 多行输入保留中文输入法与原生文本选择，只有 Command-Return 提交。
private struct ScreenshotCommentTextInput: NSViewRepresentable {
    @Binding var text: String
    let annotation: ScreenshotAnnotation
    let onCommit: () -> Void

    func makeNSView(context: Context) -> ScreenshotCommentTextView {
        let textView = ScreenshotCommentTextView(frame: CGRect(x: 0, y: 0, width: 72, height: 28))
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = CGSize(width: 260, height: CGFloat.greatestFiniteMagnitude)
        textView.allowsUndo = true
        textView.setAccessibilityLabel("批注内容")
        textView.delegate = context.coordinator
        update(textView)
        return textView
    }

    func updateNSView(_ textView: ScreenshotCommentTextView, context: Context) {
        context.coordinator.text = $text
        update(textView)
    }

    private func update(_ textView: ScreenshotCommentTextView) {
        textView.onCommit = onCommit
        // 输入法组字期间不重设字符串、字体或属性，避免打断中文候选词。
        guard !textView.hasMarkedText() else { return }
        if textView.string != text {
            textView.string = text
        }
        let attributes = ScreenshotCommentLayout.textAttributes(for: annotation)
        textView.font = ScreenshotAnnotationText.font(for: annotation)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.typingAttributes = attributes
        if let storage = textView.textStorage {
            storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}

final class ScreenshotCommentTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if [36, 76].contains(event.keyCode), event.modifierFlags.contains(.command), !hasMarkedText() {
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}
