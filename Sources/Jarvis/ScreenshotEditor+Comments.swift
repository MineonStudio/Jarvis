import AppKit

extension ScreenshotEditorModel {
    var isEditingComment: Bool {
        commentInputAnchor != nil
    }

    var nextCommentNumber: Int {
        (annotations.filter { $0.kind == .comment }.map(\.commentNumber).max() ?? 0) + 1
    }

    var pendingComment: ScreenshotAnnotation? {
        guard let anchor = commentInputAnchor, let origin = commentBubbleOrigin else { return nil }
        var comment = ScreenshotAnnotation(
            id: editingCommentID ?? UUID(), kind: .comment, points: [anchor, origin],
            text: commentDraft, brushSize: 0, fontSize: textFontSize, textColor: textColor == .white ? .black : textColor,
            isBold: false, isItalic: false, isStrikethrough: false,
            commentNumber: editingCommentID.flatMap { id in
                annotations.first { $0.id == id }?.commentNumber
            } ?? nextCommentNumber,
            commentWidth: min(280, max(48, commentEditingRect.width - 16))
        )
        comment.points[1] = ScreenshotCommentLayout.clampedOrigin(
            origin, size: ScreenshotCommentLayout.bubbleRect(of: comment).size, in: commentEditingRect
        )
        return comment
    }

    var commentEditingRect: CGRect {
        editingRect ?? CGRect(origin: .zero, size: canvasSize)
    }

    func beginCommentEditing(at point: CGPoint) {
        commitPendingEdits()
        selectedAnnotationID = nil
        selectedTool = .comment
        translationMode = false
        if textColor == .white {
            textColor = .black
        }
        commentInputAnchor = ScreenshotCommentLayout.clampedAnchor(point, in: commentEditingRect)
        commentBubbleOrigin = CGPoint(x: point.x + 40, y: point.y - 64)
        commentDraft = ""
        editingCommentID = nil
        if let pendingComment {
            commentBubbleOrigin = ScreenshotCommentLayout.clampedOrigin(
                pendingComment.end, size: ScreenshotCommentLayout.bubbleRect(of: pendingComment).size,
                in: commentEditingRect
            )
        }
    }

    func selectComment(id: UUID) {
        commitPendingEdits()
        guard let comment = annotations.first(where: { $0.id == id && $0.kind == .comment }) else { return }
        selectedTool = .comment
        translationMode = false
        // 装回样式时暂不选中，避免颜色/字号的观察器把旧控件值写回标注。
        selectedAnnotationID = nil
        textColor = comment.textColor == .white ? .black : comment.textColor
        textFontSize = comment.fontSize
        selectedAnnotationID = id
    }

    func beginCommentEditing(id: UUID) {
        selectComment(id: id)
        guard let comment = annotations.first(where: { $0.id == id && $0.kind == .comment }) else { return }
        editingCommentID = id
        commentInputAnchor = comment.start
        commentBubbleOrigin = comment.end
        commentDraft = comment.text ?? ""
    }

    /// 选中但未进入输入时，颜色和字号也能直接修改当前批注；输入中则由草稿即时预览。
    func updateSelectedCommentStyle() {
        guard selectedTool == .comment, !isEditingComment,
              let id = selectedAnnotationID,
              var comment = annotations.first(where: { $0.id == id && $0.kind == .comment }) else { return }
        comment.textColor = textColor == .white ? .black : textColor
        comment.fontSize = textFontSize
        comment.isBold = false
        comment.isItalic = false
        comment.isStrikethrough = false
        comment.points[1] = ScreenshotCommentLayout.clampedOrigin(
            comment.end, size: ScreenshotCommentLayout.bubbleRect(of: comment).size, in: commentEditingRect
        )
        replaceComment(comment)
    }

    func endCommentEditing() {
        commentInputAnchor = nil
        commentBubbleOrigin = nil
        editingCommentID = nil
        commentDraft = ""
    }

    @discardableResult
    func commitCommentEditing() -> Bool {
        guard var comment = pendingComment else { return false }
        let existingID = editingCommentID
        comment.text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        endCommentEditing()
        guard comment.text?.isEmpty == false else { return false }
        comment.points[1] = ScreenshotCommentLayout.clampedOrigin(
            comment.end, size: ScreenshotCommentLayout.bubbleRect(of: comment).size,
            in: commentEditingRect
        )
        if let existingID, annotations.contains(where: { $0.id == existingID }) {
            replaceComment(comment)
        } else {
            append(comment)
        }
        selectedAnnotationID = comment.id
        return true
    }

    func commitPendingEdits() {
        commitTextEditing()
        commitCommentEditing()
    }

    func commentHit(at point: CGPoint) -> (id: UUID, part: ScreenshotCommentPart)? {
        for comment in annotations.reversed() where comment.kind == .comment {
            if ScreenshotCommentLayout.anchorRect(of: comment).insetBy(dx: -5, dy: -5).contains(point) {
                return (comment.id, .anchor)
            }
            if ScreenshotCommentLayout.bubbleRect(of: comment).insetBy(dx: -4, dy: -4).contains(point) {
                return (comment.id, .bubble)
            }
        }
        return nil
    }
}
