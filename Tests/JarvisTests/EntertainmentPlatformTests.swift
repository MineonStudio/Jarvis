@testable import Jarvis
import WebKit
import XCTest

@MainActor
final class EntertainmentPlatformTests: XCTestCase {
    func testPlatformsExposeOfficialWebAddresses() {
        XCTAssertEqual(
            EntertainmentPlatform.allCases.map(\.title),
            ["X", "YouTube", "TikTok", "Twitch", "哔哩哔哩"]
        )
        XCTAssertEqual(EntertainmentPlatform.x.url.absoluteString, "https://x.com/")
        XCTAssertEqual(EntertainmentPlatform.youtube.url.absoluteString, "https://www.youtube.com/")
        XCTAssertEqual(EntertainmentPlatform.tiktok.url.absoluteString, "https://www.tiktok.com/")
        XCTAssertEqual(EntertainmentPlatform.twitch.url.absoluteString, "https://www.twitch.tv/")
        XCTAssertEqual(EntertainmentPlatform.bilibili.url.absoluteString, "https://www.bilibili.com/")
    }

    func testHostAllowlistsCoverLoginAndSubdomains() {
        XCTAssertTrue(EntertainmentPlatform.x.allowsHost("x.com"))
        XCTAssertTrue(EntertainmentPlatform.x.allowsHost("www.x.com"))
        XCTAssertTrue(EntertainmentPlatform.x.allowsHost("twitter.com"))
        XCTAssertFalse(EntertainmentPlatform.x.allowsHost("evil.example"))

        XCTAssertTrue(EntertainmentPlatform.youtube.allowsHost("www.youtube.com"))
        XCTAssertTrue(EntertainmentPlatform.youtube.allowsHost("accounts.google.com"))
        XCTAssertTrue(EntertainmentPlatform.youtube.allowsHost("youtu.be"))
        XCTAssertFalse(EntertainmentPlatform.youtube.allowsHost("evil.example"))

        XCTAssertTrue(EntertainmentPlatform.tiktok.allowsHost("www.tiktok.com"))
        XCTAssertTrue(EntertainmentPlatform.tiktok.allowsHost("m.tiktok.com"))
        XCTAssertFalse(EntertainmentPlatform.tiktok.allowsHost("evil.example"))

        XCTAssertTrue(EntertainmentPlatform.twitch.allowsHost("www.twitch.tv"))
        XCTAssertTrue(EntertainmentPlatform.twitch.allowsHost("id.twitch.tv"))
        XCTAssertTrue(EntertainmentPlatform.twitch.allowsHost("player.twitch.tv"))
        XCTAssertFalse(EntertainmentPlatform.twitch.allowsHost("evil.example"))

        XCTAssertTrue(EntertainmentPlatform.bilibili.allowsHost("www.bilibili.com"))
        XCTAssertTrue(EntertainmentPlatform.bilibili.allowsHost("m.bilibili.com"))
        XCTAssertTrue(EntertainmentPlatform.bilibili.allowsHost("live.bilibili.com"))
        XCTAssertTrue(EntertainmentPlatform.bilibili.allowsHost("passport.bilibili.com"))
        XCTAssertTrue(EntertainmentPlatform.bilibili.allowsHost("b23.tv"))
        XCTAssertFalse(EntertainmentPlatform.bilibili.allowsHost("evil.example"))
        XCTAssertFalse(EntertainmentPlatform.bilibili.allowsHost("notbilibili.com"))
    }

    func testEmbeddedFramesStayInsideTheWebView() {
        let ads = URL(string: "https://www.google.com/recaptcha/api2/anchor")
        XCTAssertEqual(
            JarvisWebPlatformNavigationPolicy.decision(
                url: ads,
                isMainFrame: false,
                shouldDownload: false,
                allowsHost: EntertainmentPlatform.youtube.allowsHost
            ),
            .allow
        )
        XCTAssertEqual(
            JarvisWebPlatformNavigationPolicy.decision(
                url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
                isMainFrame: true,
                shouldDownload: false,
                allowsHost: EntertainmentPlatform.youtube.allowsHost
            ),
            .allow
        )
        XCTAssertEqual(
            JarvisWebPlatformNavigationPolicy.decision(
                url: URL(string: "https://evil.example/phish"),
                isMainFrame: true,
                shouldDownload: false,
                allowsHost: EntertainmentPlatform.youtube.allowsHost
            ),
            .openExternally
        )
    }

    /// S-2 回归：window.open 产生的弹窗主帧此前被整段放行，
    /// 钓鱼页可在弹窗内跳转任意域名。现在弹窗主帧同样走白名单判定。
    func testPopupMainFrameNavigationGoesThroughTheAllowlist() {
        XCTAssertEqual(
            JarvisWebPlatformNavigationPolicy.decision(
                url: URL(string: "https://www.youtube.com/"),
                isMainFrame: true,
                shouldDownload: false,
                allowsHost: EntertainmentPlatform.youtube.allowsHost
            ),
            .allow
        )
        XCTAssertEqual(
            JarvisWebPlatformNavigationPolicy.decision(
                url: URL(string: "https://evil.example/phish"),
                isMainFrame: true,
                shouldDownload: false,
                allowsHost: EntertainmentPlatform.youtube.allowsHost
            ),
            .openExternally
        )
    }

    func testEmbeddedWebViewsPresentAsCurrentSafari() {
        let applicationName = JarvisWebPlatformUserAgent.safariCompatibleApplicationName
        let version = ProcessInfo.processInfo.operatingSystemVersion
        XCTAssertEqual(
            applicationName,
            "Version/\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) Safari/605.1.15"
        )
        XCTAssertEqual(
            JarvisWebPlatformConfiguration.make().applicationNameForUserAgent,
            applicationName
        )
    }

    func testDownloadActionsAreCancelledForBothWebModulesAndFrames() throws {
        let blobURL = try XCTUnwrap(URL(string: "blob:https://example.com/file"))
        let fileURL = try XCTUnwrap(URL(string: "https://example.com/file.zip"))
        for platform in [AIConversationProvider.gpt.webPlatform, EntertainmentPlatform.youtube.webPlatform] {
            for isMainFrame in [true, false] {
                for url in [platform.url, blobURL, fileURL] {
                    XCTAssertEqual(
                        JarvisWebPlatformNavigationPolicy.decision(
                            url: url,
                            isMainFrame: isMainFrame,
                            shouldDownload: true,
                            allowsHost: platform.allowsHost
                        ),
                        .cancel
                    )
                }
            }
        }
    }

    func testDownloadResponsesAreBlockedWhileInlineContentStaysVisible() throws {
        let url = try XCTUnwrap(URL(string: "https://www.youtube.com/file"))
        for disposition in ["attachment", "Attachment; filename=video.mp4", " attachment ; filename=page.html"] {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Disposition": disposition]
            ))
            XCTAssertFalse(JarvisWebPlatformNavigationPolicy.allowsResponse(response, canShowMIMEType: true))
        }
        let inlineResponse = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Disposition": "inline; filename=video.mp4"]
        ))
        XCTAssertTrue(JarvisWebPlatformNavigationPolicy.allowsResponse(inlineResponse, canShowMIMEType: true))
        XCTAssertFalse(JarvisWebPlatformNavigationPolicy.allowsResponse(inlineResponse, canShowMIMEType: false))
        let page = URLResponse(url: url, mimeType: "text/html", expectedContentLength: 0, textEncodingName: "utf-8")
        XCTAssertTrue(JarvisWebPlatformNavigationPolicy.allowsResponse(page, canShowMIMEType: true))
    }

    func testWebViewContainerFillsBoundsWithoutCornerOverlaysOrClipping() {
        let container = JarvisWebPlatformViewContainer(
            frame: NSRect(x: 0, y: 0, width: 320, height: 180)
        )
        let webView = WKWebView(frame: .zero)
        container.embed(webView)

        XCTAssertTrue(webView.superview === container)
        XCTAssertFalse(container.clipsToBounds)
        XCTAssertEqual(container.layer?.masksToBounds, false)
        XCTAssertFalse(webView.clipsToBounds)
        XCTAssertEqual(container.subviews.count, 1)
        XCTAssertEqual(webView.frame, container.bounds)

        container.setFrameSize(NSSize(width: 640, height: 360))
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame, container.bounds)
    }

    func testEmbeddedWebViewsAllowElementFullscreen() {
        XCTAssertTrue(
            JarvisWebPlatformConfiguration.make().preferences.isElementFullscreenEnabled
        )
        XCTAssertTrue(JarvisWebPlatformFullscreenLayout.isActive(.enteringFullscreen))
        XCTAssertTrue(JarvisWebPlatformFullscreenLayout.isActive(.inFullscreen))
        XCTAssertFalse(JarvisWebPlatformFullscreenLayout.isActive(.exitingFullscreen))
        XCTAssertFalse(JarvisWebPlatformFullscreenLayout.isActive(.notInFullscreen))
    }

    func testWebModuleSectionsUseMatchingSymbols() {
        XCTAssertEqual(AppSection.home.icon, "house")
        XCTAssertEqual(AppSection.home.navigationTitle, "首页")
        XCTAssertEqual(AppSection.aiConversation.icon, "sparkles")
        XCTAssertEqual(AppSection.aiConversation.navigationTitle, "AI聚合")
        XCTAssertEqual(AppSection.entertainment.icon, "play.rectangle")
        XCTAssertEqual(AppSection.entertainment.navigationTitle, "娱乐广场")
        XCTAssertEqual(
            EntertainmentPlatform.allCases.map(\.iconResourceName),
            ["x", "youtube", "tiktok", "twitch", "bilibili"]
        )
    }
}
