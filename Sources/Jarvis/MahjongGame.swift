import Foundation
import Observation

enum MahjongSuit: String, CaseIterable, Codable, Hashable {
    case characters
    case dots
    case bamboo

    var shortName: String {
        switch self {
        case .characters: "万"
        case .dots: "筒"
        case .bamboo: "条"
        }
    }
}

enum MahjongTile: Hashable, Codable, Identifiable {
    case suited(MahjongSuit, Int)
    case honor(Int) // east, south, west, north, red, green, white

    var id: String {
        switch self {
        case let .suited(suit, value): "\(suit.rawValue)-\(value)"
        case let .honor(value): "honor-\(value)"
        }
    }

    var sortKey: Int {
        switch self {
        case let .suited(suit, value):
            let suitIndex = MahjongSuit.allCases.firstIndex(of: suit) ?? 0
            return suitIndex * 10 + value
        case let .honor(value): return 40 + value
        }
    }

    var accessibilityName: String {
        let chineseNumerals = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return switch self {
        case let .suited(.characters, value): "\(chineseNumerals[value])萬"
        case let .suited(.dots, value): "\(chineseNumerals[value])筒"
        case let .suited(.bamboo, value): "\(chineseNumerals[value])條"
        case let .honor(value): ["東風", "南風", "西風", "北風", "紅中", "發財", "白板"][value]
        }
    }

    var aiName: String {
        accessibilityName
            .replacingOccurrences(of: "萬", with: "万")
            .replacingOccurrences(of: "條", with: "条")
            .replacingOccurrences(of: "東", with: "东")
            .replacingOccurrences(of: "紅", with: "红")
            .replacingOccurrences(of: "發", with: "发")
    }
}

struct MahjongVoiceCue: Codable, Identifiable, Equatable {
    var id = UUID()
    let seat: Int
    let key: String
}

enum MahjongTileInk {
    case red, blue, green, emerald
}

enum MahjongRuleset: String, CaseIterable, Identifiable, Codable {
    case national = "国标麻将 · 标准和牌"
    case sichuan = "四川麻将 · 定缺"
    case cantonese = "广东麻将 · 推倒胡"

    var id: String {
        rawValue
    }

    var detail: String {
        switch self {
        case .national:
            "## 🎯 核心规则：四组面子加一对将\n\n国标麻将使用万、筒、条和东南西北、中发白共一百三十六张牌。和牌的基础结构通常是四组面子加一对将牌：面子可以是同花色的连续三张组成的顺子，也可以是三张相同牌组成的刻子；将牌是两张相同的牌。\n\n### 🀄 起手与回合\n\n* 庄家起手十四张，其余玩家各十三张；庄家先打出一张开始对局。\n* 四家按逆时针顺序行动。轮到自己时，从牌墙摸一张，再从手牌中打出一张。\n* 别人打出的牌可以被响应：下一家可以吃，任意一家可以碰或明杠；满足和牌牌型时可以胡牌。若无人响应，则由下一家摸牌。\n\n### 🔁 吃、碰、杠怎么组成\n\n* **吃**：用上家打出的牌和手中的两张牌组成同花色、连续的三张，例如二万、三万、四万。\n* **碰**：手中有两张相同牌时，可以拿别人打出的第三张组成刻子。\n* **明杠**：手中已有三张相同牌时，拿别人打出的第四张组成杠；已碰出的刻子摸到第四张时也可以补杠。\n* **暗杠**：自己手中有四张相同牌时可以暗杠。杠后从牌墙补摸一张；吃、碰、明杠公开展示，暗杠保留暗牌。\n\n### ✅ 胡牌条件与例子\n\n常见牌型是“顺子 / 刻子 × 四组 + 将牌 × 一对”。例如：一二三万、四五六万、七八九条、三个东风，再加一对五筒。也支持七对和十三幺。胡牌可以来自自己摸牌，也可以来自其他玩家打出的牌。\n\n### ⚠️ 计分说明\n\n本版本采用简化竞赛计分：普通胡牌按 8 分、七对 24 分、十三幺 88 分；点炮时三家各付 8 分基础分，点炮者另付牌型分；自摸时三家各付基础分与牌型分。暂未计算完整的 81 种番种与起和门槛。\n\n### 🏁 本局结束\n\n有人胡牌后本局结束并展示各家手牌；牌墙摸完仍无人胡牌时流局。"
        case .sichuan:
            "## 🎯 核心规则：缺一门才能胡\n\n四川麻将“缺一门”的核心是：胡牌时，手牌只能保留万、筒、条中的两种花色，不能三门都在手里。开局每位玩家都要从三种花色中选一门作为自己的缺门，这一步叫**定缺**。通常会选张数较少、搭子较散，或较难继续组成顺子的花色。\n\n### 🀄 定缺与打缺\n\n* **定缺**：发牌后选择万、筒、条中的一门作为本局缺门。选定后不能更换。\n* **打缺**：手牌还留有缺门牌时，出牌必须优先打出缺门牌；自己摸到缺门牌时也要继续清理。缺门牌打完后，才可以自由选择其他牌。\n* **限制响应**：手中仍有缺门牌时，不能用别人打出的牌组成副露；缺门牌不能被吃、碰或杠进手牌。清空缺门后才恢复通常的吃碰杠选择。\n\n### ✅ 胡牌硬性条件\n\n胡牌时必须同时满足两件事：手牌中已经没有定缺花色，并且牌型符合和牌结构。基础牌型是四组顺子或刻子加一对将牌，也支持七对。满足牌型但仍留有缺门牌，不能胡牌。既可以自摸，也可以和其他玩家打出的牌。\n\n### 💡 一个简单的例子\n\n假设你定缺“筒”。接下来的出牌阶段要先把手里的筒子全部打掉；摸到筒子时继续打筒，手里还有筒时不能用别人的牌吃、碰、杠。清空筒子后，如果手牌只剩万和条，并组成“一二三万、四五六万、七八九条、三个八条、一对九条”，就满足基础和牌牌型。\n\n### ⚠️ 流局时的查花猪\n\n如果牌墙摸完仍无人胡牌，结算时检查各家手牌：仍保留万、筒、条三种花色的玩家称为“花猪”，通常需要向其他玩家赔付。本版本按定缺和牌条件限制出牌、响应与胡牌，输赢统一采用简化竞赛计分；尚未实现流局查花猪赔分、换三张、刮风下雨计分和血战到底结算。\n\n### 🏁 本局结束\n\n当前版本任意一位玩家胡牌后即结束本局并展示手牌；牌墙耗尽则流局。四川麻将常见的“血战到底”会在有人胡牌后继续让其他玩家争胜，本版本暂未实现该流程。"
        case .cantonese:
            "## 🎯 核心规则：推倒胡，成牌即可胡\n\n广东推倒胡通常使用万、筒、条和东南西北、中发白，共一百三十六张牌。这里采用易上手的基础推倒胡规则：牌型满足和牌结构即可胡，不要求先凑够复杂番种或最低番数。\n\n### 🀄 起手与回合\n\n* 庄家起手十四张，其余三家各十三张；庄家先打出一张，之后按逆时针轮流行动。\n* 每回合摸一张、打一张。上家打出的牌可以被吃，任意一家打出的牌可以被碰或明杠；达到和牌条件时可以胡牌。\n* 没有人响应弃牌时，由下一家摸牌。有人响应时，优先处理胡牌，再处理杠、碰、吃。\n\n### 🔁 吃、碰、杠\n\n* **吃**：用上家的一张弃牌和手中的两张同花色序数牌组成连续顺子。\n* **碰**：手里有两张相同牌时，用别人的弃牌组成三张相同的刻子。\n* **明杠**：手中已有三张相同牌时接入弃牌，或将已碰的刻子补成四张。\n* **暗杠**：自己摸到四张相同牌时可以暗杠。杠后从牌墙补摸一张；公开副露会展示吃、碰和明杠，暗杠保留暗牌。\n\n### ✅ 和牌牌型与示例\n\n常规牌型为四组顺子或刻子加一对将牌；也支持七对与十三幺。比如“一二三万、四五六万、七八九条、三个东风、一对五筒”即可组成常规牌型。自摸和点和都可胡；达到牌型即可和牌，不设置最低番数门槛。\n\n### ⚠️ 玩法范围说明\n\n“广东麻将”各地规则差异较大。本版本采用简化推倒胡：暂不含花牌、买马、鸡平胡 / 新章等地区计番差异，输赢统一采用简化竞赛计分，不计算完整的地方番种与台数。\n\n### 🏁 本局结束\n\n有人和牌后本局结束并展示四家手牌；牌墙耗尽仍无人和牌时流局。"
        }
    }

    var includesHonors: Bool {
        self != .sichuan
    }
}

enum MahjongPlayMode: String, CaseIterable, Identifiable, Codable {
    case solo = "单人对战"
    case lan = "局域网"

    var id: String {
        rawValue
    }
}

enum MahjongRoundPhase: Equatable, Codable {
    case idle
    case waitingForReady
    case dealing
    case choosingMissingSuit
    case playing
    case responding
    case roundEnded
}

enum MahjongMeldKind: String, Codable {
    case sequence = "吃"
    case triplet = "碰"
    case exposedKong = "明杠"
    case concealedKong = "暗杠"
    case addedKong = "补杠"
}

struct MahjongMeld: Identifiable, Codable {
    var id = UUID()
    var kind: MahjongMeldKind
    var tiles: [MahjongTile]

    var label: String {
        "\(kind.rawValue) \(tiles.sorted { $0.sortKey < $1.sortKey }.map(\.accessibilityName).joined(separator: "、"))"
    }
}

enum MahjongCallKind: String, CaseIterable, Codable {
    case win = "胡"
    case exposedKong = "杠"
    case pong = "碰"
    case chi = "吃"
    case pass = "过"

    var priority: Int {
        switch self {
        case .win: 4
        case .exposedKong, .pong: 3
        case .chi: 2
        case .pass: 0
        }
    }
}

struct MahjongCallOption: Identifiable, Equatable, Codable {
    let kind: MahjongCallKind
    let heldTiles: [MahjongTile]

    var id: String {
        "\(kind.rawValue)-\(heldTiles.map(\.id).sorted().joined(separator: "-"))"
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

private enum MahjongAIDecision {
    case discard(MahjongTile)
    case kong(MahjongTile)
}

private enum MahjongAIOutputFormat {
    case tileName
    case optionIndex
}

private final class MahjongAIRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private var isResolved = false

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    @discardableResult
    func resolve(_ value: String?) -> Bool {
        lock.lock()
        guard !isResolved else {
            lock.unlock()
            return false
        }
        isResolved = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
        return true
    }
}

@MainActor
@Observable
final class MahjongGame {
    private(set) var hands: [[MahjongTile]] = []
    private(set) var melds: [[MahjongMeld]] = Array(repeating: [], count: 4)
    private(set) var discards: [[MahjongTile]] = Array(repeating: [], count: 4)
    private(set) var wall: [MahjongTile] = []
    private(set) var turn = 0
    private(set) var dealer = 0
    private(set) var roundNumber = 1
    private(set) var roundStartedAt: Date?
    private(set) var roundEndedAt: Date?
    private(set) var dice: [Int] = []
    private(set) var dealtCount = 0
    private(set) var justDrew = false
    private var needsDiscard = false
    private(set) var message = "选择玩法并开始一局"
    private(set) var winner: Int?
    private(set) var discarder: Int?
    private(set) var winningTile: MahjongTile?
    private(set) var winningHandType: MahjongWinningHandType = .standard
    private(set) var aiProfileIDs: [String] = ["", "", ""]
    private(set) var winByDiscard = false
    private(set) var isStarted = false
    private(set) var phase: MahjongRoundPhase = .idle
    private(set) var readySeats: [Bool] = Array(repeating: false, count: 4)
    private(set) var missingSuits: [MahjongSuit?] = Array(repeating: nil, count: 4)
    private(set) var roundResult = ""
    private(set) var turnSecondsRemaining: Int?
    private(set) var turnTimerSeat: Int?
    private(set) var responseCountdowns: [Int: Int] = [:]
    private(set) var turnCountdownDeadline: Date?
    private(set) var responseCountdownDeadlines: [Int: Date] = [:]
    var mode: MahjongPlayMode = .solo
    var ruleset: MahjongRuleset = .national
    private(set) var humanSeats = [0]
    private(set) var localSeat = 0
    private(set) var isLANAuthority = true
    private(set) var seatNicknames = ["玩家", "局域网玩家", "AI", "AI"]
    var onLANAction: ((MahjongLANAction) -> Void)?
    var onMahjongVoiceCue: ((MahjongVoiceCue) -> Void)?
    private var applyingRemoteAction = false
    private var remoteActionSeat: Int?

    func configureLAN(humanSeats: [Int], localSeat: Int, authority: Bool) {
        self.humanSeats = Array(Set(humanSeats.filter { (0 ..< 4).contains($0) })).sorted()
        self.localSeat = localSeat
        isLANAuthority = authority
    }

    func setLANNickname(_ nickname: String, for seat: Int) {
        guard seatNicknames.indices.contains(seat) else { return }
        seatNicknames[seat] = String(nickname.prefix(16))
    }

    private func announceVoice(_ key: String, for seat: Int) {
        let cue = MahjongVoiceCue(seat: seat, key: key)
        onMahjongVoiceCue?(cue)
    }

    func makeLANSnapshot() -> MahjongGameSnapshot {
        MahjongGameSnapshot(
            mode: mode, ruleset: ruleset, seatNicknames: seatNicknames,
            hands: hands, melds: melds, discards: discards, wall: wall, turn: turn, dealer: dealer,
            roundNumber: roundNumber, roundStartedAt: roundStartedAt, roundEndedAt: roundEndedAt,
            humanSeats: humanSeats, dice: dice, dealtCount: dealtCount,
            justDrew: justDrew, needsDiscard: needsDiscard, message: message, winner: winner,
            discarder: discarder, winningTile: winningTile, winningHandType: winningHandType,
            aiProfileIDs: aiProfileIDs, winByDiscard: winByDiscard, isStarted: isStarted, phase: phase,
            readySeats: readySeats, missingSuits: missingSuits, roundResult: roundResult,
            turnSecondsRemaining: turnSecondsRemaining, turnTimerSeat: turnTimerSeat,
            responseCountdowns: responseCountdowns, turnCountdownDeadline: turnCountdownDeadline,
            responseCountdownDeadlines: responseCountdownDeadlines, pendingTile: pendingTile,
            pendingDiscarder: pendingDiscarder, pendingHumanSeats: pendingHumanSeats,
            pendingOptions: pendingOptions, chosenResponses: chosenResponses, pendingAISeats: Array(pendingAISeats),
            preservedTurnDeadline: preservedTurnDeadline
        )
    }

    func applyLANSnapshot(_ snapshot: MahjongGameSnapshot) {
        guard !isLANAuthority else { return }
        mode = snapshot.mode; ruleset = snapshot.ruleset; seatNicknames = snapshot.seatNicknames
        hands = snapshot.hands; melds = snapshot.melds; discards = snapshot.discards; wall = snapshot.wall
        turn = snapshot.turn; dealer = snapshot.dealer; roundNumber = snapshot.roundNumber
        roundStartedAt = snapshot.roundStartedAt; roundEndedAt = snapshot.roundEndedAt
        humanSeats = snapshot.humanSeats; dice = snapshot.dice; dealtCount = snapshot.dealtCount
        justDrew = snapshot.justDrew; needsDiscard = snapshot.needsDiscard; message = snapshot.message
        winner = snapshot.winner; discarder = snapshot.discarder; winningTile = snapshot.winningTile
        winningHandType = snapshot.winningHandType; aiProfileIDs = snapshot.aiProfileIDs
        winByDiscard = snapshot.winByDiscard; isStarted = snapshot.isStarted; phase = snapshot.phase
        readySeats = snapshot.readySeats; missingSuits = snapshot.missingSuits; roundResult = snapshot.roundResult
        turnSecondsRemaining = snapshot.turnSecondsRemaining; turnTimerSeat = snapshot.turnTimerSeat
        responseCountdowns = snapshot.responseCountdowns; turnCountdownDeadline = snapshot.turnCountdownDeadline
        responseCountdownDeadlines = snapshot.responseCountdownDeadlines; pendingTile = snapshot.pendingTile
        pendingDiscarder = snapshot.pendingDiscarder; pendingHumanSeats = snapshot.pendingHumanSeats
        pendingOptions = snapshot.pendingOptions; chosenResponses = snapshot.chosenResponses
        pendingAISeats = Set(snapshot.pendingAISeats); preservedTurnDeadline = snapshot.preservedTurnDeadline
    }

    func performRemoteAction(_ action: MahjongLANAction, seat: Int) {
        guard isLANAuthority, humanSeats.contains(seat) else { return }
        remoteActionSeat = seat
        applyingRemoteAction = true
        defer {
            applyingRemoteAction = false
            remoteActionSeat = nil
        }
        switch action {
        case .start: start()
        case .ready: markReady()
        case let .missingSuit(suit): chooseMissingSuit(suit)
        case let .discard(tile, drawnTile): discard(tile, drawnTile: drawnTile)
        case .discardDrawn: discardDrawnTile()
        case let .respond(option): respond(to: option)
        case .selfDraw: claimSelfDraw()
        case let .kong(tile): declareKong(tile)
        case .nextRound: nextRound()
        case .leave: break
        }
    }

    func assignAIProfiles(_ profileIDs: [String]) {
        aiProfileIDs = Array(profileIDs.prefix(3)) + Array(repeating: "", count: max(0, 3 - profileIDs.count))
    }

    func declareCampaignComplete() {
        roundResult = "七位 AI 对手均已破产 · 挑战胜利！"
        message = roundResult
    }

    private var pendingTile: MahjongTile?
    private var pendingDiscarder: Int?
    private var pendingHumanSeats: [Int] = []
    private var pendingOptions: [Int: [MahjongCallOption]] = [:]
    private var chosenResponses: [Int: MahjongCallOption] = [:]
    private var pendingAISeats: Set<Int> = []
    private var pendingAIStarted = false
    private var pendingResponseID = UUID()
    private var turnTimerTask: Task<Void, Never>?
    private var timedSeat: Int?
    private var preservedTurnDeadline: Date?
    private var responseTimerTasks: [Int: Task<Void, Never>] = [:]

    var humanCount: Int {
        humanSeats.count
    }

    var isHumanTurn: Bool {
        isStarted && phase == .playing && turn == localSeat
    }

    private var isHumanSeatTurn: Bool {
        isStarted && phase == .playing && humanSeats.contains(turn)
    }

    private var canActForCurrentSeat: Bool {
        isHumanTurn || remoteActionSeat == turn
    }

    func countdown(for seat: Int) -> Int {
        responseCountdowns[seat] ?? (turnTimerSeat == seat ? (turnSecondsRemaining ?? 20) : 20)
    }

    func isCountdownActive(for seat: Int) -> Bool {
        if phase == .responding { return false }
        return responseCountdowns[seat] != nil || (turnTimerSeat == seat && turnSecondsRemaining != nil)
    }

    func countdownDeadline(for seat: Int) -> Date? {
        if phase == .responding { return nil }
        return responseCountdownDeadlines[seat] ?? (turnTimerSeat == seat ? turnCountdownDeadline : nil)
    }

    var responseDecisionDeadline: Date? {
        guard phase == .responding else { return nil }
        if let humanDeadline = pendingHumanSeats.compactMap({ responseCountdownDeadlines[$0] }).min() {
            return humanDeadline
        }
        return pendingAISeats.compactMap { responseCountdownDeadlines[$0] }.min()
    }

    var responseDecisionDuration: TimeInterval {
        pendingHumanSeats.isEmpty ? 20 : 5
    }

    var currentHand: [MahjongTile] {
        hands.indices.contains(turn) ? hands[turn] : []
    }

    var visibleHandSeat: Int {
        currentResponderSeat ?? localSeat
    }

    var visibleHand: [MahjongTile] {
        hands.indices.contains(visibleHandSeat) ? hands[visibleHandSeat] : []
    }

    var activeSeat: Int {
        currentResponderSeat ?? turn
    }

    var isHumanResponse: Bool {
        phase == .responding && currentResponderSeat != nil
    }

    var currentResponderSeat: Int? {
        if let remoteActionSeat, pendingHumanSeats.contains(remoteActionSeat) {
            return remoteActionSeat
        }
        return pendingHumanSeats.first(where: { $0 == localSeat })
    }

    var humanResponseOptions: [MahjongCallOption] {
        guard let seat = currentResponderSeat else { return [] }
        return pendingOptions[seat, default: []] + [MahjongCallOption(kind: .pass, heldTiles: [])]
    }

    var canSelfDraw: Bool {
        guard canActForCurrentSeat, justDrew else { return false }
        return Self.isWinningHand(currentHand, meldCount: melds[turn].count, missingSuit: missingSuits[turn])
    }

    var availableKongTiles: [MahjongTile] {
        guard canActForCurrentSeat, justDrew, wall.count > 0 else { return [] }
        let unique = Set(currentHand).sorted { $0.sortKey < $1.sortKey }
        return unique.filter { tile in
            currentHand.filter { $0 == tile }.count == 4 ||
                (melds[turn].contains(where: { $0.kind == .triplet && $0.tiles.first == tile }) && currentHand.contains(tile))
        }
    }

    func start() {
        if mode == .lan, !isLANAuthority {
            onLANAction?(.start); return
        }
        stopTurnTimer()
        clearPendingResponses()
        let tiles = Self.makeWall(for: ruleset).shuffled()
        if !isStarted, phase == .idle {
            dealer = 0; roundNumber = 1
        }
        roundStartedAt = nil
        roundEndedAt = nil
        wall = tiles
        hands = Array(repeating: [], count: 4)
        melds = Array(repeating: [], count: 4)
        discards = Array(repeating: [], count: 4)
        missingSuits = Array(repeating: nil, count: 4)
        dice = []
        dealtCount = 0
        turn = dealer
        winner = nil
        discarder = nil
        winningTile = nil
        winByDiscard = false
        roundResult = ""
        justDrew = false
        needsDiscard = false
        readySeats = (0 ..< 4).map { !humanSeats.contains($0) }
        phase = .waitingForReady
        isStarted = true
        message = "AI 已准备 · 等待玩家准备"
    }

    func leaveTable() {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.leave)
        }
        leaveTableLocally()
    }

    func leaveTableLocally() {
        stopTurnTimer()
        clearPendingResponses()
        isStarted = false
        phase = .idle
        roundStartedAt = nil
        roundEndedAt = nil
        winner = nil
        winningTile = nil
        winByDiscard = false
        roundResult = ""
        message = "选择玩法并开始一局"
    }

    func addLANGuest(seat: Int, nickname: String) {
        guard mode == .lan, isLANAuthority, (1 ..< 4).contains(seat), !humanSeats.contains(seat) else { return }
        humanSeats.append(seat)
        humanSeats.sort()
        setLANNickname(nickname, for: seat)
        if phase == .waitingForReady {
            readySeats[seat] = false
        }
        if phase == .choosingMissingSuit, missingSuits[seat] == nil, !pendingHumanSeats.contains(seat) {
            pendingHumanSeats.append(seat)
        }
        if phase == .responding, pendingAISeats.contains(seat) {
            if pendingAIStarted {
                pendingResponseID = UUID()
                for aiSeat in pendingAISeats {
                    stopResponseTimer(for: aiSeat)
                    chosenResponses.removeValue(forKey: aiSeat)
                }
                pendingAIStarted = false
            }
            pendingAISeats.remove(seat)
            pendingHumanSeats.append(seat)
            stopResponseTimer(for: seat)
            startResponseTimer(for: seat)
        } else if phase == .playing, turn == seat {
            stopTurnTimer()
            startTurnTimerIfNeeded()
        }
    }

    func removeLANGuest(seat: Int, aiNickname: String = "AI") {
        guard mode == .lan, isLANAuthority, (1 ..< 4).contains(seat), humanSeats.contains(seat) else { return }
        humanSeats.removeAll { $0 == seat }
        setLANNickname(aiNickname, for: seat)
        if phase == .waitingForReady {
            readySeats[seat] = true
            if readySeats.allSatisfy({ $0 }) {
                Task { await rollDiceAndDeal() }
            }
        }
        if phase == .choosingMissingSuit, pendingHumanSeats.contains(seat) {
            pendingHumanSeats.removeAll { $0 == seat }
            missingSuits[seat] = Self.leastFrequentSuit(in: hands[seat])
            if pendingHumanSeats.isEmpty {
                phase = .playing
                turn = dealer
                justDrew = true
                needsDiscard = true
                Task { await runAutomatedTurns() }
            }
        }
        if phase == .responding, pendingHumanSeats.contains(seat) {
            pendingHumanSeats.removeAll { $0 == seat }
            pendingAISeats.insert(seat)
            stopResponseTimer(for: seat)
            continueResponsesAfterHumans()
        } else if phase == .playing, turn == seat {
            Task { await runAutomatedTurns() }
        }
    }

    func markReady() {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.ready); return
        }
        let seat = remoteActionSeat ?? localSeat
        guard phase == .waitingForReady,
              humanSeats.contains(seat),
              readySeats.indices.contains(seat),
              !readySeats[seat] else { return }
        readySeats[seat] = true
        message = "\(seatName(seat)) 已准备"
        if readySeats.allSatisfy({ $0 }) {
            Task { await rollDiceAndDeal() }
        }
    }

    func rollDiceAndDeal() async {
        guard phase == .waitingForReady, readySeats.allSatisfy({ $0 }) else { return }
        phase = .dealing
        roundStartedAt = Date()
        roundEndedAt = nil
        dice = [Int.random(in: 1 ... 6), Int.random(in: 1 ... 6)]
        let breakIndex = (dice.reduce(0, +) * 2) % max(wall.count, 1)
        wall = Array(wall[breakIndex...]) + Array(wall[..<breakIndex])
        message = "掷出 \(dice[0]) 点和 \(dice[1]) 点 · 从庄家右侧开门"

        // Deal three four-tile packets, then one tile per seat, then the dealer's extra tile.
        for packetSize in [4, 4, 4, 1] {
            for _ in 0 ..< packetSize {
                for offset in 0 ..< 4 {
                    let seat = (dealer + offset) % 4
                    dealOneTile(to: seat)
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
        }
        dealOneTile(to: dealer)
        let dealerDraw = hands[dealer].last
        for seat in 0 ..< 4 {
            hands[seat].sort { $0.sortKey < $1.sortKey }
        }
        if let dealerDraw, let index = hands[dealer].firstIndex(of: dealerDraw) {
            let tile = hands[dealer].remove(at: index)
            hands[dealer].append(tile)
        }
        turn = dealer
        justDrew = true
        needsDiscard = true
        if ruleset == .sichuan {
            prepareMissingSuitChoices()
        } else {
            phase = .playing
            message = "庄家 \(seatName(dealer)) 起手 14 张 · 请出牌或宣告自摸"
        }
        await runAutomatedTurns()
    }

    func chooseMissingSuit(_ suit: MahjongSuit) {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.missingSuit(suit)); return
        }
        guard phase == .choosingMissingSuit, let seat = currentResponderSeat else { return }
        announceVoice("action-missing-suit", for: seat)
        missingSuits[seat] = suit
        pendingHumanSeats.removeAll { $0 == seat }
        if pendingHumanSeats.contains(localSeat) {
            let nextSeat = localSeat
            message = "\(seatName(nextSeat)) 请选择定缺花色"
            return
        }
        if let waitingSeat = pendingHumanSeats.first {
            message = "等待\(seatName(waitingSeat))选择定缺花色"
            return
        }
        phase = .playing
        turn = dealer
        justDrew = true
        needsDiscard = true
        message = "定缺完成 · 庄家 \(seatName(dealer)) 起手 14 张"
        Task { await runAutomatedTurns() }
    }

    func discard(_ tile: MahjongTile) {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.discard(tile, drawnTile: false)); return
        }
        discard(tile, drawnTile: false)
    }

    func discardDrawnTile() {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.discardDrawn); return
        }
        guard justDrew, let tile = currentHand.last else { return }
        discard(tile, drawnTile: true)
    }

    private func discard(_ tile: MahjongTile, drawnTile: Bool) {
        guard canActForCurrentSeat, currentHand.count == concealedCountRequired(for: turn, onTurn: true), currentHand.contains(tile) else { return }
        if let missingSuit = missingSuits[turn], currentHand.contains(where: { $0.matches(missingSuit) }), !tile.matches(missingSuit) {
            message = "四川麻将定缺中，请先打出缺门花色"
            return
        }
        stopTurnTimer()
        performDiscard(tile, by: turn, preserveOrder: drawnTile)
        beginResponses(to: tile, from: turn)
        Task { await runAutomatedTurns() }
    }

    func respond(to option: MahjongCallOption) {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.respond(option)); return
        }
        guard phase == .responding, let seat = currentResponderSeat else { return }
        guard option.kind == .pass || pendingOptions[seat, default: []].contains(option) else { return }
        if option.kind == .pass {
            announceVoice("action-pass", for: seat)
        }
        stopResponseTimer(for: seat)
        if option.kind != .pass {
            chosenResponses[seat] = option
        }
        pendingHumanSeats.removeAll { $0 == seat }
        if let nextSeat = currentResponderSeat {
            message = "\(seatName(nextSeat))，请回应这张弃牌"
            _ = nextSeat
        } else {
            continueResponsesAfterHumans()
        }
    }

    func claimSelfDraw() {
        if mode == .lan && !isLANAuthority && !applyingRemoteAction {
            onLANAction?(.selfDraw); return
        }
        guard canSelfDraw || (remoteActionSeat == turn && Self.isWinningHand(currentHand, meldCount: melds[turn].count, missingSuit: missingSuits[turn])) else { return }
        stopTurnTimer()
        finishRound(winner: turn, tile: hands[turn].last, byDiscard: false)
    }

    func declareKong(_ tile: MahjongTile) {
        if mode == .lan && !isLANAuthority && !applyingRemoteAction {
            onLANAction?(.kong(tile)); return
        }
        guard availableKongTiles.contains(tile) || (remoteActionSeat == turn && aiKongTiles(for: turn).contains(tile)) else { return }
        stopTurnTimer()
        performKong(tile, for: turn)
        Task { await runAutomatedTurns() }
    }

    func nextRound() {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            onLANAction?(.nextRound); return
        }
        guard phase == .roundEnded else { return }
        if winner != dealer {
            dealer = (dealer + 1) % 4
        }
        roundNumber += 1
        start()
        markReady()
    }

    func seatName(_ seat: Int) -> String {
        switch seat {
        case 0: "东家"
        case 1: "南家"
        case 2: "西家"
        default: "北家"
        }
    }

    func tileCount(for seat: Int) -> Int {
        guard hands.indices.contains(seat), melds.indices.contains(seat) else { return 0 }
        return hands[seat].count + melds[seat].reduce(0) { $0 + $1.tiles.count }
    }

    private func dealOneTile(to seat: Int) {
        guard !wall.isEmpty else { return }
        hands[seat].append(wall.removeFirst())
        dealtCount += 1
    }

    private func prepareMissingSuitChoices() {
        phase = .choosingMissingSuit
        pendingHumanSeats = humanSeats
        for seat in 0 ..< 4 where !humanSeats.contains(seat) {
            missingSuits[seat] = Self.leastFrequentSuit(in: hands[seat])
        }
        if let first = currentResponderSeat {
            message = "四川麻将 · \(seatName(first)) 请选择定缺花色"
        }
    }

    private func performDiscard(_ tile: MahjongTile, by player: Int, preserveOrder: Bool = false) {
        let index = preserveOrder ? hands[player].lastIndex(of: tile) : hands[player].firstIndex(of: tile)
        guard let index else { return }
        hands[player].remove(at: index)
        if !preserveOrder {
            hands[player].sort { $0.sortKey < $1.sortKey }
        }
        discards[player].append(tile)
        announceVoice("tile-\(tile.id)", for: player)
        justDrew = false
        needsDiscard = false
        message = "\(seatName(player)) 打出 \(tile.accessibilityName)"
    }

    private func beginResponses(to tile: MahjongTile, from discarder: Int) {
        clearPendingResponses()
        pendingTile = tile
        pendingDiscarder = discarder
        for distance in 1 ... 3 {
            let seat = (discarder + distance) % 4
            let options = availableCalls(for: seat, using: tile, from: discarder)
            guard !options.isEmpty else { continue }
            pendingOptions[seat] = options
            if humanSeats.contains(seat) {
                pendingHumanSeats.append(seat)
            } else {
                pendingAISeats.insert(seat)
            }
        }
        if !pendingHumanSeats.isEmpty || !pendingAISeats.isEmpty {
            phase = .responding
            for seat in pendingHumanSeats {
                startResponseTimer(for: seat)
            }
            if let responder = currentResponderSeat {
                message = "\(seatName(responder))，请回应这张弃牌"
            } else {
                message = "AI 正在判断是否吃、碰或杠"
            }
            continueResponsesAfterHumans()
        } else {
            resolveResponses()
        }
    }

    private func continueResponsesAfterHumans() {
        guard phase == .responding, pendingHumanSeats.isEmpty else { return }
        if !chosenResponses.isEmpty {
            pendingAISeats.removeAll()
            resolveResponses()
            Task { await runAutomatedTurns() }
            return
        }
        guard !pendingAIStarted else { return }
        pendingAIStarted = true
        guard let tile = pendingTile, let discarder = pendingDiscarder else { return }
        if pendingAISeats.isEmpty {
            resolveResponses()
            Task { await runAutomatedTurns() }
            return
        }
        message = "AI 正在判断是否吃、碰或杠"
        let responseID = pendingResponseID
        for seat in pendingAISeats {
            startResponseTimer(for: seat)
            Task { await resolveAICall(for: seat, discardedTile: tile, discarder: discarder, responseID: responseID) }
        }
    }

    private func availableCalls(for seat: Int, using tile: MahjongTile, from discarder: Int) -> [MahjongCallOption] {
        guard hands.indices.contains(seat) else { return [] }
        if let missingSuit = missingSuits[seat], hands[seat].contains(where: { $0.matches(missingSuit) }) {
            return []
        }
        var options: [MahjongCallOption] = []
        if Self.isWinningHand(hands[seat] + [tile], meldCount: melds[seat].count, missingSuit: missingSuits[seat]) {
            options.append(MahjongCallOption(kind: .win, heldTiles: []))
        }
        let same = hands[seat].filter { $0 == tile }
        if same.count >= 3, !wall.isEmpty {
            options.append(MahjongCallOption(kind: .exposedKong, heldTiles: Array(same.prefix(3))))
        }
        if same.count >= 2 {
            options.append(MahjongCallOption(kind: .pong, heldTiles: Array(same.prefix(2))))
        }
        if seat == (discarder + 1) % 4, case let .suited(suit, value) = tile {
            for start in max(1, value - 2) ... min(7, value) {
                let run = [MahjongTile.suited(suit, start), .suited(suit, start + 1), .suited(suit, start + 2)]
                guard run.contains(tile) else { continue }
                var available = hands[seat]
                var held: [MahjongTile] = []
                for required in run where required != tile {
                    guard let index = available.firstIndex(of: required) else { held = []; break }
                    held.append(available.remove(at: index))
                }
                if held.count == 2 {
                    options.append(MahjongCallOption(kind: .chi, heldTiles: held))
                }
            }
        }
        return options
    }

    private func resolveAICall(
        for seat: Int,
        discardedTile: MahjongTile,
        discarder: Int,
        responseID: UUID
    ) async {
        let options = pendingOptions[seat, default: []]
        let choice = await aiCall(from: options, for: seat, discardedTile: discardedTile, discarder: discarder)
        guard phase == .responding,
              pendingTile == discardedTile,
              pendingDiscarder == discarder,
              pendingResponseID == responseID,
              pendingAISeats.contains(seat) else { return }
        stopResponseTimer(for: seat)
        if let choice {
            chosenResponses[seat] = choice
            if choice.kind == .pass {
                announceVoice("action-pass", for: seat)
            }
        } else {
            announceVoice("action-pass", for: seat)
        }
        pendingAISeats.remove(seat)
        if pendingAISeats.isEmpty, pendingHumanSeats.isEmpty {
            resolveResponses()
            await runAutomatedTurns()
        }
    }

    private func aiCall(
        from options: [MahjongCallOption],
        for seat: Int,
        discardedTile: MahjongTile,
        discarder: Int
    ) async -> MahjongCallOption? {
        let fallback = fallbackAICall(from: options, for: seat)
        // 胡牌是确定性规则判断，命中后直接胡牌，不等待模型接口。
        if let winningOption = options.first(where: { $0.kind == .win }) {
            return winningOption
        }
        let choices = options + [MahjongCallOption(kind: .pass, heldTiles: [])]
        let choiceText = choices.enumerated()
            .map { "\($0.offset + 1). \(aiCallLabel($0.element))" }
            .joined(separator: "\n")
        let handText = hands[seat].map(\.accessibilityName).joined(separator: "、")
        let meldText = melds[seat].map(\.label).joined(separator: "；")
        let userPrompt = """
        玩法：\(ruleset.rawValue)
        你的手牌：\(handText)
        你的副露：\(meldText.isEmpty ? "无" : meldText)
        定缺：\(missingSuits[seat]?.shortName ?? "无")
        刚打出的牌：\(discardedTile.accessibilityName)（\(seatName(discarder))）
        可选操作（只返回对应序号）：
        \(choiceText)

        选择最有利的一项；不值得吃碰杠时选择“过”。只返回序号，不要添加其他内容。
        """
        guard let answer = await requestMahjongAI(userPrompt: userPrompt, outputFormat: .optionIndex),
              let index = parseAIOptionIndex(answer, count: choices.count) else { return fallback }
        return choices[index]
    }

    private func fallbackAICall(from options: [MahjongCallOption], for seat: Int) -> MahjongCallOption? {
        if let win = options.first(where: { $0.kind == .win }) {
            return win
        }
        if let kong = options.first(where: { $0.kind == .exposedKong }) {
            return kong
        }
        if let pong = options.first(where: { $0.kind == .pong }) {
            return pong
        }
        if let chi = options.first(where: { $0.kind == .chi }) {
            let hand = hands[seat] + chi.heldTiles
            return Self.isWinningHand(hand, meldCount: melds[seat].count, missingSuit: missingSuits[seat]) || Int.random(in: 0 ... 2) == 0 ? chi : nil
        }
        return nil
    }

    private func aiCallLabel(_ option: MahjongCallOption) -> String {
        switch option.kind {
        case .pass: return "过"
        case .win: return "胡"
        case .exposedKong, .pong:
            guard let tile = option.heldTiles.first else { return option.kind.rawValue }
            return "\(option.kind.rawValue)\(tile.aiName)"
        case .chi:
            let tiles = option.heldTiles.sorted { $0.sortKey < $1.sortKey }.map(\.aiName).joined()
            return "吃\(tiles)"
        }
    }

    private func resolveResponses() {
        guard pendingHumanSeats.isEmpty, pendingAISeats.isEmpty else { return }
        guard let tile = pendingTile, let discarder = pendingDiscarder else { return }
        let selected = chosenResponses
            .filter { $0.value.kind != .pass }
            .sorted { lhs, rhs in
                if lhs.value.kind.priority != rhs.value.kind.priority {
                    return lhs.value.kind.priority > rhs.value.kind.priority
                }
                let leftDistance = (lhs.key - discarder + 4) % 4
                let rightDistance = (rhs.key - discarder + 4) % 4
                return leftDistance < rightDistance
            }
        clearPendingResponses()
        if let (seat, option) = selected.first {
            switch option.kind {
            case .win:
                finishRound(winner: seat, tile: tile, byDiscard: true, discarder: discarder)
            case .exposedKong:
                announceVoice("action-exposed-kong", for: seat)
                consumeClaimedDiscard(from: discarder)
                remove(option.heldTiles, from: seat)
                melds[seat].append(MahjongMeld(kind: .exposedKong, tiles: option.heldTiles + [tile]))
                turn = seat
                message = "\(seatName(seat)) 明杠 · 补一张牌"
                drawSupplement(for: seat)
            case .pong:
                announceVoice("action-pong", for: seat)
                consumeClaimedDiscard(from: discarder)
                remove(option.heldTiles, from: seat)
                melds[seat].append(MahjongMeld(kind: .triplet, tiles: option.heldTiles + [tile]))
                turn = seat
                justDrew = false
                needsDiscard = true
                phase = .playing
                message = "\(seatName(seat)) 碰牌 · 请打出一张"
            case .chi:
                announceVoice("action-chi", for: seat)
                consumeClaimedDiscard(from: discarder)
                remove(option.heldTiles, from: seat)
                melds[seat].append(MahjongMeld(kind: .sequence, tiles: option.heldTiles + [tile]))
                turn = seat
                justDrew = false
                needsDiscard = true
                phase = .playing
                message = "\(seatName(seat)) 吃牌 · 请打出一张"
            case .pass:
                break
            }
        } else {
            turn = (discarder + 1) % 4
            drawTurnTile()
        }
    }

    private func consumeClaimedDiscard(from seat: Int) {
        if discards.indices.contains(seat), !discards[seat].isEmpty {
            discards[seat].removeLast()
        }
    }

    private func remove(_ tiles: [MahjongTile], from seat: Int) {
        for tile in tiles {
            if let index = hands[seat].firstIndex(of: tile) {
                hands[seat].remove(at: index)
            }
        }
    }

    private func drawTurnTile() {
        guard !wall.isEmpty else {
            finishDraw()
            return
        }
        let tile = wall.removeFirst()
        hands[turn].append(tile)
        justDrew = true
        needsDiscard = true
        phase = .playing
        if Self.isWinningHand(hands[turn], meldCount: melds[turn].count, missingSuit: missingSuits[turn]) {
            if humanSeats.contains(turn) {
                message = "\(seatName(turn)) 摸到和牌 · 可选择自摸或继续打牌"
            } else {
                finishRound(winner: turn, tile: tile, byDiscard: false)
            }
        } else {
            message = "\(seatName(turn)) 摸牌"
        }
    }

    private func drawSupplement(for seat: Int) {
        guard !wall.isEmpty else {
            finishDraw()
            return
        }
        hands[seat].append(wall.removeLast())
        justDrew = true
        needsDiscard = true
        phase = .playing
        if Self.isWinningHand(hands[seat], meldCount: melds[seat].count, missingSuit: missingSuits[seat]) {
            if humanSeats.contains(seat) {
                message = "\(seatName(seat)) 补牌后和牌 · 可选择自摸或继续打牌"
            } else {
                finishRound(winner: seat, tile: hands[seat].last, byDiscard: false)
            }
        }
    }

    private func performKong(_ tile: MahjongTile, for seat: Int) {
        if let tripletIndex = melds[seat].firstIndex(where: { $0.kind == .triplet && $0.tiles.first == tile }),
           let handIndex = hands[seat].firstIndex(of: tile)
        {
            announceVoice("action-added-kong", for: seat)
            hands[seat].remove(at: handIndex)
            melds[seat][tripletIndex] = MahjongMeld(kind: .addedKong, tiles: melds[seat][tripletIndex].tiles + [tile])
        } else {
            announceVoice("action-concealed-kong", for: seat)
            let four = Array(hands[seat].filter { $0 == tile }.prefix(4))
            remove(four, from: seat)
            melds[seat].append(MahjongMeld(kind: .concealedKong, tiles: four))
        }
        message = "\(seatName(seat)) 宣告杠牌 · 补一张牌"
        drawSupplement(for: seat)
    }

    private func runAutomatedTurns() async {
        while phase == .playing, !isHumanSeatTurn {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard phase == .playing, !isHumanSeatTurn else { return }
            if !needsDiscard {
                drawTurnTile()
                guard phase == .playing else { return }
            }
            if justDrew, Self.isWinningHand(hands[turn], meldCount: melds[turn].count, missingSuit: missingSuits[turn]) {
                finishRound(winner: turn, tile: hands[turn].last, byDiscard: false)
                return
            }
            startTurnTimerIfNeeded()
            let decision = await aiTurnDecision(for: turn)
            guard phase == .playing, !isHumanSeatTurn else { return }
            if case let .kong(kong) = decision {
                stopTurnTimer()
                performKong(kong, for: turn)
                guard phase == .playing else { return }
                if Self.isWinningHand(hands[turn], meldCount: melds[turn].count, missingSuit: missingSuits[turn]) {
                    finishRound(winner: turn, tile: hands[turn].last, byDiscard: false)
                    return
                }
                continue
            }
            guard case let .discard(tile) = decision else { continue }
            stopTurnTimer()
            let discarder = turn
            performDiscard(tile, by: discarder)
            beginResponses(to: tile, from: discarder)
            guard phase == .playing else { return }
        }
        if phase == .playing, needsDiscard, humanSeats.contains(turn) {
            startTurnTimerIfNeeded()
        }
    }

    private func aiTurnDecision(for seat: Int) async -> MahjongAIDecision {
        let hand = hands[seat]
        guard let firstTile = hand.first else { return .discard(.honor(0)) }
        let forcedSuit = missingSuits[seat].flatMap { suit in
            hand.contains(where: { $0.matches(suit) }) ? suit : nil
        }
        let candidates = forcedSuit.map { suit in hand.filter { $0.matches(suit) } } ?? hand
        let discards = Array(Set(candidates)).sorted { $0.sortKey < $1.sortKey }
        let kongs = aiKongTiles(for: seat)
        let meldText = melds[seat].map(\.label).joined(separator: "；")

        if kongs.isEmpty {
            let tileNames = Array(Set(discards.map(\.aiName))).sorted()
            let userPrompt = """
            \(ruleset.rawValue)。手牌：\(hand.map(\.accessibilityName).joined(separator: "、"))。副露：\(meldText.isEmpty ? "无" : meldText)。定缺：\(missingSuits[seat]?.shortName ?? "无")。牌墙：\(wall.count)张。
            从以下合法可打出的牌中选最有利的一张，只返回牌名：\(tileNames.joined(separator: "、"))
            """
            if let answer = await requestMahjongAI(userPrompt: userPrompt, outputFormat: .tileName) {
                let normalized = normalizeAIAnswer(answer)
                if let tile = discards.first(where: { normalizeAIAnswer($0.aiName) == normalized }) {
                    return .discard(tile)
                }
            }
            return .discard(Self.aiDiscard(from: hand, missingSuit: missingSuits[seat]) ?? firstTile)
        }

        let decisions = kongs.map(MahjongAIDecision.kong) + discards.map(MahjongAIDecision.discard)
        let choices = decisions.map { decision -> String in
            switch decision {
            case let .kong(tile): "杠\(tile.aiName)"
            case let .discard(tile): "出\(tile.aiName)"
            }
        }
        let choiceText = choices.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let userPrompt = """
        \(ruleset.rawValue)。手牌：\(hand.map(\.accessibilityName).joined(separator: "、"))。副露：\(meldText.isEmpty ? "无" : meldText)。定缺：\(missingSuits[seat]?.shortName ?? "无")。牌墙：\(wall.count)张。
        可选操作（只返回对应序号）：
        \(choiceText)
        """
        if let answer = await requestMahjongAI(userPrompt: userPrompt, outputFormat: .optionIndex),
           let index = parseAIOptionIndex(answer, count: decisions.count)
        {
            return decisions[index]
        }
        return .discard(Self.aiDiscard(from: hand, missingSuit: missingSuits[seat]) ?? firstTile)
    }

    private func requestMahjongAI(userPrompt: String, outputFormat: MahjongAIOutputFormat) async -> String? {
        let configuration = AIAPIConfiguration.load()
        guard configuration.isConfigured else { return nil }
        let systemPrompt = switch outputFormat {
        case .tileName:
            "你是麻将选牌判定器。只能从用户消息给出的合法牌名中选择一张，并且只输出牌名本身。禁止输出操作、序号、解释、标点、引号、JSON、Markdown或其他内容。"
        case .optionIndex:
            "你是麻将操作判定器。只能选择用户消息中的一项，只输出该项从1开始的十进制序号。禁止输出操作名称、解释、标点、引号、JSON、Markdown或其他内容。"
        }
        return await withCheckedContinuation { continuation in
            let gate = MahjongAIRequestGate(continuation)
            let requestTask = Task.detached(priority: .userInitiated) {
                do {
                    let answer = try await OpenAICompatibleAPIClient().complete(
                        systemPrompt: systemPrompt,
                        userPrompt: userPrompt,
                        configuration: configuration,
                        options: AICompletionOptions(
                            task: "mahjong-decision",
                            temperature: 0,
                            responseFormat: .plainText,
                            timeoutSeconds: 10,
                            maxOutputTokens: 12
                        )
                    )
                    gate.resolve(answer)
                } catch {
                    JarvisLog.error(category: .network, event: "mahjong.ai-decision.failed", error: error)
                    gate.resolve(nil)
                }
            }
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if gate.resolve(nil) {
                    requestTask.cancel()
                    JarvisLog.notice(
                        category: .network,
                        event: "mahjong.ai-decision.deadline",
                        result: "local-fallback",
                        fields: ["deadlineSeconds": "10"]
                    )
                }
            }
        }
    }

    private func normalizeAIAnswer(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "萬", with: "万")
            .replacingOccurrences(of: "條", with: "条")
            .replacingOccurrences(of: "東", with: "东")
            .replacingOccurrences(of: "紅", with: "红")
            .replacingOccurrences(of: "發", with: "发")
    }

    private func parseAIOptionIndex(_ raw: String, count: Int) -> Int? {
        let answer = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty,
              answer.allSatisfy(\.isNumber),
              let number = Int(answer),
              (1 ... count).contains(number) else { return nil }
        return number - 1
    }

    private func startTurnTimerIfNeeded() {
        guard phase == .playing, needsDiscard else {
            stopTurnTimer()
            return
        }
        guard turnTimerTask == nil || timedSeat != turn else { return }
        let deadline = preservedTurnDeadline
        preservedTurnDeadline = nil
        stopTurnTimer()
        let seat = turn
        timedSeat = seat
        turnTimerSeat = seat
        let turnDeadline = deadline ?? Date().addingTimeInterval(20)
        let initialSeconds = max(1, Int(ceil(turnDeadline.timeIntervalSinceNow)))
        turnCountdownDeadline = turnDeadline
        turnSecondsRemaining = initialSeconds
        turnTimerTask = Task { [weak self] in
            for seconds in stride(from: initialSeconds, through: 1, by: -1) {
                guard let self, !Task.isCancelled,
                      self.phase == .playing, self.turn == seat, self.needsDiscard else { return }
                self.turnSecondsRemaining = seconds
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled,
                  self.phase == .playing, self.turn == seat, self.needsDiscard else { return }
            let tile = self.timeoutDiscardTile(for: seat)
            if let tile {
                self.autoDiscardAfterTimeout(tile, for: seat)
            }
        }
    }

    private func timeoutDiscardTile(for seat: Int) -> MahjongTile? {
        guard hands.indices.contains(seat), !hands[seat].isEmpty else { return nil }
        let hand = hands[seat]

        if ruleset == .sichuan,
           let missingSuit = missingSuits[seat],
           hand.contains(where: { $0.matches(missingSuit) })
        {
            // Hand order follows each seat's own view: east/south read from the
            // first tile, west/north from the last tile.
            if seat <= 1 {
                return hand.first(where: { $0.matches(missingSuit) })
            }
            return hand.reversed().first(where: { $0.matches(missingSuit) })
        }

        if justDrew {
            return hand.last
        }
        return Self.aiDiscard(from: hand, missingSuit: missingSuits[seat])
    }

    private func startResponseTimer(for seat: Int) {
        guard responseTimerTasks[seat] == nil else { return }
        let duration = humanSeats.contains(seat) ? 5 : 20
        responseCountdowns[seat] = duration
        responseCountdownDeadlines[seat] = Date().addingTimeInterval(TimeInterval(duration))
        responseTimerTasks[seat] = Task { [weak self] in
            for seconds in stride(from: duration, through: 1, by: -1) {
                guard let self, !Task.isCancelled, self.phase == .responding,
                      self.pendingHumanSeats.contains(seat) || self.pendingAISeats.contains(seat) else { return }
                self.responseCountdowns[seat] = seconds
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled, self.phase == .responding else { return }
            self.timeoutResponse(for: seat)
        }
    }

    private func stopResponseTimer(for seat: Int) {
        responseTimerTasks.removeValue(forKey: seat)?.cancel()
        responseCountdowns.removeValue(forKey: seat)
        responseCountdownDeadlines.removeValue(forKey: seat)
    }

    private func timeoutResponse(for seat: Int) {
        guard phase == .responding else { return }
        stopResponseTimer(for: seat)
        if pendingHumanSeats.contains(seat) || pendingAISeats.contains(seat) {
            announceVoice("action-pass", for: seat)
        }
        pendingHumanSeats.removeAll { $0 == seat }
        pendingAISeats.remove(seat)
        if pendingHumanSeats.isEmpty, pendingAISeats.isEmpty {
            resolveResponses()
            Task { await runAutomatedTurns() }
        } else if pendingHumanSeats.isEmpty {
            continueResponsesAfterHumans()
        } else if let responder = currentResponderSeat {
            message = "\(seatName(responder))，请回应这张弃牌"
        }
    }

    private func autoDiscardAfterTimeout(_ tile: MahjongTile, for seat: Int) {
        guard phase == .playing, turn == seat, needsDiscard, hands[seat].contains(tile) else { return }
        stopTurnTimer()
        performDiscard(tile, by: seat)
        beginResponses(to: tile, from: seat)
        Task { await runAutomatedTurns() }
    }

    private func stopTurnTimer() {
        turnTimerTask?.cancel()
        turnTimerTask = nil
        timedSeat = nil
        turnTimerSeat = nil
        turnSecondsRemaining = nil
        turnCountdownDeadline = nil
    }

    private func aiKongTiles(for seat: Int) -> [MahjongTile] {
        let unique = Set(hands[seat]).sorted { $0.sortKey < $1.sortKey }
        return unique.filter { tile in
            hands[seat].filter { $0 == tile }.count == 4 ||
                (melds[seat].contains(where: { $0.kind == .triplet && $0.tiles.first == tile }) && hands[seat].contains(tile))
        }
    }

    private func finishRound(winner: Int, tile: MahjongTile?, byDiscard: Bool) {
        finishRound(winner: winner, tile: tile, byDiscard: byDiscard, discarder: nil)
    }

    private func finishRound(winner: Int, tile: MahjongTile?, byDiscard: Bool, discarder: Int?) {
        announceVoice(byDiscard ? "action-win" : "action-self-draw", for: winner)
        stopTurnTimer()
        roundEndedAt = Date()
        self.winner = winner
        self.discarder = byDiscard ? discarder : nil
        winningTile = tile
        winByDiscard = byDiscard
        var completedHand = hands.indices.contains(winner) ? hands[winner] : []
        if byDiscard, let tile {
            completedHand.append(tile)
        }
        winningHandType = Self.winningHandType(completedHand, meldCount: melds.indices.contains(winner) ? melds[winner].count : 0)
        phase = .roundEnded
        isStarted = true
        justDrew = false
        needsDiscard = false
        roundResult = "\(byDiscard ? "荣和" : "自摸")\(tile.map { " · \($0.accessibilityName)" } ?? "")"
        message = "\(roundResult) · 本局结束"
        readySeats = (0 ..< 4).map { !humanSeats.contains($0) }
        clearPendingResponses()
    }

    private func finishDraw() {
        announceVoice("action-draw", for: turn)
        stopTurnTimer()
        roundEndedAt = Date()
        phase = .roundEnded
        isStarted = true
        justDrew = false
        needsDiscard = false
        winner = nil
        roundResult = "牌墙摸完 · 流局"
        message = roundResult
        readySeats = (0 ..< 4).map { !humanSeats.contains($0) }
        clearPendingResponses()
    }

    private func clearPendingResponses() {
        for seat in Array(responseTimerTasks.keys) {
            stopResponseTimer(for: seat)
        }
        pendingResponseID = UUID()
        pendingTile = nil
        pendingDiscarder = nil
        pendingHumanSeats = []
        pendingOptions = [:]
        chosenResponses = [:]
        pendingAISeats = []
        pendingAIStarted = false
    }

    private func concealedCountRequired(for seat: Int, onTurn: Bool) -> Int {
        (onTurn ? 14 : 13) - melds[seat].count * 3
    }

    private static func makeWall(for ruleset: MahjongRuleset) -> [MahjongTile] {
        var tiles: [MahjongTile] = []
        for suit in MahjongSuit.allCases {
            for value in 1 ... 9 {
                for _ in 0 ..< 4 {
                    tiles.append(.suited(suit, value))
                }
            }
        }
        if ruleset.includesHonors {
            for value in 0 ..< 7 {
                for _ in 0 ..< 4 {
                    tiles.append(.honor(value))
                }
            }
        }
        return tiles
    }

    private static func leastFrequentSuit(in hand: [MahjongTile]) -> MahjongSuit {
        MahjongSuit.allCases.min { lhs, rhs in
            hand.filter { $0.matches(lhs) }.count < hand.filter { $0.matches(rhs) }.count
        } ?? .characters
    }

    private static func aiDiscard(from hand: [MahjongTile], missingSuit: MahjongSuit? = nil) -> MahjongTile? {
        guard !hand.isEmpty else { return nil }
        let missing = missingSuit.map { suit in hand.filter { $0.matches(suit) } } ?? []
        let candidates = missing.isEmpty ? hand : missing
        let counts = Dictionary(grouping: candidates, by: { $0 }).mapValues(\.count)
        return candidates.min { lhs, rhs in
            let lhsCount = counts[lhs, default: 0]
            let rhsCount = counts[rhs, default: 0]
            let lhsScore = lhsCount * 8 + neighborCount(lhs, counts: counts)
            let rhsScore = rhsCount * 8 + neighborCount(rhs, counts: counts)
            return lhsScore < rhsScore
        }
    }

    private static func neighborCount(_ tile: MahjongTile, counts: [MahjongTile: Int]) -> Int {
        guard case let .suited(suit, value) = tile else { return 0 }
        return [-2, -1, 1, 2].reduce(0) { result, offset in
            result + counts[.suited(suit, value + offset), default: 0]
        }
    }

    private static func isWinningHand(_ hand: [MahjongTile], meldCount: Int = 0, missingSuit: MahjongSuit? = nil) -> Bool {
        guard hand.count == 14 - meldCount * 3 else { return false }
        if let missingSuit, hand.contains(where: { $0.matches(missingSuit) }) {
            return false
        }
        var counts = Dictionary(grouping: hand, by: { $0 }).mapValues(\.count)
        if meldCount == 0 {
            let pairCount = counts.values.reduce(0) { $0 + $1 / 2 }
            if counts.values.allSatisfy({ $0.isMultiple(of: 2) }), pairCount == 7 {
                return true
            }

            let orphans: Set<MahjongTile> = Set(MahjongSuit.allCases.flatMap { suit in
                [MahjongTile.suited(suit, 1), .suited(suit, 9)]
            } + (0 ..< 7).map(MahjongTile.honor))
            if hand.allSatisfy(orphans.contains),
               orphans.allSatisfy({ counts[$0, default: 0] > 0 }),
               counts.values.contains(2)
            {
                return true
            }
        }
        for tile in counts.keys where counts[tile, default: 0] >= 2 {
            counts[tile, default: 0] -= 2
            if canFormMelds(&counts) {
                return true
            }
            counts[tile, default: 0] += 2
        }
        return false
    }

    private static func winningHandType(_ hand: [MahjongTile], meldCount: Int) -> MahjongWinningHandType {
        guard meldCount == 0 else { return .standard }
        let counts = Dictionary(grouping: hand, by: { $0 }).mapValues(\.count)
        if counts.values.allSatisfy({ $0 == 2 }), counts.count == 7 {
            return .sevenPairs
        }
        let orphans: Set<MahjongTile> = Set(MahjongSuit.allCases.flatMap { suit in
            [MahjongTile.suited(suit, 1), .suited(suit, 9)]
        } + (0 ..< 7).map(MahjongTile.honor))
        if hand.count == 14,
           hand.allSatisfy(orphans.contains),
           orphans.allSatisfy({ counts[$0, default: 0] > 0 }),
           counts.values.contains(2)
        {
            return .thirteenOrphans
        }
        return .standard
    }

    private static func canFormMelds(_ counts: inout [MahjongTile: Int]) -> Bool {
        guard let tile = counts.keys.filter({ counts[$0, default: 0] > 0 }).min(by: { $0.sortKey < $1.sortKey }) else {
            return true
        }
        if counts[tile, default: 0] >= 3 {
            counts[tile, default: 0] -= 3
            if canFormMelds(&counts) {
                return true
            }
            counts[tile, default: 0] += 3
        }
        if case let .suited(suit, value) = tile, value <= 7 {
            let next = MahjongTile.suited(suit, value + 1)
            let last = MahjongTile.suited(suit, value + 2)
            if counts[next, default: 0] > 0, counts[last, default: 0] > 0 {
                counts[tile, default: 0] -= 1
                counts[next, default: 0] -= 1
                counts[last, default: 0] -= 1
                if canFormMelds(&counts) {
                    return true
                }
                counts[tile, default: 0] += 1
                counts[next, default: 0] += 1
                counts[last, default: 0] += 1
            }
        }
        return false
    }
}

struct MahjongGameSnapshot: Codable {
    var mode: MahjongPlayMode
    var ruleset: MahjongRuleset
    var seatNicknames: [String]
    var hands: [[MahjongTile]]
    var melds: [[MahjongMeld]]
    var discards: [[MahjongTile]]
    var wall: [MahjongTile]
    var turn: Int
    var dealer: Int
    var roundNumber: Int
    var roundStartedAt: Date?
    var roundEndedAt: Date?
    var humanSeats: [Int]
    var dice: [Int]
    var dealtCount: Int
    var justDrew: Bool
    var needsDiscard: Bool
    var message: String
    var winner: Int?
    var discarder: Int?
    var winningTile: MahjongTile?
    var winningHandType: MahjongWinningHandType
    var aiProfileIDs: [String]
    var winByDiscard: Bool
    var isStarted: Bool
    var phase: MahjongRoundPhase
    var readySeats: [Bool]
    var missingSuits: [MahjongSuit?]
    var roundResult: String
    var turnSecondsRemaining: Int?
    var turnTimerSeat: Int?
    var responseCountdowns: [Int: Int]
    var turnCountdownDeadline: Date?
    var responseCountdownDeadlines: [Int: Date]
    var pendingTile: MahjongTile?
    var pendingDiscarder: Int?
    var pendingHumanSeats: [Int]
    var pendingOptions: [Int: [MahjongCallOption]]
    var chosenResponses: [Int: MahjongCallOption]
    var pendingAISeats: [Int]
    var preservedTurnDeadline: Date?
}

private extension MahjongTile {
    func matches(_ suit: MahjongSuit) -> Bool {
        if case let .suited(tileSuit, _) = self {
            return tileSuit == suit
        }
        return false
    }
}
