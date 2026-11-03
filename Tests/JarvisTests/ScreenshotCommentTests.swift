import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

@MainActor
final class ScreenshotCommentTests: XCTestCase {
    private func makeEditor(scale: CGFloat = 1) throws -> ScreenshotEditorModel {
        let size = CGSize(width: 640, height: 400)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = try XCTUnwrap(NSImage(data: data))
        return ScreenshotEditorModel(image: image, data: data, outputData: data, canvasSize: size)
    }

    private func addComment(_ editor: ScreenshotEditorModel, text: String = "检查这里") throws -> ScreenshotAnnotation {
        editor.selectTool(.comment)
        editor.beginCommentEditing(at: CGPoint(x: 120, y: 160))
        editor.commentDraft = text
        XCTAssertTrue(editor.commitCommentEditing())
        return try XCTUnwrap(editor.annotations.last)
    }

    func testCommentUsesTextStyleAndCanBeReeditedAndUndone() throws {
        let editor = try makeEditor()
        editor.textColor = .blue
        editor.textFontSize = try XCTUnwrap(ScreenshotTextSize.options.last?.size)
        editor.textBold = false
        let original = try addComment(editor)
        XCTAssertEqual(original.textColor, .blue)
        XCTAssertEqual(original.fontSize, 32)
        XCTAssertFalse(original.isBold)
        editor.clearSelection()
        editor.textColor = .red
        editor.textFontSize = 16
        editor.beginCommentEditing(id: original.id)
        XCTAssertEqual(editor.textColor, .blue)
        XCTAssertEqual(editor.textFontSize, 32)
        editor.commentDraft = "修改后的说明\n第二行"
        editor.textColor = .green
        editor.textFontSize = 16
        editor.commitCommentEditing()
        XCTAssertEqual(editor.annotations.count, 1)
        XCTAssertEqual(editor.annotations[0].commentNumber, 1)
        XCTAssertEqual(editor.annotations[0].textColor, .green)
        editor.undo()
        XCTAssertEqual(editor.annotations, [original])
        editor.redo()
        XCTAssertEqual(editor.annotations[0].text, "修改后的说明\n第二行")
    }

    func testCancelPreservesExistingAndEmptyDraftCreatesNothing() throws {
        let editor = try makeEditor()
        editor.beginCommentEditing(at: .zero)
        editor.commentDraft = " \n "
        XCTAssertFalse(editor.commitCommentEditing())
        XCTAssertTrue(editor.annotations.isEmpty)
        let original = try addComment(editor)
        editor.beginCommentEditing(id: original.id)
        editor.commentDraft = "取消这次修改"
        XCTAssertTrue(editor.handleEscape())
        XCTAssertFalse(editor.isEditingComment)
        XCTAssertEqual(editor.annotations, [original])
        XCTAssertTrue(editor.handleEscape(), "第二次 Esc 只取消选中")
        XCTAssertFalse(editor.handleEscape(), "再按 Esc 才退出截图")
    }

    func testToolAndTranslationSwitchCommitDrafts() throws {
        let editor = try makeEditor()
        editor.beginCommentEditing(at: CGPoint(x: 80, y: 80))
        editor.commentDraft = "换工具前保留"
        editor.selectTool(.text)
        XCTAssertEqual(editor.annotations.last?.text, "换工具前保留")
        editor.beginCommentEditing(at: CGPoint(x: 80, y: 120))
        editor.commentDraft = "翻译前保留"
        editor.enterTranslationMode()
        XCTAssertEqual(editor.annotations.last?.text, "翻译前保留")
        XCTAssertFalse(editor.isEditingComment)
        XCTAssertTrue(editor.translationMode)
    }

    func testMoveAnchorAndBubbleSeparatelyWithSingleUndo() throws {
        let editor = try makeEditor()
        let comment = try addComment(editor)
        editor.beginMove(id: comment.id)
        editor.moveAnnotation(id: comment.id, by: CGPoint(x: -30, y: 20), commentPart: .anchor)
        editor.moveAnnotation(id: comment.id, by: CGPoint(x: -10, y: 5), commentPart: .anchor)
        editor.endMove()
        XCTAssertEqual(editor.annotations[0].end, comment.end)
        XCTAssertEqual(editor.annotations[0].start.x, comment.start.x - 40)
        editor.undo()
        XCTAssertEqual(editor.annotations, [comment])
        editor.beginMove(id: comment.id)
        editor.moveAnnotation(id: comment.id, by: CGPoint(x: 40, y: 20), commentPart: .bubble)
        editor.endMove()
        XCTAssertEqual(editor.annotations[0].start, comment.start)
        XCTAssertEqual(editor.annotations[0].end.x, comment.end.x + 40)
        editor.undo()
        XCTAssertEqual(editor.annotations, [comment])
    }

    func testNumberingDeleteDuplicateAndHitTargets() throws {
        let editor = try makeEditor()
        let first = try addComment(editor)
        let second = try addComment(editor)
        XCTAssertEqual(second.commentNumber, 2)
        editor.selectedAnnotationID = second.id
        editor.duplicateSelectedAnnotation()
        XCTAssertEqual(editor.annotations.last?.commentNumber, 3)
        editor.deleteAnnotation(id: second.id)
        let fourth = try addComment(editor)
        XCTAssertEqual(fourth.commentNumber, 4)
        XCTAssertEqual(editor.commentHit(at: fourth.start)?.id, fourth.id)
        XCTAssertEqual(editor.commentHit(at: fourth.start)?.part, .anchor)
        let bubble = ScreenshotCommentLayout.bubbleRect(of: fourth)
        XCTAssertEqual(editor.commentHit(at: CGPoint(x: bubble.midX, y: bubble.midY))?.part, .bubble)
        editor.beginCommentEditing(id: first.id)
        editor.deleteAnnotation(id: first.id)
        XCTAssertFalse(editor.isEditingComment)
    }

    func testEdgePlacementAndLongTextWrapWithinSelection() throws {
        let editor = try makeEditor()
        let selection = CGRect(x: 200, y: 100, width: 240, height: 220)
        editor.updateSelectionRect(selection)
        editor.beginCommentEditing(at: CGPoint(x: 440, y: 320))
        editor.commentDraft = "这是一条需要自动换行的中文批注，用来检查靠近截图边缘时说明文字仍能完整保留。"
        editor.textFontSize = 16
        editor.commitCommentEditing()
        let comment = try XCTUnwrap(editor.annotations.first)
        let bubble = ScreenshotCommentLayout.bubbleRect(of: comment)
        XCTAssertTrue(selection.contains(bubble))
        XCTAssertTrue(selection.contains(ScreenshotCommentLayout.anchorRect(of: comment)))
        XCTAssertGreaterThan(bubble.height, 50)
        XCTAssertLessThanOrEqual(bubble.width, selection.width)
    }

    func testExportCommitsPendingCommentAndRendersAnchorAtRetinaScale() async throws {
        for scale: CGFloat in [1, 2] {
            let editor = try makeEditor(scale: scale)
            editor.beginCommentEditing(at: CGPoint(x: 120, y: 160))
            editor.commentDraft = "随截图导出"
            editor.textColor = .blue
            let data = await editor.finalPNGData()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertFalse(editor.isEditingComment)
            XCTAssertEqual(editor.annotations.count, 1)
            XCTAssertEqual(bitmap.pixelsWide, Int(640 * scale))
            XCTAssertEqual(bitmap.pixelsHigh, Int(400 * scale))
            let pixel = try XCTUnwrap(bitmap.colorAt(x: Int(113 * scale), y: Int(160 * scale)))
            let rgb = try XCTUnwrap(pixel.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(rgb.blueComponent, 0.8)
            XCTAssertLessThan(rgb.redComponent, 0.3, "落点应当在画布位置按像素倍率导出")
        }
    }

    func testCommentToolOpensSharedStyleBar() throws {
        let editor = try makeEditor()
        editor.selectTool(.comment)
        XCTAssertTrue(editor.secondaryBarVisible)
        let slots = ScreenshotToolbarComposition.mainRow
        let textIndex = try XCTUnwrap(slots.firstIndex(of: .tool(.text)))
        XCTAssertEqual(slots[textIndex + 1], .tool(.comment))
    }

    func testReselectFromAnotherToolRestoresStyleAndChangesOnlySelectedComment() throws {
        let editor = try makeEditor()
        let first = try addComment(editor)
        let second = try addComment(editor, text: "另一条批注")
        editor.selectTool(.arrow)
        editor.textColor = .green
        editor.selectComment(id: first.id)
        XCTAssertEqual(editor.selectedTool, .comment)
        XCTAssertEqual(editor.textColor, first.textColor)
        editor.textColor = .blue
        XCTAssertEqual(editor.annotations[0].textColor, .blue)
        XCTAssertEqual(editor.annotations[1], second)
        editor.undo()
        XCTAssertEqual(editor.annotations[0], first)
        editor.beginCommentEditing(id: first.id)
        editor.commentDraft = "点选后直接编辑"
        editor.textColor = .green
        editor.commitCommentEditing()
        XCTAssertEqual(editor.annotations[0].text, "点选后直接编辑")
        XCTAssertEqual(editor.annotations[0].textColor, .green)
    }

    func testPanelGrowsThenWrapsAndShrinksDuringInput() throws {
        let editor = try makeEditor()
        editor.beginCommentEditing(at: CGPoint(x: 600, y: 360))
        editor.commentDraft = "短"
        let short = try XCTUnwrap(editor.pendingComment)
        let shortRect = ScreenshotCommentLayout.bubbleRect(of: short)
        editor.commentDraft = "这是一条长度适中的说明"
        let mediumRect = try ScreenshotCommentLayout.bubbleRect(of: XCTUnwrap(editor.pendingComment))
        XCTAssertGreaterThan(mediumRect.width, shortRect.width)
        editor.commentDraft = String(repeating: "自动换行并增高", count: 5)
        let long = try XCTUnwrap(editor.pendingComment)
        let longRect = ScreenshotCommentLayout.bubbleRect(of: long)
        XCTAssertEqual(longRect.width, long.commentWidth)
        XCTAssertGreaterThan(longRect.height, mediumRect.height)
        XCTAssertTrue(editor.commentEditingRect.contains(longRect), "边缘输入时面板也应实时留在选区内")
        editor.commentDraft = "短"
        let shrunkRect = try ScreenshotCommentLayout.bubbleRect(of: XCTUnwrap(editor.pendingComment))
        XCTAssertEqual(shrunkRect.size, shortRect.size)
        editor.commentDraft = "短\n"
        XCTAssertGreaterThan(
            try ScreenshotCommentLayout.bubbleRect(of: XCTUnwrap(editor.pendingComment)).height,
            shortRect.height, "回车后即使下一行为空也要为光标留出一行"
        )
    }

    func testSolidPanelExportKeepsWhiteTextAndIgnoresFontDecorations() async throws {
        let editor = try makeEditor()
        editor.textBold = true
        editor.textItalic = true
        editor.textStrikethrough = true
        let comment = try addComment(editor, text: "白色文字")
        XCTAssertFalse(comment.isBold)
        XCTAssertFalse(comment.isItalic)
        XCTAssertFalse(comment.isStrikethrough)
        let color = try XCTUnwrap(ScreenshotCommentLayout.textAttributes(for: comment)[.foregroundColor] as? NSColor)
        XCTAssertEqual(color, .white)
        let data = await editor.finalPNGData()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
        let bubble = ScreenshotCommentLayout.bubbleRect(of: comment)
        let insetPixel = try XCTUnwrap(bitmap.colorAt(x: Int(bubble.minX + 6), y: Int(bubble.midY)))
        let rgb = try XCTUnwrap(insetPixel.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(rgb.redComponent, 0.9)
        XCTAssertLessThan(rgb.greenComponent, 0.3, "面板内部应填充所选红色而非浅色底")
    }
}
