import Foundation

enum ResumeSection: String, CaseIterable, Identifiable, Sendable {
    case basicInfo
    case education
    case experience
    case skills
    case projects

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .basicInfo: "基本信息"
        case .education: "教育经历"
        case .experience: "工作经历"
        case .skills: "掌握技能"
        case .projects: "项目经历"
        }
    }

    var icon: String {
        switch self {
        case .basicInfo: "person.crop.circle"
        case .education: "graduationcap"
        case .experience: "briefcase"
        case .skills: "tag"
        case .projects: "folder"
        }
    }

    var requirementTitle: String {
        self == .basicInfo ? "必填" : "可选"
    }
}
