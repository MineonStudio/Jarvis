import SceneKit
import SwiftUI

struct MahjongTableStylePicker: View {
    @Bindable private var settings = MahjongTableSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("选择牌桌主题")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Text("当前：\(settings.style.title)")
                    .font(.system(size: 13))
                    .foregroundStyle(MahjongVisualTheme.accent)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 18) {
                ForEach(MahjongTableStyle.allCases) { style in
                    styleButton(style)
                }
            }
            Text("选择后立即生效，自动保存在本机。")
                .font(.system(size: 13))
                .foregroundStyle(MahjongVisualTheme.muted)
        }
        .foregroundStyle(MahjongVisualTheme.ivory)
    }

    private func styleButton(_ style: MahjongTableStyle) -> some View {
        let selected = settings.style == style
        return Button {
            settings.style = style
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: MahjongTablePreview.image(for: style))
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 23))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(MahjongVisualTheme.ink, MahjongVisualTheme.accent)
                                .padding(12)
                                .shadow(color: .black.opacity(0.25), radius: 4)
                        }
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Text(style.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(selected ? MahjongVisualTheme.accent : MahjongVisualTheme.ivory)
                    Text(style.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(MahjongVisualTheme.muted)
                }
                .padding(14)
            }
            .background(.black.opacity(0.23))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(selected ? MahjongVisualTheme.accent : .white.opacity(0.14), lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityValue(selected ? "已选中" : "未选中")
        .help("使用\(style.title)主题")
    }
}

/// Render the actual scene material once per style, so previews match the table.
@MainActor
enum MahjongTablePreview {
    private static var cache: [MahjongTableStyle: NSImage] = [:]

    static func image(for style: MahjongTableStyle) -> NSImage {
        if let image = cache[style] {
            return image
        }
        let scene = SCNScene()
        let surface = SCNBox(width: 48, height: 0.05, length: 48, chamferRadius: 0)
        surface.materials = [MahjongFeltCloth.material(style: style)]
        scene.rootNode.addChildNode(SCNNode(geometry: surface))
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 5.5
        camera.position = SCNVector3(0, 20, 0)
        camera.look(at: SCNVector3(0, 0, 0), up: SCNVector3(0, 0, -1), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 780
        sun.eulerAngles = SCNVector3(-1.05, 0.35, 0)
        scene.rootNode.addChildNode(sun)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 640, height: 360), antialiasingMode: .multisampling4X)
        cache[style] = image
        return image
    }
}
