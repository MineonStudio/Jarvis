import Foundation

enum MeetingRecordingPreferences {
    static let hotwordsKey = "jarvis.meeting.hotwords"
    static var hotwords: String {
        UserDefaults.standard.string(forKey: hotwordsKey) ?? ""
    }
}
