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

    /// Play-style label for menus, tags, and room lists. The raw value stays unchanged so saved matches still decode.
    var title: String {
        switch self {
        case .national: "标准和牌"
        case .sichuan: "缺一门"
        case .cantonese: "推倒胡"
        }
    }

    var detail: String {
        let rules = switch self {
        case .national:
            "## 🎯 核心规则：四组面子加一对将\n\n国标麻将使用万、筒、条和东南西北、中发白共一百三十六张牌。和牌的基础结构通常是四组面子加一对将牌：面子可以是同花色的连续三张组成的顺子，也可以是三张相同牌组成的刻子；将牌是两张相同的牌。\n\n### 🀄 起手与回合\n\n* 庄家起手十四张，其余玩家各十三张；庄家先打出一张开始对局。\n* 四家按逆时针顺序行动。轮到自己时，从牌墙摸一张，再从手牌中打出一张。\n* 别人打出的牌可以被响应：下一家可以吃，任意一家可以碰或明杠；满足和牌牌型时可以胡牌。若无人响应，则由下一家摸牌。\n\n### 🔁 吃、碰、杠怎么组成\n\n* **吃**：用上家打出的牌和手中的两张牌组成同花色、连续的三张，例如二万、三万、四万。\n* **碰**：手中有两张相同牌时，可以拿别人打出的第三张组成刻子。\n* **明杠**：手中已有三张相同牌时，拿别人打出的第四张组成杠；已碰出的刻子摸到第四张时也可以补杠。\n* **暗杠**：自己手中有四张相同牌时可以暗杠。杠后从牌墙补摸一张；吃、碰、明杠公开展示，暗杠保留暗牌。\n\n### ✅ 胡牌条件与例子\n\n常见牌型是“顺子 / 刻子 × 四组 + 将牌 × 一对”。例如：一二三万、四五六万、七八九条、三个东风，再加一对五筒。也支持七对和十三幺。胡牌可以来自自己摸牌，也可以来自其他玩家打出的牌。\n\n### ⚠️ 计分说明\n\n本版本采用简化竞赛计分：普通胡牌按 8 分、七对 24 分、十三幺 88 分；点炮时三家各付 8 分基础分，点炮者另付牌型分；自摸时三家各付基础分与牌型分。暂未计算完整的 81 种番种与起和门槛。\n\n### 🏁 本局结束\n\n有人胡牌后本局结束并展示各家手牌；牌墙摸完仍无人胡牌时流局。"
        case .sichuan:
            "## 🎯 核心规则：缺一门才能胡\n\n四川麻将“缺一门”的核心是：胡牌时，手牌只能保留万、筒、条中的两种花色，不能三门都在手里。开局每位玩家都要从三种花色中选一门作为自己的缺门，这一步叫**定缺**。通常会选张数较少、搭子较散，或较难继续组成顺子的花色。\n\n### 🀄 定缺与打缺\n\n* **定缺**：发牌后选择万、筒、条中的一门作为本局缺门。选定后不能更换。\n* **打缺**：手牌还留有缺门牌时，出牌必须优先打出缺门牌；自己摸到缺门牌时也要继续清理。缺门牌打完后，才可以自由选择其他牌。\n* **限制响应**：手中仍有缺门牌时，不能用别人打出的牌组成副露；缺门牌不能被吃、碰或杠进手牌。清空缺门后才恢复通常的吃碰杠选择。\n\n### ✅ 胡牌硬性条件\n\n胡牌时必须同时满足两件事：手牌中已经没有定缺花色，并且牌型符合和牌结构。基础牌型是四组顺子或刻子加一对将牌，也支持七对。满足牌型但仍留有缺门牌，不能胡牌。既可以自摸，也可以和其他玩家打出的牌。\n\n### 💡 一个简单的例子\n\n假设你定缺“筒”。接下来的出牌阶段要先把手里的筒子全部打掉；摸到筒子时继续打筒，手里还有筒时不能用别人的牌吃、碰、杠。清空筒子后，如果手牌只剩万和条，并组成“一二三万、四五六万、七八九条、三个八条、一对九条”，就满足基础和牌牌型。\n\n### ⚠️ 流局时的查花猪\n\n如果牌墙摸完仍无人胡牌，结算时检查各家手牌：仍保留万、筒、条三种花色的玩家称为“花猪”，通常需要向其他玩家赔付。本版本按定缺和牌条件限制出牌、响应与胡牌，输赢统一采用简化竞赛计分；尚未实现流局查花猪赔分、换三张、刮风下雨计分和血战到底结算。\n\n### 🏁 本局结束\n\n当前版本任意一位玩家胡牌后即结束本局并展示手牌；牌墙耗尽则流局。四川麻将常见的“血战到底”会在有人胡牌后继续让其他玩家争胜，本版本暂未实现该流程。"
        case .cantonese:
            "## 🎯 核心规则：推倒胡，成牌即可胡\n\n广东推倒胡通常使用万、筒、条和东南西北、中发白，共一百三十六张牌。这里采用易上手的基础推倒胡规则：牌型满足和牌结构即可胡，不要求先凑够复杂番种或最低番数。\n\n### 🀄 起手与回合\n\n* 庄家起手十四张，其余三家各十三张；庄家先打出一张，之后按逆时针轮流行动。\n* 每回合摸一张、打一张。上家打出的牌可以被吃，任意一家打出的牌可以被碰或明杠；达到和牌条件时可以胡牌。\n* 没有人响应弃牌时，由下一家摸牌。有人响应时，优先处理胡牌，再处理杠、碰、吃。\n\n### 🔁 吃、碰、杠\n\n* **吃**：用上家的一张弃牌和手中的两张同花色序数牌组成连续顺子。\n* **碰**：手里有两张相同牌时，用别人的弃牌组成三张相同的刻子。\n* **明杠**：手中已有三张相同牌时接入弃牌，或将已碰的刻子补成四张。\n* **暗杠**：自己摸到四张相同牌时可以暗杠。杠后从牌墙补摸一张；公开副露会展示吃、碰和明杠，暗杠保留暗牌。\n\n### ✅ 和牌牌型与示例\n\n常规牌型为四组顺子或刻子加一对将牌；也支持七对与十三幺。比如“一二三万、四五六万、七八九条、三个东风、一对五筒”即可组成常规牌型。自摸和点和都可胡；达到牌型即可和牌，不设置最低番数门槛。\n\n### ⚠️ 玩法范围说明\n\n“广东麻将”各地规则差异较大。本版本采用简化推倒胡：暂不含花牌、买马、鸡平胡 / 新章等地区计番差异，输赢统一采用简化竞赛计分，不计算完整的地方番种与台数。\n\n### 🏁 本局结束\n\n有人和牌后本局结束并展示四家手牌；牌墙耗尽仍无人和牌时流局。"
        }
        return rules + "\n\n### ✨ 本局加倍\n\n发牌后、首张出牌前，每人有 10 秒选择不加倍（×1）、加倍（×2）或超级加倍（×4）；缺一门在定缺后选择。开局余额满 3,000 毛格子可选 ×2，满 8,000 可选 ×4；超时按 ×1。AI 只根据开局余额按随机权重选择。结算时，每位支付方的基础金额分别乘以赢家倍数和自己的倍数，最多支付其实际余额；流局不结算。"
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
    case choosingMultiplier
    case playing
    case responding
    case roundEnded
}

enum MahjongDoubling {
    static let duration: TimeInterval = 10
    static let revealPause: TimeInterval = 1.4

    static func aiRevealDelay(order: Int, jitter: TimeInterval) -> TimeInterval {
        1.2 + Double(order) * 1.25 + jitter
    }

    static func options(for balance: Int) -> [Int] {
        if balance >= 8000 {
            return [1, 2, 4]
        }
        if balance >= 3000 {
            return [1, 2]
        }
        return [1]
    }

    /// The roll is uniform in 0..<100. Eligibility is based only on the balance
    /// captured before this round, never on the AI's hand or later balance changes.
    static func aiChoice(balance: Int, roll: Int) -> Int {
        if balance < 3000 {
            return 1
        }
        if balance < 8000 {
            return roll < 60 ? 1 : 2
        }
        if roll < 50 {
            return 1
        }
        return roll < 85 ? 2 : 4
    }
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

enum MahjongAIDecision {
    case discard(MahjongTile)
    case kong(MahjongTile)
}

enum MahjongAIOutputFormat {
    case tileName
    case optionIndex
}

final class MahjongAIRequestGate: @unchecked Sendable {
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
    var hands: [[MahjongTile]] = []
    var melds: [[MahjongMeld]] = Array(repeating: [], count: 4)
    var discards: [[MahjongTile]] = Array(repeating: [], count: 4)
    var wall: [MahjongTile] = []
    var turn = 0
    var dealer = 0
    var roundNumber = 1
    var roundStartedAt: Date?
    var roundEndedAt: Date?
    var dice: [Int] = []
    var dealtCount = 0
    var justDrew = false
    var needsDiscard = false
    var message = "选择玩法并开始一局"
    var winner: Int?
    var discarder: Int?
    var winningTile: MahjongTile?
    var winningHandType: MahjongWinningHandType = .standard
    var aiProfileIDs: [String] = ["", "", ""]
    var winByDiscard = false
    var isStarted = false
    var phase: MahjongRoundPhase = .idle
    var readySeats: [Bool] = Array(repeating: false, count: 4)
    var missingSuits: [MahjongSuit?] = Array(repeating: nil, count: 4)
    var roundStartingBalances = Array(repeating: 0, count: 4)
    var multipliers: [Int?] = Array(repeating: nil, count: 4)
    var multiplierDeadline: Date?
    var pendingMultiplierSeats: [Int] = []
    var roundResult = ""
    var turnSecondsRemaining: Int?
    var turnTimerSeat: Int?
    var responseCountdowns: [Int: Int] = [:]
    var turnCountdownDeadline: Date?
    var responseCountdownDeadlines: [Int: Date] = [:]
    var mode: MahjongPlayMode = .solo
    var ruleset: MahjongRuleset = .national
    var humanSeats = [0]
    var localSeat = 0
    var isLANAuthority = true
    var seatNicknames = ["玩家", "局域网玩家", "AI", "AI"]
    var onLANAction: ((MahjongLANAction) -> Void)?
    var onMahjongVoiceCue: ((MahjongVoiceCue) -> Void)?
    var onRoundBalancesRequested: (() -> [Int])?
    var applyingRemoteAction = false
    var remoteActionSeat: Int?

    func configureLAN(humanSeats: [Int], localSeat: Int, authority: Bool) {
        self.humanSeats = Array(Set(humanSeats.filter { (0 ..< 4).contains($0) })).sorted()
        self.localSeat = localSeat
        isLANAuthority = authority
    }

    func setLANNickname(_ nickname: String, for seat: Int) {
        guard seatNicknames.indices.contains(seat) else { return }
        seatNicknames[seat] = String(nickname.prefix(16))
    }

    func announceVoice(_ key: String, for seat: Int) {
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
            roundStartingBalances: roundStartingBalances, multipliers: multipliers,
            multiplierDeadline: multiplierDeadline, pendingMultiplierSeats: pendingMultiplierSeats,
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
        roundStartingBalances = snapshot.roundStartingBalances; multipliers = snapshot.multipliers
        multiplierDeadline = snapshot.multiplierDeadline; pendingMultiplierSeats = snapshot.pendingMultiplierSeats
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
        case let .multiplier(value): chooseMultiplier(value)
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

    func setRoundStartingBalances(_ balances: [Int]) {
        guard isLANAuthority, balances.count == 4 else { return }
        roundStartingBalances = balances.map { max(0, $0) }
    }

    var localMultiplierOptions: [Int] {
        guard phase == .choosingMultiplier, pendingMultiplierSeats.contains(localSeat) else { return [] }
        return MahjongDoubling.options(for: roundStartingBalances[localSeat])
    }

    func chooseMultiplier(_ value: Int) {
        if mode == .lan, !isLANAuthority, !applyingRemoteAction {
            guard localMultiplierOptions.contains(value) else { return }
            onLANAction?(.multiplier(value))
            return
        }
        let seat = remoteActionSeat ?? localSeat
        guard phase == .choosingMultiplier, pendingMultiplierSeats.contains(seat),
              MahjongDoubling.options(for: roundStartingBalances[seat]).contains(value) else { return }
        multipliers[seat] = value
        pendingMultiplierSeats.removeAll { $0 == seat }
        announceVoice(Self.multiplierVoiceCue(for: value), for: seat)
        message = "\(seatName(seat)) 已选择 ×\(value)"
        finishMultiplierChoices()
    }

    static func multiplierVoiceCue(for value: Int) -> String {
        switch value {
        case 2: "action-double"
        case 4: "action-super-double"
        default: "action-no-double"
        }
    }

    func declareCampaignComplete() {
        roundResult = "七位 AI 对手均已破产 · 挑战胜利！"
        message = roundResult
    }

    var pendingTile: MahjongTile?
    var pendingDiscarder: Int?
    var pendingHumanSeats: [Int] = []
    var pendingOptions: [Int: [MahjongCallOption]] = [:]
    var chosenResponses: [Int: MahjongCallOption] = [:]
    var pendingAISeats: Set<Int> = []
    var pendingAIStarted = false
    var pendingResponseID = UUID()
    var turnTimerTask: Task<Void, Never>?
    var timedSeat: Int?
    var preservedTurnDeadline: Date?
    var responseTimerTasks: [Int: Task<Void, Never>] = [:]
    var multiplierTimerTask: Task<Void, Never>?
    var multiplierAIChoiceTasks: [Int: Task<Void, Never>] = [:]
    var multiplierCompletionTask: Task<Void, Never>?
    var missingSuitTimerTask: Task<Void, Never>?

    var humanCount: Int {
        humanSeats.count
    }

    var isHumanTurn: Bool {
        isStarted && phase == .playing && turn == localSeat
    }

    var isHumanSeatTurn: Bool {
        isStarted && phase == .playing && humanSeats.contains(turn)
    }

    var canActForCurrentSeat: Bool {
        isHumanTurn || remoteActionSeat == turn
    }

    func countdown(for seat: Int) -> Int {
        responseCountdowns[seat] ?? (turnTimerSeat == seat ? (turnSecondsRemaining ?? 20) : 20)
    }

    func isCountdownActive(for seat: Int) -> Bool {
        if phase == .responding {
            return false
        }
        return responseCountdowns[seat] != nil || (turnTimerSeat == seat && turnSecondsRemaining != nil)
    }

    func countdownDeadline(for seat: Int) -> Date? {
        if phase == .responding {
            return nil
        }
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
}
