import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class JarvisHomePointerTracker {
    var location: CGPoint?
    var lastPointerMovement = Date.distantPast

    var isIdle: Bool {
        Date().timeIntervalSince(lastPointerMovement) >= 8
    }
}
