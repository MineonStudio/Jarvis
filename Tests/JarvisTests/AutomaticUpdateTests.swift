import AppKit
@testable import Jarvis
import XCTest

final class AutomaticUpdatePreferenceTests: XCTestCase {
    func testExistingInstallWithoutPreferenceEnablesAutomaticUpdates() throws {
        let suite = "jarvis-automatic-updates-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(JarvisAutomaticUpdatePreference.load(from: defaults))
        XCTAssertEqual(defaults.object(forKey: JarvisAutomaticUpdatePreference.key) as? Bool, true)
    }

    func testExplicitChoiceSurvivesReload() throws {
        let suite = "jarvis-automatic-updates-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        for choice in [false, true, false] {
            defaults.set(choice, forKey: JarvisAutomaticUpdatePreference.key)
            XCTAssertEqual(JarvisAutomaticUpdatePreference.load(from: defaults), choice)
            XCTAssertEqual(JarvisAutomaticUpdatePreference.load(from: defaults), choice)
        }
    }
}

@MainActor
final class UpdatePromptTests: XCTestCase {
    func testRestoringMainWindowForUpdateDoesNotSelectAnAuxiliaryWindow() {
        let auxiliary = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        auxiliary.isReleasedWhenClosed = false
        auxiliary.identifier = NSUserInterfaceItemIdentifier("Jarvis.MediaPreview")
        defer { auxiliary.close() }
        auxiliary.makeKeyAndOrderFront(nil)
        let menuBar = JarvisMenuBarController()
        var openCount = 0
        menuBar.bind { openCount += 1 }

        menuBar.reopenMainWindow(preservingSelection: true)

        XCTAssertEqual(openCount, 1)
    }

    func testMainWindowLookupNeverUsesSettingsPanel() {
        let settings = NSPanel(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false
        )
        settings.identifier = NSUserInterfaceItemIdentifier("Jarvis.SettingsPanel")
        let main = NSWindow(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false
        )
        main.identifier = NSUserInterfaceItemIdentifier(JarvisAppIdentity.mainWindowSceneID)

        XCTAssertTrue(JarvisUpdatePromptController.mainWindow(in: [settings, main]) === main)
        XCTAssertNil(JarvisUpdatePromptController.mainWindow(in: [settings]))
    }

    func testBothPromptActionsArePresentedOnMainWindow() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/update"))
        let release = JarvisReleaseInfo(
            version: "2.0.0", build: "400", releaseURL: url, downloadURL: url,
            manifestURL: url, signatureURL: url, archiveName: "Jarvis-update.zip"
        )
        let main = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        main.isReleasedWhenClosed = false
        main.identifier = NSUserInterfaceItemIdentifier(JarvisAppIdentity.mainWindowSceneID)
        let settings = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 400, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        settings.isReleasedWhenClosed = false
        settings.identifier = NSUserInterfaceItemIdentifier("Jarvis.SettingsPanel")
        defer {
            if let sheet = main.attachedSheet {
                main.endSheet(sheet)
            }
            settings.close()
            main.close()
        }
        main.orderFront(nil)
        let controller = JarvisUpdatePromptController()
        var installCount = 0
        for response in [NSApplication.ModalResponse.alertSecondButtonReturn, .alertFirstButtonReturn] {
            settings.makeKeyAndOrderFront(nil)
            controller.present(
                release: release,
                loadNotes: { _ in ["修复首页网络显示。"] },
                onInstall: { installCount += 1 }
            )
            controller.present(release: release) { XCTFail("Duplicate prompt must be ignored") }
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertTrue(controller.isPresenting)
            let sheet = try XCTUnwrap(main.attachedSheet)
            XCTAssertTrue(sheet.sheetParent === main)
            XCTAssertNil(settings.attachedSheet)
            main.endSheet(sheet, returnCode: response)
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertFalse(controller.isPresenting)
            XCTAssertEqual(installCount, response == .alertFirstButtonReturn ? 1 : 0)
        }
    }

    func testPromptOffersInstallAndDeferralAndExplainsRestart() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/update"))
        for version in ["2.0.0", "v2.0.0"] {
            let release = JarvisReleaseInfo(
                version: version, build: "400", releaseURL: url, downloadURL: url,
                manifestURL: url, signatureURL: url, archiveName: "Jarvis-update.zip"
            )
            let alert = JarvisUpdatePromptController.makeAlert(release: release)

            XCTAssertEqual(alert.messageText, "发现新版本 v2.0.0")
            XCTAssertEqual(alert.buttons.map(\.title), ["立马更新", "稍后更新"])
            XCTAssertEqual(alert.buttons[1].keyEquivalent, "\u{1b}")
            XCTAssertTrue(alert.informativeText.contains("重启应用"))
            XCTAssertTrue(alert.informativeText.contains("暂时无法显示更新说明"))
            XCTAssertNil(alert.accessoryView)
        }
    }
}

extension UpdatePromptTests {
    func testLongReleaseNotesScrollWhileKeepingBothActionsAvailable() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/update"))
        let release = JarvisReleaseInfo(
            version: "2.0.0", build: "400", releaseURL: url, downloadURL: url,
            manifestURL: url, signatureURL: url, archiveName: "Jarvis-update.zip"
        )
        let notes = (1 ... 24).map { "第 \($0) 项更新内容。" }
        let alert = JarvisUpdatePromptController.makeAlert(release: release, notes: notes)
        let scrollView = try XCTUnwrap(alert.accessoryView as? NSScrollView)
        let textView = try XCTUnwrap(scrollView.documentView as? NSTextView)

        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(textView.isEditable)
        XCTAssertEqual(textView.string.components(separatedBy: "\n").count, notes.count)
        XCTAssertTrue(textView.string.contains("第 24 项更新内容。"))
        XCTAssertEqual(alert.buttons.map(\.title), ["立马更新", "稍后更新"])
    }
}

final class JarvisReleaseNotesTests: XCTestCase {
    func testReleaseNotesUseChangeSectionsAndExcludeVerification() {
        let body = """
        发布摘要。

        ## 新功能
        - 新增 **返回顶部**。
        - [查看示例](https://example.com/example)。

        ## 修复
        ### 网络
        重新适配公网地址查询。

        ### 代理
        1. 修复代理地址显示。

        ## 验证
        - 打包和签名校验通过。
        """
        XCTAssertEqual(JarvisReleaseNotes.items(from: body), [
            "新增 返回顶部。", "查看示例。", "重新适配公网地址查询。", "修复代理地址显示。"
        ])
    }

    func testNotesWithoutFormalHeadingsCanUseProseOrLists() {
        XCTAssertEqual(JarvisReleaseNotes.items(from: "修复了设置窗口重复提示。"), ["修复了设置窗口重复提示。"])
        XCTAssertEqual(JarvisReleaseNotes.items(from: "- 优化界面。\n- 修复崩溃。"), ["优化界面。", "修复崩溃。"])
        XCTAssertTrue(JarvisReleaseNotes.items(from: "## 验证\n\n- 签名通过。").isEmpty)
        XCTAssertTrue(JarvisReleaseNotes.items(from: "  ").isEmpty)
    }
}
