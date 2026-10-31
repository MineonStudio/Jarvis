import Foundation

extension AppModel {
    var canBeginMeetingCapture: Bool {
        guard meetingCurrentRecordingID == nil, !isStartingMeetingRecording else { return false }
        guard !screenRecording.isActive else {
            showToast("请先停止屏幕录制，再开始会议录音。")
            return false
        }
        return true
    }
}
