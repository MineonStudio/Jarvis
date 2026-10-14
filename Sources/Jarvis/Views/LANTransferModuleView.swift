import AppKit
import LANTransfer
import SwiftUI

struct LANTransferModuleView: View {
    @Binding var isTasksPresented: Bool
    @ObservedObject private var store = ShareStore.shared
    @State private var showsHotspotGuide = false

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
                ToolbarItem(id: "lan-transfer.tasks", placement: .automatic) {
                    Button {
                        isTasksPresented = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text("传输任务")
                        }
                    }
                    .buttonStyle(JarvisToolbarButtonStyle.menu())
                    .help("查看局域网传输任务")
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "lan-transfer.hotspot-guide", placement: .automatic) {
                    Button {
                        showsHotspotGuide = true
                    } label: {
                        Label("热点指引", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(JarvisToolbarButtonStyle.menu())
                    .help("查看手机热点连接方法")
                }
            },
            content: {
                LANTransferView()
                    .jarvisModulePanel()
            }
        )
        .sheet(isPresented: $showsHotspotGuide) {
            HotspotGuide()
        }
    }
}
