import SwiftUI

/// The LAN transfer service belongs to the app, so active transfers continue
/// when Jarvis switches to another page and returns to this module.
@MainActor
public struct LANTransferView: View {
    public init() {}

    public var body: some View {
        ContentView(store: ShareStore.shared)
    }
}

@MainActor
public struct LANTransferCommands: Commands {
    @ObservedObject private var store = ShareStore.shared

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button(store.running ? "停止局域网共享" : "启动局域网共享") {
                if store.running {
                    store.stop()
                } else {
                    store.start()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
