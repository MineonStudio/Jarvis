import SwiftUI

struct MahjongTileBackView: View {
    var scale: CGFloat = 1

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = MahjongTablePalette(scheme: colorScheme)
        // Same shell as MahjongTileView. Only the face panel is the back.
        let cornerRadius: CGFloat = 9
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.tileSide)
                .offset(x: 3 * scale, y: -4 * scale)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.88, green: 0.74, blue: 0.48), Color(red: 0.67, green: 0.50, blue: 0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .offset(x: 1.5 * scale, y: -2 * scale)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: palette.tileBackGreen,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: .black.opacity(palette.tileShadowOpacity(compact: false)), radius: 2.5, x: 1.5, y: -1.5)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(red: 0.24, green: 0.21, blue: 0.19), lineWidth: 1.35 * scale)
            // Back artwork stays upright so the tile edge matches the local hand.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color(red: 0.89, green: 0.78, blue: 0.50).opacity(0.85), lineWidth: 0.7 * scale)
                .padding(6 * scale)
            VStack(spacing: 2 * scale) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 6 * scale, weight: .bold))
                Capsule()
                    .frame(width: 1.2 * scale, height: 13 * scale)
                Circle()
                    .frame(width: 2.2 * scale, height: 2.2 * scale)
            }
            .foregroundStyle(Color(red: 0.91, green: 0.81, blue: 0.58).opacity(0.8))
        }
        .frame(width: 48 * scale, height: 68 * scale)
        .accessibilityHidden(true)
    }
}

/// Red corner on a 缺一门 tile. The face stays cream so the suit marks stay readable.
struct MahjongMissingSuitFold: View {
    var leg: CGFloat = 16

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: leg, y: 0))
                path.addLine(to: CGPoint(x: leg, y: leg))
                path.closeSubpath()
            }
            .fill(Color(red: 0.78, green: 0.18, blue: 0.24))
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: leg, y: leg))
            }
            .stroke(Color(red: 0.42, green: 0.07, blue: 0.09), lineWidth: max(1, leg * 0.06))
        }
        .frame(width: leg, height: leg)
        .accessibilityHidden(true)
    }
}

struct MahjongTileView: View {
    let tile: MahjongTile
    var isSelected = false
    var isMissingSuit = false
    var compact = false
    var scale: CGFloat = 1
    var faceRotation: CGFloat = 0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = MahjongTablePalette(scheme: colorScheme)
        let cornerRadius: CGFloat = compact ? 3 : 9
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.tileSide)
                .offset(x: compact ? 1 : 3 * scale, y: compact ? -1.2 : -4 * scale)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.88, green: 0.74, blue: 0.48), Color(red: 0.67, green: 0.50, blue: 0.28)], startPoint: .top, endPoint: .bottom))
                .offset(x: compact ? 0.5 : 1.5 * scale, y: compact ? -0.6 : -2 * scale)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 1.0, blue: 0.98), Color(red: 0.97, green: 0.96, blue: 0.91)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(palette.tileShadowOpacity(compact: compact)), radius: compact ? 0.8 : 2.5, x: compact ? 0.5 : 1.5, y: compact ? -0.8 : -1.5)
            MahjongTileFace(tile: tile, compact: compact, rotation: faceRotation, scale: scale)
                .padding(compact ? 1 : 0)
            if isMissingSuit {
                MahjongMissingSuitFold(leg: compact ? 9 : 16 * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(red: 0.24, green: 0.21, blue: 0.19), lineWidth: compact ? 0.65 : 1.35 * scale)
        }
        .frame(
            width: compact ? 26 : 48 * scale,
            height: compact ? 37 : 68 * scale
        )
        .accessibilityLabel(tile.accessibilityName)
    }
}

struct MahjongTileFace: View {
    let tile: MahjongTile
    let compact: Bool
    var rotation: CGFloat = 0
    var scale: CGFloat = 1
    var fullness: CGFloat = 1

    var body: some View {
        Group {
            if rotation == 0 {
                canvas
            } else {
                canvas
                    .frame(width: 68 * scale, height: 48 * scale)
                    .rotationEffect(.degrees(rotation))
                    .frame(width: 48 * scale, height: 68 * scale)
                    .clipped()
            }
        }
        .accessibilityHidden(true)
    }

    private var canvas: some View {
        Canvas { context, size in
            switch tile {
            case let .suited(.dots, rank):
                if rank == 1 {
                    drawFlower(in: &context, size: size)
                } else {
                    let pips = dotPattern(rank)
                    for pip in pips {
                        let nearest = pips.filter { $0.x != pip.x || $0.y != pip.y }.map {
                            hypot(($0.x - pip.x) * size.width, ($0.y - pip.y) * size.height)
                        }.min() ?? min(size.width, size.height)
                        let baseRadius = (compact ? 1.7 : min(size.width * 0.14, size.height * 0.095)) * fullness
                        let radius = min(baseRadius, nearest * 0.43)
                        drawConcentricDot(at: CGPoint(x: pip.x * size.width, y: pip.y * size.height), radius: radius, in: &context, color: color(for: pip.ink))
                    }
                }
            case let .suited(.bamboo, rank):
                if rank == 1 {
                    drawBird(in: &context, size: size)
                } else if rank == 8 {
                    drawEightBamboo(in: &context, size: size)
                } else {
                    for stick in bambooPattern(rank) {
                        drawBambooStick(at: CGPoint(x: stick.x * size.width, y: stick.y * size.height), in: &context, size: size, color: color(for: stick.ink))
                    }
                }
            case let .suited(.characters, rank):
                let numbers = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
                drawCalligraphy(numbers[rank], in: &context, at: CGPoint(x: size.width / 2, y: size.height * 0.33), font: (compact ? 8 : 19) * fullness, color: .blue)
                drawCalligraphy("萬", in: &context, at: CGPoint(x: size.width / 2, y: size.height * 0.71), font: (compact ? 8 : 17) * fullness, color: .red)
            case let .honor(rank):
                let glyphs = ["東", "南", "西", "北", "中", "發", "白"]
                if rank == 6 {
                    drawWhiteDragon(in: &context, size: size)
                } else {
                    drawCalligraphy(glyphs[rank], in: &context, at: CGPoint(x: size.width / 2, y: size.height * 0.52), font: (compact ? 12 : 27) * fullness, color: rank == 4 ? .red : (rank == 5 ? .green : .blue))
                }
            }
        }
    }

    private func drawCalligraphy(_ value: String, in context: inout GraphicsContext, at point: CGPoint, font: CGFloat, color inkValue: MahjongTileInk) {
        let ink = color(for: inkValue)
        let text = Text(value).font(.custom("Kaiti SC", size: font).weight(.bold)).foregroundColor(ink)
        context.draw(text, at: point)
    }

    private func color(for ink: MahjongTileInk) -> Color {
        switch ink {
        case .red: Color(red: 0.78, green: 0.18, blue: 0.24)
        case .blue: Color(red: 0.14, green: 0.33, blue: 0.63)
        case .green: Color(red: 0.13, green: 0.54, blue: 0.27)
        case .emerald: Color(red: 0.08, green: 0.47, blue: 0.26)
        }
    }

    private func drawConcentricDot(at point: CGPoint, radius: CGFloat, in context: inout GraphicsContext, color: Color) {
        let outer = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let inner = outer.insetBy(dx: radius * 0.23, dy: radius * 0.23)
        let core = outer.insetBy(dx: radius * 0.48, dy: radius * 0.48)
        context.fill(Path(ellipseIn: outer), with: .color(color))
        context.fill(Path(ellipseIn: inner), with: .color(.white))
        context.fill(Path(ellipseIn: core), with: .color(color))
        context.fill(Path(ellipseIn: core.insetBy(dx: radius * 0.22, dy: radius * 0.22)), with: .color(.white.opacity(0.92)))
    }

    private func drawFlower(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.5)
        let radiusX = size.width * 0.30
        let radiusY = size.height * 0.21
        let petalRadiusX = size.width * 0.048
        let petalRadiusY = size.height * 0.049
        for index in 0 ..< 16 {
            let angle = CGFloat(index) * .pi * 2 / 16
            let point = CGPoint(x: center.x + cos(angle) * radiusX * 0.645, y: center.y + sin(angle) * radiusY * 0.645)
            let petal = CGRect(x: point.x - petalRadiusX, y: point.y - petalRadiusY, width: petalRadiusX * 2, height: petalRadiusY * 2)
            context.fill(Path(ellipseIn: petal), with: .color(color(for: .green)))
        }
        let outer = CGRect(x: center.x - radiusX, y: center.y - radiusY, width: radiusX * 2, height: radiusY * 2)
        context.stroke(Path(ellipseIn: outer), with: .color(color(for: .blue)), lineWidth: max(0.8, size.width * 0.036))
        let centerRadiusX = size.width * 0.154
        let centerRadiusY = size.height * 0.108
        let centerRect = CGRect(x: center.x - centerRadiusX, y: center.y - centerRadiusY, width: centerRadiusX * 2, height: centerRadiusY * 2)
        context.fill(Path(ellipseIn: centerRect), with: .color(color(for: .red)))
        context.stroke(Path(ellipseIn: centerRect), with: .color(.white), lineWidth: max(0.7, size.width * 0.024))
        var cross = Path()
        cross.move(to: CGPoint(x: center.x, y: center.y - centerRadiusY * 0.68))
        cross.addLine(to: CGPoint(x: center.x, y: center.y + centerRadiusY * 0.68))
        cross.move(to: CGPoint(x: center.x - centerRadiusX * 0.68, y: center.y))
        cross.addLine(to: CGPoint(x: center.x + centerRadiusX * 0.68, y: center.y))
        context.stroke(cross, with: .color(.white), lineWidth: max(0.65, size.width * 0.027))
    }

    private func drawBambooStick(at point: CGPoint, in context: inout GraphicsContext, size: CGSize, color: Color) {
        let halfWidth = (compact ? 1.15 : min(size.width * 0.09, 3.1)) * fullness
        let halfHeight = (compact ? 2.6 : min(size.height * 0.115, 6.8)) * fullness
        var shape = Path()
        shape.move(to: CGPoint(x: point.x, y: point.y - halfHeight))
        shape.addCurve(to: CGPoint(x: point.x + halfWidth * 0.72, y: point.y - halfHeight * 0.62), control1: CGPoint(x: point.x + halfWidth * 1.05, y: point.y - halfHeight * 0.96), control2: CGPoint(x: point.x + halfWidth * 0.82, y: point.y - halfHeight * 0.86))
        shape.addCurve(to: CGPoint(x: point.x + halfWidth * 0.48, y: point.y - halfHeight * 0.17), control1: CGPoint(x: point.x + halfWidth * 0.6, y: point.y - halfHeight * 0.42), control2: CGPoint(x: point.x + halfWidth * 0.48, y: point.y - halfHeight * 0.36))
        shape.addCurve(to: CGPoint(x: point.x + halfWidth * 0.48, y: point.y + halfHeight * 0.17), control1: CGPoint(x: point.x + halfWidth * 0.48, y: point.y - halfHeight * 0.06), control2: CGPoint(x: point.x + halfWidth * 0.48, y: point.y + halfHeight * 0.06))
        shape.addCurve(to: CGPoint(x: point.x + halfWidth * 0.72, y: point.y + halfHeight * 0.62), control1: CGPoint(x: point.x + halfWidth * 0.48, y: point.y + halfHeight * 0.36), control2: CGPoint(x: point.x + halfWidth * 0.6, y: point.y + halfHeight * 0.42))
        shape.addCurve(to: CGPoint(x: point.x, y: point.y + halfHeight), control1: CGPoint(x: point.x + halfWidth * 0.82, y: point.y + halfHeight * 0.86), control2: CGPoint(x: point.x + halfWidth * 1.05, y: point.y + halfHeight * 0.96))
        shape.addCurve(to: CGPoint(x: point.x - halfWidth * 0.72, y: point.y + halfHeight * 0.62), control1: CGPoint(x: point.x - halfWidth * 1.05, y: point.y + halfHeight * 0.96), control2: CGPoint(x: point.x - halfWidth * 0.82, y: point.y + halfHeight * 0.86))
        shape.addCurve(to: CGPoint(x: point.x - halfWidth * 0.48, y: point.y + halfHeight * 0.17), control1: CGPoint(x: point.x - halfWidth * 0.6, y: point.y + halfHeight * 0.42), control2: CGPoint(x: point.x - halfWidth * 0.48, y: point.y + halfHeight * 0.36))
        shape.addCurve(to: CGPoint(x: point.x - halfWidth * 0.48, y: point.y - halfHeight * 0.17), control1: CGPoint(x: point.x - halfWidth * 0.48, y: point.y + halfHeight * 0.06), control2: CGPoint(x: point.x - halfWidth * 0.48, y: point.y - halfHeight * 0.06))
        shape.addCurve(to: CGPoint(x: point.x - halfWidth * 0.72, y: point.y - halfHeight * 0.62), control1: CGPoint(x: point.x - halfWidth * 0.48, y: point.y - halfHeight * 0.36), control2: CGPoint(x: point.x - halfWidth * 0.6, y: point.y - halfHeight * 0.42))
        shape.addCurve(to: CGPoint(x: point.x, y: point.y - halfHeight), control1: CGPoint(x: point.x - halfWidth * 0.82, y: point.y - halfHeight * 0.86), control2: CGPoint(x: point.x - halfWidth * 1.05, y: point.y - halfHeight * 0.96))
        shape.closeSubpath()
        context.stroke(shape, with: .color(color), style: StrokeStyle(lineWidth: compact ? 0.9 : 1.75, lineJoin: .round))
        var node = Path()
        node.move(to: CGPoint(x: point.x - halfWidth * 0.48, y: point.y))
        node.addQuadCurve(to: CGPoint(x: point.x + halfWidth * 0.48, y: point.y), control: CGPoint(x: point.x, y: point.y + halfHeight * 0.035))
        context.stroke(node, with: .color(color.opacity(0.9)), lineWidth: compact ? 0.6 : 1.05)
    }

    private func drawEightBamboo(in context: inout GraphicsContext, size: CGSize) {
        let green = color(for: .green)
        for y in [CGFloat(0.23), 0.5, 0.77] {
            for x in [CGFloat(0.22), 0.78] {
                drawBambooStick(at: CGPoint(x: x * size.width, y: y * size.height), in: &context, size: size, color: green)
            }
        }
        drawBambooBridge(at: CGPoint(x: size.width * 0.5, y: size.height * 0.37), in: &context, size: size, inverted: false, color: green)
        drawBambooBridge(at: CGPoint(x: size.width * 0.5, y: size.height * 0.63), in: &context, size: size, inverted: true, color: green)
    }

    private func drawBambooBridge(at center: CGPoint, in context: inout GraphicsContext, size: CGSize, inverted: Bool, color: Color) {
        let direction: CGFloat = inverted ? -1 : 1
        let halfWidth = size.width * 28 / 104
        let halfHeight = size.height * 11 / 148
        var outer = Path()
        outer.move(to: CGPoint(x: center.x - halfWidth, y: center.y + direction * halfHeight))
        outer.addCurve(to: CGPoint(x: center.x - halfWidth * 0.58, y: center.y - direction * halfHeight), control1: CGPoint(x: center.x - halfWidth * 0.82, y: center.y + direction * halfHeight), control2: CGPoint(x: center.x - halfWidth * 0.78, y: center.y - direction * halfHeight))
        outer.addCurve(to: CGPoint(x: center.x - halfWidth * 0.2, y: center.y + direction * halfHeight * 0.72), control1: CGPoint(x: center.x - halfWidth * 0.38, y: center.y - direction * halfHeight), control2: CGPoint(x: center.x - halfWidth * 0.42, y: center.y + direction * halfHeight * 0.72))
        outer.addCurve(to: CGPoint(x: center.x, y: center.y - direction * halfHeight * 0.65), control1: CGPoint(x: center.x, y: center.y + direction * halfHeight * 0.72), control2: CGPoint(x: center.x - halfWidth * 0.05, y: center.y - direction * halfHeight * 0.65))
        outer.addCurve(to: CGPoint(x: center.x + halfWidth * 0.2, y: center.y + direction * halfHeight * 0.72), control1: CGPoint(x: center.x + halfWidth * 0.05, y: center.y - direction * halfHeight * 0.65), control2: CGPoint(x: center.x, y: center.y + direction * halfHeight * 0.72))
        outer.addCurve(to: CGPoint(x: center.x + halfWidth * 0.58, y: center.y - direction * halfHeight), control1: CGPoint(x: center.x + halfWidth * 0.42, y: center.y + direction * halfHeight * 0.72), control2: CGPoint(x: center.x + halfWidth * 0.38, y: center.y - direction * halfHeight))
        outer.addCurve(to: CGPoint(x: center.x + halfWidth, y: center.y + direction * halfHeight), control1: CGPoint(x: center.x + halfWidth * 0.78, y: center.y - direction * halfHeight), control2: CGPoint(x: center.x + halfWidth * 0.82, y: center.y + direction * halfHeight))
        context.stroke(outer, with: .color(color), style: StrokeStyle(lineWidth: compact ? 0.75 : 3.4 * size.width / 104, lineCap: .round, lineJoin: .round))

        var inner = Path()
        inner.move(to: CGPoint(x: center.x - halfWidth * 0.9, y: center.y + direction * halfHeight * 0.60))
        inner.addCurve(to: CGPoint(x: center.x - halfWidth * 0.57, y: center.y - direction * halfHeight * 0.56), control1: CGPoint(x: center.x - halfWidth * 0.75, y: center.y + direction * halfHeight * 0.60), control2: CGPoint(x: center.x - halfWidth * 0.70, y: center.y - direction * halfHeight * 0.56))
        inner.addCurve(to: CGPoint(x: center.x - halfWidth * 0.2, y: center.y + direction * halfHeight * 0.43), control1: CGPoint(x: center.x - halfWidth * 0.42, y: center.y - direction * halfHeight * 0.56), control2: CGPoint(x: center.x - halfWidth * 0.34, y: center.y + direction * halfHeight * 0.43))
        inner.addCurve(to: CGPoint(x: center.x, y: center.y - direction * halfHeight * 0.25), control1: CGPoint(x: center.x - halfWidth * 0.07, y: center.y + direction * halfHeight * 0.43), control2: CGPoint(x: center.x - halfWidth * 0.08, y: center.y - direction * halfHeight * 0.25))
        inner.addCurve(to: CGPoint(x: center.x + halfWidth * 0.2, y: center.y + direction * halfHeight * 0.43), control1: CGPoint(x: center.x + halfWidth * 0.08, y: center.y - direction * halfHeight * 0.25), control2: CGPoint(x: center.x + halfWidth * 0.07, y: center.y + direction * halfHeight * 0.43))
        inner.addCurve(to: CGPoint(x: center.x + halfWidth * 0.57, y: center.y - direction * halfHeight * 0.56), control1: CGPoint(x: center.x + halfWidth * 0.34, y: center.y + direction * halfHeight * 0.43), control2: CGPoint(x: center.x + halfWidth * 0.42, y: center.y - direction * halfHeight * 0.56))
        inner.addCurve(to: CGPoint(x: center.x + halfWidth * 0.9, y: center.y + direction * halfHeight * 0.60), control1: CGPoint(x: center.x + halfWidth * 0.70, y: center.y - direction * halfHeight * 0.56), control2: CGPoint(x: center.x + halfWidth * 0.75, y: center.y + direction * halfHeight * 0.60))
        context.stroke(inner, with: .color(color), style: StrokeStyle(lineWidth: compact ? 0.58 : 2.2 * size.width / 104, lineCap: .round, lineJoin: .round))
    }

    private func drawBird(in context: inout GraphicsContext, size: CGSize) {
        let green = color(for: .green), blue = color(for: .blue), red = color(for: .red)
        let sx = size.width / 104, sy = size.height / 148
        let line = min(sx, sy)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * sx, y: y * sy)
        }
        var branch = Path()
        branch.move(to: point(18, 116))
        branch.addQuadCurve(to: point(61, 65), control: point(35, 86))
        branch.move(to: point(27, 105))
        branch.addQuadCurve(to: point(17, 81), control: point(14, 92))
        context.stroke(branch, with: .color(green), style: StrokeStyle(lineWidth: 3.5 * line, lineCap: .round))

        var body = Path()
        body.move(to: point(28, 84))
        body.addCurve(to: point(57, 69), control1: point(34, 72), control2: point(44, 65))
        body.addCurve(to: point(70, 97), control1: point(70, 73), control2: point(76, 85))
        body.addCurve(to: point(30, 101), control1: point(63, 112), control2: point(44, 113))
        body.closeSubpath()
        context.fill(body, with: .color(.white))
        context.stroke(body, with: .color(blue), style: StrokeStyle(lineWidth: 3.5 * line, lineJoin: .round))

        let head = CGRect(x: 50 * sx, y: 46 * sy, width: 30 * sx, height: 30 * sy)
        context.fill(Path(ellipseIn: head), with: .color(.white))
        context.stroke(Path(ellipseIn: head), with: .color(blue), lineWidth: 3.5 * line)
        var comb = Path()
        comb.move(to: point(54, 49))
        comb.addQuadCurve(to: point(59, 40), control: point(53, 37))
        comb.addQuadCurve(to: point(64, 44), control: point(63, 31))
        comb.addQuadCurve(to: point(71, 40), control: point(73, 31))
        comb.addQuadCurve(to: point(69, 50), control: point(77, 42))
        context.stroke(comb, with: .color(red), style: StrokeStyle(lineWidth: 4.5 * line, lineCap: .round, lineJoin: .round))

        var beak = Path()
        beak.move(to: point(77, 59))
        beak.addLine(to: point(93, 65))
        beak.addLine(to: point(77, 71))
        beak.closeSubpath()
        context.fill(beak, with: .color(red))
        let eye = CGRect(x: 67 * sx, y: 55 * sy, width: 4.8 * sx, height: 4.8 * sy)
        context.fill(Path(ellipseIn: eye), with: .color(blue))

        var wing = Path()
        wing.move(to: point(37, 78))
        wing.addQuadCurve(to: point(71, 81), control: point(53, 67))
        wing.addQuadCurve(to: point(39, 98), control: point(57, 97))
        wing.closeSubpath()
        context.stroke(wing, with: .color(blue), style: StrokeStyle(lineWidth: 3 * line, lineCap: .round, lineJoin: .round))

        var tail = Path()
        tail.move(to: point(34, 102))
        tail.addQuadCurve(to: point(54, 131), control: point(48, 116))
        context.stroke(tail, with: .color(red), style: StrokeStyle(lineWidth: 4.2 * line, lineCap: .round))
    }

    private func drawWhiteDragon(in context: inout GraphicsContext, size: CGSize) {
        let blue = color(for: .blue)
        let outer = CGRect(x: size.width * 0.17, y: size.height * 0.12, width: size.width * 0.66, height: size.height * 0.76)
        let inner = outer.insetBy(dx: compact ? 2 : 4, dy: compact ? 2 : 4)
        context.stroke(Path(roundedRect: outer, cornerRadius: compact ? 1 : 3), with: .color(blue), lineWidth: compact ? 1 : 2)
        context.stroke(Path(roundedRect: inner, cornerRadius: compact ? 1 : 2), with: .color(blue.opacity(0.78)), lineWidth: compact ? 0.7 : 1.25)
    }

    private struct Pip {
        let x: CGFloat
        let y: CGFloat
        let ink: MahjongTileInk
    }

    private func dotPattern(_ rank: Int) -> [Pip] {
        func p(_ x: CGFloat, _ y: CGFloat, _ ink: MahjongTileInk) -> Pip {
            Pip(x: x, y: y, ink: ink)
        }
        switch rank {
        case 2: return [p(0.5, 0.32, .blue), p(0.5, 0.68, .green)]
        case 3: return [p(0.27, 0.25, .blue), p(0.5, 0.5, .red), p(0.73, 0.75, .green)]
        case 4: return [p(0.29, 0.29, .green), p(0.71, 0.29, .blue), p(0.29, 0.71, .blue), p(0.71, 0.71, .green)]
        case 5: return [p(0.29, 0.27, .green), p(0.71, 0.27, .blue), p(0.5, 0.5, .red), p(0.29, 0.73, .blue), p(0.71, 0.73, .green)]
        case 6: return [p(0.3, 0.24, .green), p(0.7, 0.24, .green), p(0.3, 0.5, .red), p(0.7, 0.5, .red), p(0.3, 0.76, .red), p(0.7, 0.76, .red)]
        case 7: return [p(0.25, 0.22, .green), p(0.5, 0.34, .green), p(0.75, 0.46, .green), p(0.3, 0.64, .red), p(0.7, 0.64, .red), p(0.3, 0.82, .red), p(0.7, 0.82, .red)]
        case 8: return [p(0.3, 0.16, .blue), p(0.7, 0.16, .blue), p(0.3, 0.39, .blue), p(0.7, 0.39, .blue), p(0.3, 0.61, .blue), p(0.7, 0.61, .blue), p(0.3, 0.84, .blue), p(0.7, 0.84, .blue)]
        default: return [p(0.23, 0.23, .blue), p(0.5, 0.23, .blue), p(0.77, 0.23, .blue), p(0.23, 0.5, .red), p(0.5, 0.5, .red), p(0.77, 0.5, .red), p(0.23, 0.77, .green), p(0.5, 0.77, .green), p(0.77, 0.77, .green)]
        }
    }

    private func bambooPattern(_ rank: Int) -> [Pip] {
        func p(_ x: CGFloat, _ y: CGFloat, _ ink: MahjongTileInk = .green) -> Pip {
            Pip(x: x, y: y, ink: ink)
        }
        switch rank {
        case 2: return [p(0.5, 0.32), p(0.5, 0.68)]
        case 3: return [p(0.5, 0.26), p(0.28, 0.72), p(0.72, 0.72)]
        case 4: return [p(0.3, 0.34), p(0.7, 0.34), p(0.3, 0.66), p(0.7, 0.66)]
        case 5: return [p(0.28, 0.28), p(0.72, 0.28), p(0.5, 0.5, .red), p(0.28, 0.72), p(0.72, 0.72)]
        case 6: return [p(0.25, 0.3), p(0.5, 0.3), p(0.75, 0.3), p(0.25, 0.7), p(0.5, 0.7), p(0.75, 0.7)]
        case 7: return [p(0.5, 0.18, .red), p(0.25, 0.46), p(0.5, 0.46, .blue), p(0.75, 0.46), p(0.25, 0.76), p(0.5, 0.76, .blue), p(0.75, 0.76)]
        case 8: return []
        default: return [p(0.25, 0.22), p(0.5, 0.22, .red), p(0.75, 0.22), p(0.25, 0.5), p(0.5, 0.5, .red), p(0.75, 0.5), p(0.25, 0.78), p(0.5, 0.78, .red), p(0.75, 0.78)]
        }
    }
}

struct MahjongLANRoomView: View {
    let localProfile: MahjongPlayerArchive
    let ruleset: MahjongRuleset
    let onStart: (MahjongLANRoomService) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = MahjongLANRoomService()
    @State private var roomCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("欢乐麻将联机")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("与同一 Wi‑Fi 下的朋友一起玩")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") { service.startBrowsing() }
                    .buttonStyle(.plain)
                Button("关闭") {
                    service.stop()
                    dismiss()
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                TextField("输入六位匹配码", text: $roomCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .onChange(of: roomCode) { _, value in
                        roomCode = String(value.filter(\.isNumber).prefix(6))
                    }
                Button("加入对局") {
                    service.joinRoom(code: roomCode, profile: localProfile)
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(roomCode.count != 6 || service.isConnecting)
                Spacer()
                if !service.isHosting {
                    Button("创建房间") { service.createRoom(profile: localProfile, ruleset: ruleset) }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                }
            }

            if service.isHosting, let code = service.roomCode {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("房间已创建 · 匹配码")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(code)
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                            .tracking(5)
                    }
                    Spacer()
                    Button("进入牌桌") { onStart(service) }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                }
                .padding(16)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            }

            HStack {
                Text("可加入的房间")
                    .font(JarvisTypography.controlEmphasis)
                Spacer()
                Text(service.status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    if service.rooms.isEmpty {
                        ContentUnavailableView("还没有发现房间", systemImage: "wifi", description: Text("创建房间后会自动出现在同一局域网的列表中，也可以输入匹配码加入。"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(service.rooms) { room in
                            Button {
                                roomCode = room.code
                                service.joinRoom(code: room.code, profile: localProfile)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(room.displayName)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("匹配码：\(room.code)")
                                            .font(.system(size: 12, design: .rounded).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("加入")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.jarvisAccent)
                                }
                                .padding(13)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
        .padding(26)
        .onAppear {
            service.startBrowsing()
        }
        .onChange(of: service.connected) { _, connected in
            guard connected, !service.isHosting else { return }
            onStart(service)
        }
    }
}
