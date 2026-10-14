import AppKit
import LANTransfer
import SwiftUI

struct LANTransferModuleView: View {
    @ObservedObject private var store = ShareStore.shared

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(id: "lan-transfer.sharing", placement: .navigation) {
                    Button {
                        if store.running {
                            store.stop()
                        } else {
                            store.start()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: store.running ? "stop.fill" : "wifi")
                            Text(store.running ? "停止共享" : "启动共享")
                        }
                    }
                    .buttonStyle(JarvisToolbarButtonStyle.menu(
                        tint: store.running ? .red : nil
                    ))
                    .help(store.running ? "停止局域网传输" : "启动局域网传输")
                }
            },
            trailingToolbar: {
                ToolbarSpacer(.fixed, placement: .automatic)
            },
            content: {
                GeometryReader { geometry in
                    let spacing: CGFloat = 12
                    let availableHeight = max(0, geometry.size.height - spacing)
                    VStack(spacing: spacing) {
                        LANTransferView()
                            .frame(maxWidth: .infinity)
                            .frame(height: availableHeight * 2 / 3)
                            .jarvisModulePanel()

                        LANTransferTasksView()
                            .frame(maxWidth: .infinity)
                            .frame(height: availableHeight / 3)
                            .jarvisModulePanel()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        )
    }
}
