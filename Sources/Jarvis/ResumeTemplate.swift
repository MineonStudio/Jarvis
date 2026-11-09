import Foundation

enum ResumeTemplate: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case minimal
    case mono
    case grid
    case business
    case summit
    case slate
    case classic
    case heritage
    case scholar
    case editorial
    case journal
    case gazette
    case creative
    case prism
    case orbit

    static let defaultTemplate: ResumeTemplate = .minimal

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        // Retired layouts remain importable without retaining them in the gallery.
        switch value {
        case "structured", "timeline", "executive", "technical": self = .business
        case "traditional", "academic": self = .classic
        case "folio", "typographic": self = .creative
        default: self = Self(rawValue: value) ?? .defaultTemplate
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .minimal: "留白"
        case .mono: "素线"
        case .grid: "秩序"
        case .business: "领航"
        case .summit: "峰会"
        case .slate: "远见"
        case .classic: "书简"
        case .heritage: "典藏"
        case .scholar: "文脉"
        case .editorial: "人物志"
        case .journal: "专栏"
        case .gazette: "周刊"
        case .creative: "跃动"
        case .prism: "棱镜"
        case .orbit: "轨迹"
        }
    }

    var icon: String {
        switch baseTemplate {
        case .minimal: "text.alignleft"
        case .business: "rectangle.leadinghalf.filled"
        case .classic: "text.book.closed"
        case .editorial: "newspaper"
        case .creative: "circle.hexagongrid"
        default: "doc.text"
        }
    }

    var sectionOrder: [ResumeSection] {
        switch self {
        case .minimal: [.experience, .projects, .education, .skills]
        case .business: [.education, .skills, .experience, .projects]
        case .classic: [.education, .experience, .projects, .skills]
        case .editorial: [.experience, .education, .skills, .projects]
        case .creative: [.projects, .skills, .education, .experience]
        case .mono: [.experience, .education, .skills, .projects]
        case .grid: [.education, .skills, .projects, .experience]
        case .summit: [.experience, .projects, .education, .skills]
        case .slate: [.skills, .education, .projects, .experience]
        case .heritage: [.experience, .projects, .education, .skills]
        case .scholar: [.education, .experience, .skills, .projects]
        case .journal: [.projects, .experience, .education, .skills]
        case .gazette: [.projects, .experience, .education, .skills]
        case .prism: [.skills, .projects, .experience, .education]
        case .orbit: [.education, .skills, .projects, .experience]
        }
    }

    var baseTemplate: ResumeTemplate {
        switch category {
        case .minimal, .all: .minimal
        case .business: .business
        case .classic: .classic
        case .editorial: .editorial
        case .creative: .creative
        }
    }

    var isVariant: Bool {
        self != baseTemplate
    }

    var usesDarkSidebar: Bool {
        self == .business || self == .orbit
    }

    var category: ResumeTemplateCategory {
        switch self {
        case .minimal, .mono, .grid: .minimal
        case .business, .summit, .slate: .business
        case .classic, .heritage, .scholar: .classic
        case .editorial, .journal, .gazette: .editorial
        case .creative, .prism, .orbit: .creative
        }
    }
}

enum ResumeTemplateCategory: String, CaseIterable, Identifiable, Sendable {
    case all
    case minimal
    case business
    case classic
    case editorial
    case creative

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部"
        case .minimal: "极简"
        case .business: "商务"
        case .classic: "经典"
        case .editorial: "编辑"
        case .creative: "创意"
        }
    }

    var templates: [ResumeTemplate] {
        self == .all ? ResumeTemplate.allCases : ResumeTemplate.allCases.filter { $0.category == self }
    }
}
