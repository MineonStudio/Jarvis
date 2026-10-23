import SwiftUI

struct MahjongTurnRing: View {
    let deadline: Date?
    let duration: TimeInterval

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let remaining = deadline?.timeIntervalSince(context.date) ?? 0
            let progress = min(max(remaining / max(duration, 0.001), 0), 1)
            MahjongCountdownArc(progress: progress)
        }
        .accessibilityHidden(true)
    }
}

struct MahjongTurnCompass: View {
    /// Wind character for each view. 0 is the bottom (local), then left, top, right.
    let winds: [String]
    let seatName: String
    let viewPosition: Int?
    let deadline: Date?
    let counting: Bool
    let countdownDuration: TimeInterval

    private let plate: CGFloat = 108
    private let activeFill = Color.white.opacity(0.18)

    var body: some View {
        ZStack {
            plateBody
            Circle()
                .fill(.white.opacity(0.06))
                .overlay {
                    if counting, let deadline {
                        MahjongTurnRing(deadline: deadline, duration: countdownDuration)
                            .padding(4)
                    }
                }
                .overlay {
                    if counting {
                        TimelineView(.periodic(from: .now, by: 0.2)) { context in
                            let remaining = deadline?.timeIntervalSince(context.date) ?? 0
                            Text("\(max(0, Int(ceil(remaining))))")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(MahjongVisualTheme.ivory)
                                .monospacedDigit()
                        }
                    }
                }
                .frame(width: 52, height: 52)
        }
        .frame(width: plate, height: plate)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .position(MahjongOverheadMetrics.compass)
        .animation(.easeInOut(duration: 0.25), value: viewPosition)
        .allowsHitTesting(false)
        .accessibilityLabel(counting ? "\(seatName) 倒计时" : (viewPosition == nil ? "方位指示器" : "\(seatName) 当前"))
    }

    private var plateBody: some View {
        let wedges: [(view: Int, a: UnitPoint, b: UnitPoint)] = [
            (2, .topLeading, .topTrailing),
            (3, .topTrailing, .bottomTrailing),
            (0, .bottomTrailing, .bottomLeading),
            (1, .bottomLeading, .topLeading)
        ]
        return ZStack {
            ZStack {
                ForEach(wedges, id: \.view) { wedge in
                    CompassWedge(a: wedge.a, b: wedge.b)
                        .fill(wedge.view == viewPosition ? activeFill : .clear)
                }
            }
            .mask(CompassOuterRegion().fill(style: FillStyle(eoFill: true)))
            DiagonalSeam()
                .stroke(.white.opacity(0.12), lineWidth: 1)
            windMarks
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var windMarks: some View {
        ZStack {
            wind(2).offset(y: -39)
            wind(3).offset(x: 39)
            wind(0).offset(y: 39)
            wind(1).offset(x: -39)
        }
    }

    private func wind(_ view: Int) -> some View {
        Text(winds.indices.contains(view) ? winds[view] : "")
            .font(.custom("Kaiti SC", size: 15))
            .foregroundStyle(
                view == viewPosition
                    ? MahjongVisualTheme.accent
                    : MahjongVisualTheme.ivory.opacity(0.85)
            )
    }
}

/// One corner of the direction square. The two outer corners and the center form the triangle.
struct CompassWedge: Shape {
    var a: UnitPoint
    var b: UnitPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + a.x * rect.width, y: rect.minY + a.y * rect.height))
        path.addLine(to: CGPoint(x: rect.minX + b.x * rect.width, y: rect.minY + b.y * rect.height))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct DiagonalSeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        for corner in corners {
            let dx = corner.x - center.x
            let dy = corner.y - center.y
            let distance = hypot(dx, dy)
            guard distance > 32 else { continue }
            path.move(to: corner)
            path.addLine(to: CGPoint(x: center.x + dx / distance * 32, y: center.y + dy / distance * 32))
        }
        return path
    }
}

struct CompassOuterRegion: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: rect.midX - 32, y: rect.midY - 32, width: 64, height: 64))
        return path
    }
}

struct MahjongActionTray: View {
    let game: MahjongGame

    var body: some View {
        if actionsVisible {
            tray
        }
    }

    private var actionsVisible: Bool {
        switch game.phase {
        case .choosingMissingSuit:
            game.currentResponderSeat == game.localSeat
        case .responding:
            !game.humanResponseOptions.isEmpty
        case .playing where game.isHumanTurn:
            game.canSelfDraw || !game.availableKongTiles.isEmpty
        default:
            false
        }
    }

    @ViewBuilder
    private var tray: some View {
        switch game.phase {
        case .choosingMissingSuit where game.currentResponderSeat == game.localSeat:
            HStack(spacing: 8) {
                ForEach(MahjongSuit.allCases, id: \.self) { suit in
                    Button(suit.shortName) { game.chooseMissingSuit(suit) }
                        .buttonStyle(MahjongGameButtonStyle())
                }
            }
        case .responding:
            HStack(spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(game.humanResponseOptions.filter { $0.kind != .pass }) { option in
                            Button(callTitle(option)) { game.respond(to: option) }
                                .buttonStyle(MahjongGameButtonStyle(kind: option.kind == .win ? .primary : .secondary))
                        }
                    }
                }
                .scrollIndicators(.automatic)
                Button("过") { game.respond(to: MahjongCallOption(kind: .pass, heldTiles: [])) }
                    .buttonStyle(MahjongGameButtonStyle())
            }
        case .playing where game.isHumanTurn && (game.canSelfDraw || !game.availableKongTiles.isEmpty):
            HStack(spacing: 8) {
                if game.canSelfDraw {
                    Button("自摸") { game.claimSelfDraw() }
                        .buttonStyle(MahjongGameButtonStyle(kind: .primary))
                }
                ForEach(game.availableKongTiles) { tile in
                    Button("杠 \(tile.accessibilityName)") { game.declareKong(tile) }
                        .buttonStyle(MahjongGameButtonStyle())
                }
            }
        default:
            EmptyView()
        }
    }

    private func callTitle(_ option: MahjongCallOption) -> String {
        guard !option.heldTiles.isEmpty else { return option.kind.rawValue }
        let names = option.heldTiles.map(\.accessibilityName).joined(separator: " ")
        return "\(option.kind.rawValue) \(names)"
    }
}

struct MahjongMultiplierCeremony: View {
    let game: MahjongGame

    @State private var submittedValue: Int?

    private var localChoice: Int? {
        game.multipliers[game.localSeat] ?? submittedValue
    }

    var body: some View {
        ZStack {
            ForEach(0 ..< 4, id: \.self) { view in
                let seat = (game.localSeat + view) % 4
                let choice = game.multipliers[seat] ?? (view == 0 ? submittedValue : nil)
                if let choice {
                    announcement(for: seat, choice: choice)
                        .position(announcementPosition(for: view))
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .allowsHitTesting(false)
                }
            }
            if localChoice == nil, !game.localMultiplierOptions.isEmpty {
                choiceTray
                    .position(x: 640, y: 625)
            }
        }
        .frame(width: MahjongOverheadMetrics.canvas.width, height: MahjongOverheadMetrics.canvas.height)
        .animation(.easeOut(duration: 0.25), value: game.multipliers)
        .animation(.easeOut(duration: 0.25), value: submittedValue)
        .onChange(of: game.multiplierDeadline) { _, _ in submittedValue = nil }
    }

    private func announcement(for seat: Int, choice: Int) -> some View {
        HStack(spacing: 7) {
            Text(game.seatName(seat))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MahjongVisualTheme.muted)
            Text(choice == 1 ? "不加倍" : "加倍 ×\(choice)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(MahjongVisualTheme.accent)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .accessibilityLabel("\(game.seatName(seat))\(choice == 1 ? "不加倍" : "加倍 \(choice) 倍")")
    }

    private func announcementPosition(for view: Int) -> CGPoint {
        switch view {
        case 0: CGPoint(x: 640, y: 744)
        case 1: CGPoint(x: 315, y: 488)
        case 2: CGPoint(x: 640, y: 235)
        default: CGPoint(x: 965, y: 488)
        }
    }

    private var choiceTray: some View {
        VStack(spacing: 10) {
            Text("请选择本局倍数")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MahjongVisualTheme.ivory)
                .shadow(color: .black.opacity(0.6), radius: 3)
            HStack(spacing: 10) {
                ForEach(game.localMultiplierOptions, id: \.self) { value in
                    Button(value == 1 ? "不加倍" : "加倍 ×\(value)") {
                        submittedValue = value
                        game.chooseMultiplier(value)
                    }
                    .buttonStyle(MahjongGameButtonStyle(kind: value == 1 ? .secondary : .primary))
                }
            }
            Text("超时默认不加倍")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MahjongVisualTheme.muted)
                .shadow(color: .black.opacity(0.6), radius: 3)
        }
    }
}
