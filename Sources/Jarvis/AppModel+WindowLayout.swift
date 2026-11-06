import AppKit

enum WindowDragLayoutPreference {
    static let key = "jarvis.window-layout.drag.enabled"

    static func load(from defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }
}

struct WindowDragLayoutActivation {
    private(set) var awaitingPermission = false

    mutating func request(hasPermission: Bool) -> Bool {
        awaitingPermission = !hasPermission
        return hasPermission
    }

    mutating func receivePermission(granted: Bool) -> Bool {
        guard awaitingPermission, granted else { return false }
        awaitingPermission = false
        return true
    }

    mutating func cancel() {
        awaitingPermission = false
    }
}

extension AppModel {
    func configureWindowDragLayout() {
        guard windowDragLayoutEnabled else {
            windowDragLayoutController?.stop()
            return
        }
        if windowDragLayoutController == nil, let windowLayoutController {
            windowDragLayoutController = WindowDragLayoutController(layoutController: windowLayoutController)
        }
        windowDragLayoutController?.start()
    }

    func updateWindowDragLayoutEnabled(_ enabled: Bool) {
        guard enabled else {
            windowDragLayoutActivation.cancel()
            persistWindowDragLayoutEnabled(false)
            return
        }
        refreshPermissionStatus()
        guard windowDragLayoutActivation.request(hasPermission: accessibilityPermissionGranted) else {
            persistWindowDragLayoutEnabled(false)
            promptForTaskPermission(.accessibility, presentation: .settingsWindow)
            return
        }
        persistWindowDragLayoutEnabled(true)
    }

    func completePendingWindowDragLayoutEnableIfAllowed() {
        guard windowDragLayoutActivation.receivePermission(granted: accessibilityPermissionGranted) else { return }
        persistWindowDragLayoutEnabled(true)
    }

    private func persistWindowDragLayoutEnabled(_ enabled: Bool) {
        windowDragLayoutEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: WindowDragLayoutPreference.key)
        configureWindowDragLayout()
    }

    func showWindowLayoutPicker() {
        toolUsage.recordOpen(.windowLayout)
        if windowLayoutPickerController?.isPresented == true {
            windowLayoutPickerController?.cancel(animated: true)
            return
        }
        refreshPermissionStatus()
        guard accessibilityPermissionGranted else {
            promptForTaskPermission(.accessibility)
            return
        }
        windowDragLayoutController?.cancel()
        guard let target = WindowDragTarget.captureFocusedWindow(), let frame = target.frame,
              let screen = NSScreen.screens.max(by: { lhs, rhs in
                  let left = lhs.frame.intersection(frame)
                  let right = rhs.frame.intersection(frame)
                  return left.width * left.height < right.width * right.height
              })
        else {
            showToast(JarvisFeedbackCopy.noAdjustableWindow)
            return
        }
        windowLayoutPickerController?.present(target: target, on: screen)
    }
}
