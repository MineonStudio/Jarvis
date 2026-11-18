import Foundation

enum JarvisReleaseNotes {
    static func load(version: String) async -> [String] {
        guard let version = JarvisUpdateSecurity.normalizedVersion(version),
              let url = URL(string: "https://api.github.com/repos/MineonStudio/Jarvis/releases/tags/v\(version)")
        else { return [] }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Jarvis macOS", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              release.tagName == "v\(version)", !release.draft, !release.prerelease,
              let body = release.body
        else { return [] }
        return items(from: body)
    }

    static func items(from markdown: String) -> [String] {
        let sections = sections(from: blocks(from: markdown))
        let changeSections = sections.filter { $0.scope == .changes }
        if !changeSections.isEmpty {
            return changeSections.flatMap { $0.list.isEmpty ? $0.paragraphs : $0.list }
        }
        let generalSections = sections.filter { $0.scope == .general }
        let list = generalSections.flatMap(\.list)
        return list.isEmpty ? generalSections.flatMap(\.paragraphs) : list
    }

    private static func blocks(from markdown: String) -> [Block] {
        guard let content = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full))
        else { return [] }
        var blocks: [Block] = []
        for run in content.runs {
            guard let intents = run.presentationIntent?.components, let intent = intents.first else { continue }
            let text = String(content[run.range].characters)
            if blocks.last?.intent.identity == intent.identity {
                blocks[blocks.count - 1].text += text
            } else {
                let isListItem = intents.contains {
                    if case .listItem = $0.kind {
                        return true
                    }
                    return false
                }
                blocks.append(Block(intent: intent, text: text, isListItem: isListItem))
            }
        }
        return blocks
    }

    private static func sections(from blocks: [Block]) -> [Section] {
        var sections = [Section(scope: .general)]
        var headings: [(level: Int, scope: Section.Scope)] = []
        for block in blocks {
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            switch block.intent.kind {
            case let .header(level):
                while let last = headings.last, last.level >= level {
                    headings.removeLast()
                }
                let scope = sectionScope(for: text.lowercased(), parent: headings.last?.scope)
                headings.append((level, scope))
                sections.append(Section(scope: scope))
            case .paragraph:
                if block.isListItem {
                    sections[sections.count - 1].list.append(text)
                } else {
                    sections[sections.count - 1].paragraphs.append(text)
                }
            default:
                break
            }
        }
        return sections
    }

    private static func sectionScope(for heading: String, parent: Section.Scope?) -> Section.Scope {
        if technicalHeadings.contains(heading) {
            return .technical
        }
        if changeHeadings.contains(heading) {
            return .changes
        }
        return parent ?? .general
    }

    private static let changeHeadings: Set<String> = [
        "更新", "更新内容", "更新说明", "新功能", "新增", "改进", "优化", "调整", "修复",
        "what's new", "what’s new", "what's changed", "changes", "features", "improvements", "bug fixes", "fixes"
    ]

    private static let technicalHeadings: Set<String> = [
        "验证", "校验", "下载", "安装", "发布源码", "完整变更日志", "verification", "checksums", "downloads", "installation"
    ]

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        return URLSession(configuration: configuration)
    }()

    private struct Block {
        let intent: PresentationIntent.IntentType
        var text: String
        let isListItem: Bool
    }

    private struct Section {
        enum Scope {
            case general, changes, technical
        }

        let scope: Scope
        var list: [String] = []
        var paragraphs: [String] = []
    }

    private struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, body
        }
    }
}
