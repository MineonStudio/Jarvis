import Foundation

enum SkillID: String, CaseIterable, Hashable, Identifiable {
    case screenshot
    case screenRecording
    case clipboard
    case windowLayout
    case resume
    case wallpaper
    case meetingNotes
    case lanTransfer

    static var sidebarCases: [Self] {
        allCases.filter { $0 != .windowLayout }
    }

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenshot: "截图技能"
        case .screenRecording: "屏幕录制"
        case .clipboard: "剪贴板技能"
        case .windowLayout: "窗口布局技能"
        case .resume: "简历制作技能"
        case .wallpaper: "桌面壁纸技能"
        case .meetingNotes: "会议记录技能"
        case .lanTransfer: "局域网传输"
        }
    }

    var navigationTitle: String {
        switch self {
        case .screenshot: "截图"
        case .screenRecording: "屏幕录制"
        case .clipboard: "剪贴板"
        case .windowLayout: "窗口布局"
        case .resume: "简历制作"
        case .wallpaper: "桌面壁纸"
        case .meetingNotes: "会议记录"
        case .lanTransfer: "局域网传输"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: "viewfinder"
        case .screenRecording: "record.circle"
        case .clipboard: "clipboard"
        case .windowLayout: "macwindow.on.rectangle"
        case .resume: "doc.text.magnifyingglass"
        case .wallpaper: "photo.on.rectangle.angled"
        case .meetingNotes: "waveform.and.person.filled"
        case .lanTransfer: "wifi"
        }
    }
}
