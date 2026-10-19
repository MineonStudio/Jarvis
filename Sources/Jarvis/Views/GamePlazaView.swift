import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum GameLibrarySelection: String, CaseIterable, Identifiable, Hashable {
    case all = "全部游戏"
    case mahjong = "麻将"
    var id: String { rawValue }
}

struct GamePlazaView: View {
    @State private var game = MahjongGame()
    @State private var archive = MahjongArchiveStore()
    @State private var showsLANRoom = false
    @State private var lanRoomService: MahjongLANRoomService?
    @State private var idleLANRoomService = MahjongLANRoomService()
    @State private var showsArchive = false
    @State private var librarySelection: GameLibrarySelection = .all
    @State private var latestSettlement: MahjongArchiveSettlement?
    @State private var lastSettledRoundNumber = 0
    @State private var playerNicknameDraft = ""
    @State private var isCheckingIn = false
    @State private var checkInFailed = false
    @State private var showsAvatarImporter = false
    @State private var avatarImportError: String?
    @State private var gameWindowModel: MahjongGameWindowModel?

    private var gameWindow: MahjongGameWindowController { .shared }

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                JarvisToolbarSurface(id: "games.library", placement: .navigation) {
                    JarvisToolbarGroupedPicker(
                        items: GameLibrarySelection.allCases,
                        selection: $librarySelection,
                        title: { $0.rawValue }
                    )
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) { EmptyView() }
            },
            content: {
                ScrollView {
                    Group {
                        if librarySelection == .mahjong {
                            mahjongDetail
                        } else {
                            gameGallery
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(24)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .jarvisModulePanel()
            }
        )
        .sheet(isPresented: $showsLANRoom) {
            MahjongLANRoomView(localProfile: archive.player) { service in
                startLANMatch(service)
            }
            .frame(width: 560, height: 620)
        }
        .sheet(isPresented: $showsArchive) {
            MahjongArchiveDashboardView(archive: archive)
                .frame(minWidth: 720, minHeight: 620)
        }
        .onChange(of: game.phase) { _, phase in
            guard phase == .roundEnded, lastSettledRoundNumber != game.roundNumber else { return }
            if game.mode == .lan {
                guard let service = lanRoomService, service.isHosting else { return }
                settleLANRound(using: service)
            } else {
                settleRound()
            }
        }
        .onReceive((lanRoomService ?? idleLANRoomService).$lastVoiceCue) { cue in
            guard let cue, let service = lanRoomService, !service.isHosting else { return }
            MahjongVoicePlayer.shared.play(cue.key, gender: voiceGender(for: cue.seat))
        }
        .onReceive((lanRoomService ?? idleLANRoomService).$settlement) { settlement in
            guard game.mode == .lan, let service = lanRoomService, !service.isHosting,
                  let settlement, game.phase == .roundEnded else { return }
            latestSettlement = settlement
            if let profile = service.syncedProfiles[game.localSeat] {
                archive.applyLANPlayerProfile(profile)
            }
            lastSettledRoundNumber = game.roundNumber
        }
        .onReceive((lanRoomService ?? idleLANRoomService).$syncedProfiles) { profiles in
            guard game.mode == .lan, let profile = profiles[game.localSeat] else { return }
            archive.applyLANPlayerProfile(profile)
        }
        .onReceive((lanRoomService ?? idleLANRoomService).$hostLeft) { hostLeft in
            guard hostLeft else { return }
            game.leaveTableLocally()
            lanRoomService?.stop()
            lanRoomService = nil
            latestSettlement = nil
            librarySelection = .mahjong
        }
        .onChange(of: game.isStarted) { _, started in
            if !started { gameWindow.hide() }
        }
        .onChange(of: latestSettlement) { _, settlement in
            gameWindowModel?.roundNotice = settlement?.notice
            gameWindowModel?.roundSettlement = settlement
        }
    }

    private var gameGallery: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("全部游戏")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Spacer()
                Text("1 款游戏")
                    .font(JarvisTypography.control)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 18)], alignment: .leading, spacing: 18) {
                Button { librarySelection = .mahjong } label: { GamePosterCard() }
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var mahjongDetail: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                GamePosterArtwork()
                    .frame(width: 300, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Spacer(minLength: 0)
                        Text("麻将玩法")
                            .font(JarvisTypography.control)
                            .foregroundStyle(.secondary)
                        JarvisDropdownMenu(
                            title: game.ruleset.rawValue,
                            options: MahjongRuleset.allCases.map { JarvisDropdownOption(id: $0.rawValue, title: $0.rawValue) },
                            selectionID: game.ruleset.rawValue,
                            accessibilityLabel: "麻将玩法",
                            help: "选择麻将玩法",
                            maximumControlWidth: 250
                        ) { selectedID in
                            guard let ruleset = MahjongRuleset(rawValue: selectedID) else { return }
                            game.ruleset = ruleset
                        }
                        Text("游玩模式")
                            .font(JarvisTypography.control)
                            .foregroundStyle(.secondary)
                        JarvisDropdownMenu(
                            title: gameModeTitle,
                            options: [
                                JarvisDropdownOption(id: MahjongPlayMode.solo.rawValue, title: "单人对战 AI"),
                                JarvisDropdownOption(id: MahjongPlayMode.lan.rawValue, title: "局域网房间")
                            ],
                            selectionID: game.mode.rawValue,
                            accessibilityLabel: "对局模式",
                            help: "选择对局模式"
                        ) { selectedID in
                            guard let mode = MahjongPlayMode(rawValue: selectedID) else { return }
                            game.mode = mode
                        }
                        Button {
                            if game.isStarted {
                                presentGameWindow()
                            } else if game.mode == .lan {
                                showsLANRoom = true
                            } else {
                                startSoloMatch()
                            }
                        } label: {
                            Text(game.isStarted ? "回到牌桌" : "进入游戏")
                        }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                        .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("中国麻将")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("选择玩法与对局模式，和 AI 对弈，或创建局域网房间与朋友同桌。")
                            .font(JarvisTypography.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            archiveSummary
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("玩法说明", systemImage: "text.alignleft")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(.init(game.ruleset.detail))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
            Spacer(minLength: 0)
        }
    }

    private var gameModeTitle: String {
        game.mode == .solo ? "单人对战 AI" : "局域网房间"
    }

    private var archiveSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Button { showsAvatarImporter = true } label: {
                    MahjongArchiveAvatar(profile: archive.player, size: 54)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.58))
                                .offset(x: 3, y: 3)
                        }
                }
                .buttonStyle(.plain)
                .help("从本地选择头像")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("玩家昵称", text: $playerNicknameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: 150)
                            .onSubmit(savePlayerNickname)
                        Button("保存") { savePlayerNickname() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    Picker("麻将配音", selection: Binding(
                        get: { archive.player.voiceGender },
                        set: { archive.updatePlayerProfile(voiceGender: $0) }
                    )) {
                        ForEach(MahjongVoiceGender.allCases) { gender in
                            Text(gender.displayName).tag(gender)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 112)
                    .help("选择你的麻将语音")
                    Text("余额  \(archive.player.balance.formatted()) 毛格子")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 38)
                archiveMetric("胜率", "\(archive.player.winRate)%")
                archiveMetric("胜场", "\(archive.player.wins)")
                archiveMetric("败场", "\(archive.player.losses)")
                archiveMetric("逃跑", "\(archive.player.escapes)")
                Spacer(minLength: 8)
                Button(checkInButtonTitle, action: startDailyCheckIn)
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(!archive.canClaimDailyReward || isCheckingIn)
                Button("查看档案") { showsArchive = true }
                    .buttonStyle(JarvisSecondaryButtonStyle())
            }
            if let notice = latestSettlement?.notice {
                Text(notice)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let avatarImportError {
                Text("头像导入失败：\(avatarImportError)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .onAppear {
            if playerNicknameDraft.isEmpty { playerNicknameDraft = archive.player.nickname }
        }
        .onChange(of: archive.player.nickname) { _, nickname in
            playerNicknameDraft = nickname
        }
        .fileImporter(isPresented: $showsAvatarImporter, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                do {
                    try archive.updatePlayerAvatar(from: url)
                    avatarImportError = nil
                } catch {
                    avatarImportError = error.localizedDescription
                }
            case let .failure(error):
                avatarImportError = error.localizedDescription
            }
        }
    }

    private var checkInButtonTitle: String {
        if isCheckingIn { return "开始签到" }
        if checkInFailed { return "签到失败" }
        if !archive.canClaimDailyReward { return "签到成功" }
        return "开始签到"
    }

    private func savePlayerNickname() {
        archive.updatePlayerProfile(nickname: playerNicknameDraft)
        playerNicknameDraft = archive.player.nickname
    }

    private func voiceGender(for seat: Int) -> MahjongVoiceGender {
        if game.mode == .lan {
            if let profile = lanRoomService?.syncedProfiles[seat] { return profile.voiceGender }
            if seat == game.localSeat { return archive.player.voiceGender }
        }
        if seat == 0 { return archive.player.voiceGender }
        if game.aiProfileIDs.indices.contains(seat - 1),
           let profile = archive.profile(id: game.aiProfileIDs[seat - 1]) {
            return profile.voiceGender
        }
        return .female
    }

    private func startDailyCheckIn() {
        guard archive.canClaimDailyReward, !isCheckingIn else { return }
        isCheckingIn = true
        checkInFailed = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            let succeeded = archive.claimDailyReward()
            isCheckingIn = false
            checkInFailed = !succeeded
            if succeeded {
                latestSettlement = MahjongArchiveSettlement(
                    transfers: [], notice: "每日签到已领取 +5,000 毛格子", campaignComplete: false,
                    playerBankrupt: false, playerNeedsExit: false
                )
            }
        }
    }

    private func archiveMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }

    private func startSoloMatch() {
        guard archive.player.balance > 0 else {
            latestSettlement = MahjongArchiveSettlement(
                transfers: [], notice: "毛格子余额不足，先领取今日签到任务；今日补助已用完则请明日再战。",
                campaignComplete: false, playerBankrupt: true, playerNeedsExit: true
            )
            return
        }
        let profiles = archive.prepareAIOpponents()
        guard !profiles.isEmpty else {
            latestSettlement = MahjongArchiveSettlement(
                transfers: [], notice: "今日可用的 AI 对手不足，挑战已完成。", campaignComplete: true,
                playerBankrupt: false, playerNeedsExit: false
            )
            return
        }
        game.mode = .solo
        game.assignAIProfiles(profiles)
        let archive = archive
        let aiProfileIDs = game.aiProfileIDs
        game.onMahjongVoiceCue = { cue in
            let gender: MahjongVoiceGender
            if cue.seat == 0 {
                gender = archive.player.voiceGender
            } else if aiProfileIDs.indices.contains(cue.seat - 1),
                      let profile = archive.profile(id: aiProfileIDs[cue.seat - 1]) {
                gender = profile.voiceGender
            } else {
                gender = .female
            }
            MahjongVoicePlayer.shared.play(cue.key, gender: gender)
        }
        game.start()
        lastSettledRoundNumber = 0
        latestSettlement = nil
        librarySelection = .mahjong
        presentGameWindow()
    }

    private func exitMatch() {
        if game.isStarted && game.phase != .roundEnded {
            archive.recordVoluntaryEscape()
        }
        game.leaveTable()
        lanRoomService?.stop()
        lanRoomService = nil
        latestSettlement = nil
        librarySelection = .mahjong
    }

    private func presentGameWindow() {
        let model: MahjongGameWindowModel
        if let gameWindowModel {
            model = gameWindowModel
        } else {
            let created = MahjongGameWindowModel(
                game: game,
                archive: archive,
                lanRoomService: lanRoomService ?? idleLANRoomService
            )
            gameWindowModel = created
            model = created
        }
        model.lanRoomService = lanRoomService ?? idleLANRoomService
        model.roundNotice = latestSettlement?.notice
        model.roundSettlement = latestSettlement
        model.onNextRound = { startNextRound() }
        model.onExit = { exitMatch() }
        gameWindow.onUserClose = { exitMatch() }
        gameWindow.show(model: model)
    }

    private func startLANMatch(_ service: MahjongLANRoomService) {
        lanRoomService = service
        game.mode = .lan
        if service.isHosting {
            let archive = archive
            game.onMahjongVoiceCue = { [weak service] cue in
                let gender = service?.syncedProfiles[cue.seat]?.voiceGender ?? archive.player.voiceGender
                MahjongVoicePlayer.shared.play(cue.key, gender: gender)
                service?.broadcastVoiceCue(cue)
            }
        } else {
            game.onMahjongVoiceCue = nil
        }
        lastSettledRoundNumber = 0
        latestSettlement = nil
        librarySelection = .mahjong
        if service.isHosting {
            let aiIDs = archive.prepareAIOpponents()
            game.assignAIProfiles(aiIDs)
            let aiProfiles = aiIDs.compactMap { archive.profile(id: $0) }
            service.startHostGame(game, profile: archive.player, aiProfiles: aiProfiles)
            game.start()
        } else {
            service.startJoinedGame(game, profile: archive.player)
        }
        showsLANRoom = false
        presentGameWindow()
    }

    private func startNextRound() {
        if game.mode == .lan {
            lanRoomService?.clearSettlement()
            game.nextRound()
            return
        }
        if latestSettlement?.campaignComplete == true || latestSettlement?.playerNeedsExit == true {
            game.leaveTable()
            latestSettlement = nil
            return
        }
        game.assignAIProfiles(archive.replacingBankruptOpponents(game.aiProfileIDs))
        game.nextRound()
    }

    private func settleRound() {
        lastSettledRoundNumber = game.roundNumber
        guard let winner = game.winner else {
            latestSettlement = nil
            return
        }
        let settlement = archive.settle(
            winnerSeat: winner,
            discarderSeat: game.discarder,
            handType: game.winningHandType,
            byDiscard: game.winByDiscard,
            seatProfileIDs: ["player"] + game.aiProfileIDs
        )
        latestSettlement = settlement
        if settlement.playerNeedsExit {
            game.leaveTable()
            return
        }
        if settlement.campaignComplete { game.declareCampaignComplete() }
    }

    private func settleLANRound(using service: MahjongLANRoomService) {
        lastSettledRoundNumber = game.roundNumber
        guard let winner = game.winner else {
            latestSettlement = nil
            return
        }
        var seats = (0..<4).map { seat in
            service.syncedProfiles[seat] ?? MahjongPlayerArchive(
                id: "empty-seat-\(seat)", nickname: game.seatName(seat), avatarStyle: .player, balance: 0
            )
        }
        seats[0] = archive.player
        if let profile = archive.profile(id: game.aiProfileIDs.indices.contains(1) ? game.aiProfileIDs[1] : "") { seats[2] = profile }
        if let profile = archive.profile(id: game.aiProfileIDs.indices.contains(2) ? game.aiProfileIDs[2] : "") { seats[3] = profile }
        let result = archive.settleLAN(
            winnerSeat: winner,
            discarderSeat: game.discarder,
            handType: game.winningHandType,
            byDiscard: game.winByDiscard,
            seatProfiles: seats
        )
        latestSettlement = result.settlement
        service.publishSettlement(result.settlement, profiles: result.profiles)
    }
}

private struct MahjongArchiveDashboardView: View {
    let archive: MahjongArchiveStore

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("麻将档案").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("玩家战绩、毛格子余额与 AI 对手档案")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("今日 AI 淘汰  \(archive.eliminatedAICount) / \(archive.totalAICount)")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            HStack(spacing: 14) {
                MahjongArchiveAvatar(profile: archive.player, size: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(archive.player.nickname).font(.system(size: 17, weight: .semibold))
                    Text("\(archive.player.balance.formatted()) 毛格子")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("胜率 \(archive.player.winRate)%  ·  胜 \(archive.player.wins)  负 \(archive.player.losses)  逃跑 \(archive.player.escapes)")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(archive.canClaimDailyReward ? "领取每日签到 · +5,000" : "今日签到已领取") {
                    _ = archive.claimDailyReward()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(!archive.canClaimDailyReward)
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Text("AI 玩家档案").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("每日首场对局时，余额低于 10,000 自动补至 10,000")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(archive.aiProfiles) { profile in
                        MahjongArchiveProfileCard(
                            profile: profile,
                            isEliminated: archive.isEliminatedToday(profile),
                            onToggleVoiceGender: {
                                archive.updateAIVoiceGender(
                                    profileID: profile.id,
                                    voiceGender: profile.voiceGender == .male ? .female : .male
                                )
                            }
                        )
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            VStack(alignment: .leading, spacing: 7) {
                Text("单局赔付标准").font(.system(size: 12, weight: .semibold))
                Text("普通胡牌：点炮 1,000 / 自摸每家 500　 ·　 七对：点炮 1,500 / 自摸每家 700　 ·　 十三幺：点炮 2,000 / 自摸每家 900")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(22)
    }
}

private struct MahjongArchiveProfileCard: View {
    let profile: MahjongPlayerArchive
    let isEliminated: Bool
    let onToggleVoiceGender: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MahjongArchiveAvatar(profile: profile, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(profile.nickname).font(.system(size: 14, weight: .semibold))
                    if isEliminated {
                        Text("今日淘汰").font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
                    }
                }
                Text("\(profile.balance.formatted()) 毛格子")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                HStack(spacing: 7) {
                    Text("胜率 \(profile.winRate)%  ·  胜 \(profile.wins) / 负 \(profile.losses) / 逃跑 \(profile.escapes)")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Button(profile.voiceGender.displayName, action: onToggleVoiceGender)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("切换 AI 麻将语音")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MahjongArchiveAvatar: View {
    let profile: MahjongPlayerArchive
    let size: CGFloat

    private var palette: [Color] {
        switch profile.avatarStyle {
        case .player: [Color(red: 0.12, green: 0.39, blue: 0.58), Color(red: 0.24, green: 0.68, blue: 0.71)]
        case .iron: [Color(red: 0.47, green: 0.08, blue: 0.09), Color(red: 0.91, green: 0.35, blue: 0.18)]
        case .spider: [Color(red: 0.49, green: 0.05, blue: 0.09), Color(red: 0.88, green: 0.16, blue: 0.22)]
        case .captain: [Color(red: 0.07, green: 0.16, blue: 0.40), Color(red: 0.28, green: 0.48, blue: 0.77)]
        case .thor: [Color(red: 0.14, green: 0.26, blue: 0.49), Color(red: 0.49, green: 0.69, blue: 0.88)]
        case .hulk: [Color(red: 0.15, green: 0.29, blue: 0.17), Color(red: 0.38, green: 0.65, blue: 0.34)]
        case .widow: [Color(red: 0.14, green: 0.16, blue: 0.20), Color(red: 0.53, green: 0.18, blue: 0.24)]
        case .hawkeye: [Color(red: 0.20, green: 0.15, blue: 0.36), Color(red: 0.51, green: 0.31, blue: 0.65)]
        case .panda: [Color(red: 0.10, green: 0.45, blue: 0.46), Color(red: 0.52, green: 0.78, blue: 0.68)]
        case .fox: [Color(red: 0.69, green: 0.24, blue: 0.09), Color(red: 0.98, green: 0.60, blue: 0.19)]
        case .cat: [Color(red: 0.78, green: 0.30, blue: 0.06), Color(red: 1.0, green: 0.68, blue: 0.28)]
        case .rabbit: [Color(red: 0.32, green: 0.49, blue: 0.76), Color(red: 0.72, green: 0.62, blue: 0.88)]
        case .bear: [Color(red: 0.42, green: 0.25, blue: 0.11), Color(red: 0.76, green: 0.54, blue: 0.26)]
        case .tiger: [Color(red: 0.71, green: 0.20, blue: 0.10), Color(red: 0.96, green: 0.52, blue: 0.17)]
        case .owl: [Color(red: 0.08, green: 0.17, blue: 0.40), Color(red: 0.35, green: 0.43, blue: 0.80)]
        }
    }

    private var generatedImage: NSImage? {
        if let filename = profile.customAvatarFilename {
            let url = MahjongArchiveStore.avatarDirectoryURL.appendingPathComponent(filename)
            if let image = NSImage(contentsOf: url) { return image }
        }
        guard let assetName = profile.avatarStyle.generatedAssetName,
              let url = Bundle.main.url(forResource: assetName, withExtension: "png", subdirectory: "GameArtwork/Avatars") else { return nil }
        return NSImage(contentsOf: url)
    }

    private var symbol: String {
        switch profile.avatarStyle {
        case .player: "person.fill"
        case .iron: "cpu.fill"
        case .spider: "ant.fill"
        case .captain: "shield.lefthalf.filled"
        case .thor: "bolt.fill"
        case .hulk: "hand.raised.fingers.spread.fill"
        case .widow: "eye.fill"
        case .hawkeye: "scope"
        case .panda, .fox, .cat, .rabbit, .bear, .tiger, .owl: "person.fill"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.12)).frame(width: size * 0.72).offset(x: size * 0.32, y: -size * 0.32)
            if let generatedImage {
                Image(nsImage: generatedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.43, weight: .black))
                    .foregroundStyle(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                VStack { Spacer(); Text(String(profile.nickname.prefix(1)))
                        .font(.system(size: size * 0.15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                        .padding(.bottom, size * 0.055) }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityLabel("\(profile.nickname)头像")
    }
}

private struct GamePosterCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GamePosterArtwork()
                .frame(height: 184)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("中国麻将")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("棋牌 · 单人对战 AI / 局域网")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.jarvisAccent)
                    .padding(8)
                    .background(Color.jarvisAccent.opacity(0.1), in: Circle())
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct GamePosterArtwork: View {
    private static let poster: NSImage? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("GameArtwork/mahjong-poster.svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        return image
    }()

    var body: some View {
        GeometryReader { geometry in
            if let poster = Self.poster {
                Image(nsImage: poster)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                fallback
            }
        }
        .accessibilityLabel("中国麻将游戏海报：青玉牌桌与麻将牌")
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.17, blue: 0.16), Color(red: 0.12, green: 0.38, blue: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: -8) {
                MahjongTileView(tile: .suited(.bamboo, 3)).rotationEffect(.degrees(-9))
                MahjongTileView(tile: .honor(4)).rotationEffect(.degrees(4))
                MahjongTileView(tile: .suited(.dots, 5)).rotationEffect(.degrees(12))
            }
        }
    }
}

/// Match-table felt and tile shell. Tags and buttons use the same semantic
/// colors as the rest of the app, so they are not listed here.
private struct MahjongTablePalette {
    var scheme: ColorScheme

    var isDark: Bool { scheme == .dark }

    var felt: Color {
        isDark
            ? Color(red: 0.035, green: 0.12, blue: 0.09)
            : Color(red: 0.56, green: 0.76, blue: 0.66)
    }

    var feltAccentTop: Double { isDark ? 0.68 : 0.22 }
    var feltAccentBottom: Double { isDark ? 0.38 : 0.08 }

    var discardFill: Color { Color.black.opacity(isDark ? 0.14 : 0.08) }
    var discardStroke: Color {
        isDark ? Color.white.opacity(0.07) : Color(red: 0.10, green: 0.26, blue: 0.18).opacity(0.28)
    }

    var tileBackGreen: [Color] {
        isDark
            ? [Color(red: 0.20, green: 0.59, blue: 0.33), Color(red: 0.09, green: 0.39, blue: 0.23)]
            : [Color(red: 0.30, green: 0.68, blue: 0.42), Color(red: 0.16, green: 0.48, blue: 0.30)]
    }

    var tileSide: Color {
        isDark
            ? Color(red: 0.035, green: 0.22, blue: 0.12)
            : Color(red: 0.10, green: 0.34, blue: 0.20)
    }

    func tileShadowOpacity(compact: Bool) -> Double {
        if isDark { return compact ? 0.08 : 0.18 }
        return compact ? 0.14 : 0.26
    }
}

private extension View {
    /// Title and ready tags share one frosted capsule. Text follows the
    /// appearance; the glass itself is the system liquid glass, untinted.
    func mahjongAdaptiveTag() -> some View {
        font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .jarvisGlass(in: Capsule(), interactive: false)
    }
}

struct MahjongTableView: View {
    var model: MahjongGameWindowModel

    private var game: MahjongGame { model.game }
    private var archive: MahjongArchiveStore { model.archive }
    private var lanRoomService: MahjongLANRoomService { model.lanRoomService }
    private var roundNotice: String? { model.roundNotice }
    private var roundSettlement: MahjongArchiveSettlement? { model.roundSettlement }
    private var onNextRound: () -> Void { model.onNextRound }
    private var onExit: () -> Void { model.onExit }

    var body: some View {
        MahjongOverheadTable(
            game: game,
            archive: archive,
            lanRoomService: lanRoomService,
            roundNotice: roundNotice,
            roundSettlement: roundSettlement,
            onNextRound: onNextRound,
            onExit: onExit
        )
    }

    /// Rules, duration, wall count, and exit. Its own rounded panel, above the felt.
    private var matchInfoBar: some View {
        ZStack {
            HStack(spacing: 8) {
                titleTag(game.ruleset.rawValue)
                titleTag(game.mode.rawValue)
                if game.mode == .lan, let code = lanRoomService.roomCode {
                    titleTag("房间码 \(code)")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let endedAt = game.roundEndedAt {
                    titleTag("对局时长  \(formattedRoundDuration(at: endedAt))")
                } else if game.roundStartedAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        titleTag("对局时长  \(formattedRoundDuration(at: context.date))")
                    }
                } else {
                    titleTag("对局时长 00:00")
                }
                titleTag("牌组剩余  \(game.wall.count) 张")
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer(minLength: 0)
                Button("退出游戏", action: onExit)
                    .buttonStyle(JarvisSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 36)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func feltBackground(_ palette: MahjongTablePalette) -> some View {
        palette.felt
            .overlay {
                LinearGradient(
                    colors: [
                        Color.jarvisAccent.opacity(palette.feltAccentTop),
                        Color.jarvisAccent.opacity(palette.feltAccentBottom)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
    }

    private func titleTag(_ text: String) -> some View {
        Text(text)
            .mahjongAdaptiveTag()
    }

    private func formattedRoundDuration(at date: Date) -> String {
        guard let start = game.roundStartedAt else { return "00:00" }
        let totalSeconds = max(0, Int(date.timeIntervalSince(start)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    @ViewBuilder
    private var workflowControls: some View {
        switch game.phase {
        case .waitingForReady:
            EmptyView()

        case .dealing:
            EmptyView()

        case .choosingMissingSuit:
            if game.currentResponderSeat == game.localSeat {
                HStack(spacing: 10) {
                    ForEach(MahjongSuit.allCases, id: \.self) { suit in
                        Button(suit.shortName) { game.chooseMissingSuit(suit) }
                            .buttonStyle(JarvisSecondaryButtonStyle())
                    }
                }
                .padding(12)
            }

        case .responding:
            HStack(spacing: 8) {
                ForEach(game.humanResponseOptions) { option in
                    Button(callTitle(option)) { game.respond(to: option) }
                        .buttonStyle(JarvisSecondaryButtonStyle(tint: option.kind == .win ? .orange : nil))
                }
            }
            .padding(12)

        case .playing where game.isHumanTurn:
            if game.canSelfDraw || !game.availableKongTiles.isEmpty {
                HStack(spacing: 8) {
                    if game.canSelfDraw {
                        Button("自摸") { game.claimSelfDraw() }
                            .buttonStyle(JarvisSecondaryButtonStyle(tint: .orange))
                    }
                    ForEach(game.availableKongTiles) { tile in
                        Button("杠【\(tile.accessibilityName)】") { game.declareKong(tile) }
                            .buttonStyle(JarvisSecondaryButtonStyle())
                    }
                }
                .padding(10)
            }

        case .roundEnded:
            EmptyView()

        default:
            EmptyView()
        }
    }

    private func callTitle(_ option: MahjongCallOption) -> String {
        guard !option.heldTiles.isEmpty else { return option.kind.rawValue }
        let tiles = option.heldTiles.map(\.accessibilityName).joined(separator: "、")
        return "\(option.kind.rawValue)【\(tiles)】"
    }

}

private enum MahjongDiscardMetrics {
    static let tileSpacing: CGFloat = 2
    static let safetyInset: CGFloat = 12
    static let zoneGap: CGFloat = MahjongSeatAreaMetrics.spacingBetweenAreas
    static let horizontalWidth: CGFloat = 7 * 48 + 6 * tileSpacing + 2 * safetyInset
    static let horizontalHeight: CGFloat = 4 * 68 + 3 * tileSpacing + 2 * safetyInset
    static let sideWidth: CGFloat = 4 * 68 + 3 * tileSpacing + 2 * safetyInset
    static let sideHeight: CGFloat = 7 * 48 + 6 * tileSpacing + 2 * safetyInset
    static let sideAreaHeight: CGFloat = 2 * horizontalHeight + zoneGap

    static func center(for seat: Int, width: CGFloat, height: CGFloat) -> CGPoint {
        let totalWidth = sideWidth * 2 + horizontalWidth + zoneGap * 2
        let leftCenterX = width / 2 - totalWidth / 2 + sideWidth / 2
        let middleCenterX = leftCenterX + sideWidth / 2 + zoneGap + horizontalWidth / 2
        let rightCenterX = middleCenterX + horizontalWidth / 2 + zoneGap + sideWidth / 2
        let topCenterY = height / 2 - (horizontalHeight / 2 + zoneGap / 2)
        let bottomCenterY = height / 2 + (horizontalHeight / 2 + zoneGap / 2)
        switch seat {
        case 2:
            return CGPoint(x: middleCenterX, y: topCenterY)
        case 3:
            return CGPoint(x: rightCenterX, y: height / 2)
        case 1:
            return CGPoint(x: leftCenterX, y: height / 2)
        default:
            return CGPoint(x: middleCenterX, y: bottomCenterY)
        }
    }

    static func scaledCenter(for seat: Int, width: CGFloat, height: CGFloat, scale: CGFloat) -> CGPoint {
        let center = center(for: seat, width: width, height: height)
        return CGPoint(
            x: width / 2 + (center.x - width / 2) * scale,
            y: height / 2 + (center.y - height / 2) * scale
        )
    }
}

private struct MahjongHandDisplayTile: Identifiable {
    let id: String
    let tile: MahjongTile
}

private enum MahjongSeatAreaMetrics {
    static let tileWidth: CGFloat = 48
    static let tileHeight: CGFloat = 68
    static let tileSpacing: CGFloat = 2
    static let safeInset: CGFloat = 12
    static let drawGap: CGFloat = tileWidth
    static let meldGroupGap: CGFloat = 8
    // Fifteen slots: thirteen base tiles, one tile-width draw gap, and the drawn tile.
    // Keep the safety inset on both ends; side seats use these same dimensions rotated.
    static let handLength: CGFloat = 15 * tileWidth + 12 * tileSpacing + 2 * safeInset
    static let areaThickness: CGFloat = tileHeight + 2 * safeInset
    static let spacingBetweenAreas: CGFloat = 12
    static let operationHeight: CGFloat = 64
    static let operationMaxWidth: CGFloat = 620
    /// Main-view hand tiles draw larger than the other three seats.
    static let localHandScale: CGFloat = 1.5

    static func operationCenterY(in boardHeight: CGFloat) -> CGFloat {
        boardHeight - 55 - areaThickness / 2 - spacingBetweenAreas
            - areaThickness - spacingBetweenAreas - operationHeight / 2
    }
}

private enum MahjongPlayerInfoCardMetrics {
    static let gap: CGFloat = 12
    /// Compact slot: avatar, nickname, and balance. The detail popover holds the rest.
    static let compactWidth: CGFloat = 252
    static let compactHeight: CGFloat = 100
    /// Left and right seats stack avatar, nickname, and balance on separate rows.
    static let sideWidth: CGFloat = 136
    static let sideHeight: CGFloat = 180

    static func height(areaThickness: CGFloat) -> CGFloat {
        areaThickness + gap + areaThickness
    }

    static func width(areaThickness: CGFloat) -> CGFloat {
        height(areaThickness: areaThickness) + 56
    }
}

private struct MahjongPlayerInfoCard: View {
    let profile: MahjongPlayerArchive
    let seatName: String
    let missingSuit: MahjongSuit?
    let countdownActive: Bool
    let countdownDeadline: Date?
    var stacksVertically = false
    var detailArrowEdge: Edge = .bottom

    @State private var showsDetail = false
    @State private var isAvatarHovered = false

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var content: some View {
        if stacksVertically {
            VStack(spacing: 8) {
                avatarButton
                nicknameText
                balanceRow
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                avatarButton
                VStack(alignment: .leading, spacing: 4) {
                    nicknameText
                    balanceRow
                }
                .frame(maxWidth: 140, alignment: .leading)
            }
        }
    }

    private var nicknameText: some View {
        Text(profile.nickname)
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var balanceRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "centsign.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.96, green: 0.76, blue: 0.22))
                .accessibilityHidden(true)
            Text(profile.balance.formatted())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("余额\(profile.balance.formatted())毛格子")
    }

    private var avatarButton: some View {
        Button {
            showsDetail = true
        } label: {
            avatar
        }
        .buttonStyle(.plain)
        .onHover { isAvatarHovered = $0 }
        .scaleEffect(isAvatarHovered ? 1.06 : 1)
        .animation(.easeInOut(duration: 0.15), value: isAvatarHovered)
        .help("查看\(profile.nickname)的资料")
        .accessibilityLabel("查看\(profile.nickname)的资料")
        .popover(isPresented: $showsDetail, arrowEdge: detailArrowEdge) {
            MahjongPlayerDetailPanel(
                profile: profile,
                seatName: seatName,
                missingSuit: missingSuit
            )
        }
    }

    private var avatar: some View {
        ZStack {
            let avatarSize: CGFloat = countdownActive ? 72 : 64
            let avatarFrameSize = avatarSize + 8
            MahjongArchiveAvatar(profile: profile, size: avatarSize)
                .frame(width: avatarSize, height: avatarSize)
            if countdownActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    let remaining = countdownDeadline?.timeIntervalSince(context.date) ?? 20
                    MahjongCountdownRing(
                        progress: CGFloat(min(max(remaining / 20, 0), 1)),
                        size: avatarFrameSize
                    )
                }
            }
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

struct MahjongPlayerDetailPanel: View {
    let profile: MahjongPlayerArchive
    let seatName: String
    let missingSuit: MahjongSuit?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                MahjongArchiveAvatar(profile: profile, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(seatName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(profile.nickname)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("毛格子：\(profile.balance.formatted())")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let missingSuit {
                Text("缺门：\(missingSuit.shortName)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 0) {
                metric("胜率", "\(profile.winRate)%")
                metric("胜场", "\(profile.wins)")
                metric("败场", "\(profile.losses)")
                metric("逃跑", "\(profile.escapes)")
            }
            Text("语音：\(profile.voiceGender.displayName)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [
            seatName,
            profile.nickname,
            "余额\(profile.balance)毛格子",
            "胜率\(profile.winRate)%",
            "胜场\(profile.wins)",
            "败场\(profile.losses)",
            "逃跑\(profile.escapes)",
            "语音\(profile.voiceGender.displayName)"
        ]
        if let missingSuit {
            parts.insert("缺门\(missingSuit.shortName)", at: 3)
        }
        return parts.joined(separator: "，")
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MahjongCountdownRing: View {
    let progress: CGFloat
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let trackColor = colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3)
        Canvas { context, size in
            let bounds = CGRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4)
            let track = Path(roundedRect: bounds, cornerSize: CGSize(width: 14, height: 14))
            context.stroke(track, with: .color(trackColor), lineWidth: 3)

            let boundedProgress = min(max(progress, 0), 1)
            let segmentCount = Int((boundedProgress * 120).rounded(.up))
            guard segmentCount > 0 else { return }
            let activeColor = countdownColor(at: 1 - Double(boundedProgress))
            for index in 0..<segmentCount {
                let start = Double(index) / 120
                let end = min(Double(index + 1) / 120, Double(boundedProgress))
                let segment = track.trimmedPath(from: start, to: end)
                context.stroke(segment, with: .color(activeColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
    }

    private func countdownColor(at fraction: Double) -> Color {
        let green = (red: 0.20, green: 0.82, blue: 0.36)
        let yellow = (red: 1.0, green: 0.78, blue: 0.10)
        let red = (red: 0.96, green: 0.22, blue: 0.18)
        let start = fraction < 0.5 ? green : yellow
        let end = fraction < 0.5 ? yellow : red
        let amount = fraction < 0.5 ? fraction * 2 : (fraction - 0.5) * 2
        return Color(
            red: start.red + (end.red - start.red) * amount,
            green: start.green + (end.green - start.green) * amount,
            blue: start.blue + (end.blue - start.blue) * amount
        )
    }
}

private struct MahjongHandTileHoverLift<Content: View>: View {
    let lift: CGFloat
    let content: Content
    @State private var isHovered = false

    init(lift: CGFloat, @ViewBuilder content: () -> Content) {
        self.lift = lift
        self.content = content()
    }

    var body: some View {
        content
            .offset(y: isHovered ? -lift : 0)
            .zIndex(isHovered ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

private struct MahjongHandTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

private struct MahjongDiscardBoard<WorkflowControls: View>: View {
    let game: MahjongGame
    let archive: MahjongArchiveStore
    @ObservedObject var lanRoomService: MahjongLANRoomService
    let onExit: () -> Void
    let roundNotice: String?
    let roundSettlement: MahjongArchiveSettlement?
    let onNextRound: () -> Void
    @ViewBuilder let workflowControls: () -> WorkflowControls

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let edgeInset: CGFloat = 8
            let infoGap = MahjongPlayerInfoCardMetrics.gap
            let handLength = MahjongSeatAreaMetrics.handLength
            let thickness = MahjongSeatAreaMetrics.areaThickness
            let zoneGap = MahjongSeatAreaMetrics.spacingBetweenAreas
            // Hands alone set the scale. Player cards are placed after the hands are centered.
            let verticalDesign = thickness + zoneGap + handLength + zoneGap + thickness * MahjongSeatAreaMetrics.localHandScale
            let horizontalDesign = thickness * 2 + zoneGap * 2 + handLength
            let boardScale = max(
                0.4,
                min(
                    min(width / 1_400, height / 920),
                    min(1.22, min(width, height) / max(verticalDesign, horizontalDesign))
                )
            )
            let horizontalZoneWidth = handLength
            // Every hand area stays within the centered discard block's width.
            let discardSpan = MahjongDiscardMetrics.sideWidth * 2
                + MahjongDiscardMetrics.horizontalWidth
                + MahjongDiscardMetrics.zoneGap * 2
            let maxHandScale = discardSpan / handLength
            let seatHandScale = min(1, maxHandScale)
            let sideClearance = edgeInset + thickness * boardScale + zoneGap * boardScale
            let localMeldSize = localMeldCornerSize()
            let localMeldVisualWidth = localMeldSize.width * boardScale
            let cornerLeading = localMeldVisualWidth > 0 ? edgeInset + localMeldVisualWidth + 16 : sideClearance
            let widthFitScale = (width - cornerLeading - sideClearance - 24) / max(horizontalZoneWidth * boardScale, 1)
            let minimumLocalScale: CGFloat = localMeldVisualWidth > 0 ? 0.85 : 1
            let localHandScale = min(
                MahjongSeatAreaMetrics.localHandScale,
                maxHandScale,
                max(widthFitScale, minimumLocalScale)
            )
            let localHandVisualHalf = thickness * boardScale * localHandScale / 2
            let localHandVisualWidth = horizontalZoneWidth * boardScale * localHandScale
            let localHandMinCenterX = cornerLeading + localHandVisualWidth / 2
            let localHandMaxCenterX = width - sideClearance - localHandVisualWidth / 2
            let localHandCenterX = min(max(width / 2, localHandMinCenterX), max(localHandMaxCenterX, localHandMinCenterX))
            let infoWidth = MahjongPlayerInfoCardMetrics.compactWidth
            let infoHeight = MahjongPlayerInfoCardMetrics.compactHeight
            let sideInfoWidth = MahjongPlayerInfoCardMetrics.sideWidth
            let sideInfoHeight = MahjongPlayerInfoCardMetrics.sideHeight
            let infoVisualHalf = infoHeight * boardScale / 2
            // Main-view info stays on the bottom edge. The hand sits just above it.
            let localInfoCenterX = width / 2
            let localInfoCenterY = height - edgeInset - infoVisualHalf
            let localHandCenterY = localInfoCenterY - infoVisualHalf - infoGap * boardScale - localHandVisualHalf
            let topHandCenterX = width / 2
            let topHandCenterY = edgeInset + thickness * boardScale * seatHandScale / 2
            let opponentHandBottom = topHandCenterY + thickness * boardScale * seatHandScale / 2
            let opponentHandVisualHalf = horizontalZoneWidth * boardScale * seatHandScale / 2
            let opponentInfoHalf = infoWidth * boardScale / 2
            let topInfoCenterX = min(
                width - edgeInset - opponentInfoHalf,
                topHandCenterX + opponentHandVisualHalf + infoGap * boardScale + opponentInfoHalf
            )
            let localHandTop = localHandCenterY - localHandVisualHalf
            let localHoverLift = MahjongSeatAreaMetrics.tileHeight / 3 * boardScale * localHandScale
            let seatGap = max(24, localHoverLift)
            // Left and right hands share the table's vertical center. Fitting them
            // between the other hands does not move that center.
            let sideHandCenterY = height / 2
            let sideTopRoom = sideHandCenterY - (opponentHandBottom + zoneGap * boardScale)
            let sideBottomRoom = (localHandTop - seatGap) - sideHandCenterY
            let sideSpan = max(0, min(sideTopRoom, sideBottomRoom) * 2)
            let sideFitScale = min(seatHandScale, sideSpan / max(handLength * boardScale, 1))
            let sideHandVisualHalfWidth = thickness * boardScale * sideFitScale / 2
            let sideHandVisualHalfHeight = handLength * boardScale * sideFitScale / 2
            let leftHandCenterX = edgeInset + sideHandVisualHalfWidth
            let rightHandCenterX = width - edgeInset - sideHandVisualHalfWidth
            let sideInfoHalfWidth = sideInfoWidth * boardScale / 2
            let sideInfoHalfHeight = sideInfoHeight * boardScale / 2
            let alongTile = MahjongSeatAreaMetrics.tileWidth
            let sideTileSpan = 14 * alongTile + 13 * MahjongSeatAreaMetrics.tileSpacing
            let sideTileHalf = min(sideHandVisualHalfHeight, sideTileSpan * boardScale * sideFitScale / 2)
            let infoGapScaled = infoGap * boardScale
            // Own left sits just outside the tiles. If that spot is off the table,
            // the card slides inward instead of covering the hand.
            let preferredLeftInfoY = sideHandCenterY - sideTileHalf - infoGapScaled - sideInfoHalfHeight
            let leftInfoCenterY = max(edgeInset + sideInfoHalfHeight, preferredLeftInfoY)
            let leftInfoOverlapsHand = leftInfoCenterY + sideInfoHalfHeight > sideHandCenterY - sideTileHalf
            let leftClearX = leftHandCenterX + sideHandVisualHalfWidth + infoGapScaled + sideInfoHalfWidth
            let leftInfoCenterX = min(
                width - edgeInset - sideInfoHalfWidth,
                leftInfoOverlapsHand ? leftClearX : max(edgeInset + sideInfoHalfWidth, leftHandCenterX)
            )
            // The right seat's own left is under the column. Keep the card there
            // and line its right edge up with the hand, even when the local hand
            // occupies the same vertical band farther toward the center.
            let rightHandRight = rightHandCenterX + sideHandVisualHalfWidth
            let rightInfoCenterX = min(
                width - edgeInset - sideInfoHalfWidth,
                max(edgeInset + sideInfoHalfWidth, rightHandRight - sideInfoHalfWidth)
            )
            let preferredRightInfoY = sideHandCenterY + sideTileHalf + infoGapScaled + sideInfoHalfHeight
            let rightInfoCenterY = min(
                height - edgeInset - sideInfoHalfHeight,
                max(edgeInset + sideInfoHalfHeight, preferredRightInfoY)
            )
            let frontGap = zoneGap * boardScale
            let sideMeldShift = sideHandVisualHalfWidth + frontGap + sideHandVisualHalfWidth
            ZStack {
                seatHand(actualSeat(at: 2), viewPosition: 2, width: horizontalZoneWidth, length: MahjongSeatAreaMetrics.areaThickness)
                    .frame(width: horizontalZoneWidth, height: MahjongSeatAreaMetrics.areaThickness, alignment: .center)
                    .scaleEffect(boardScale * seatHandScale)
                    .position(x: topHandCenterX, y: topHandCenterY)
                seatHand(actualSeat(at: 0), viewPosition: 0, width: horizontalZoneWidth, length: MahjongSeatAreaMetrics.areaThickness)
                    .frame(width: horizontalZoneWidth, height: MahjongSeatAreaMetrics.areaThickness, alignment: .center)
                    .scaleEffect(boardScale * localHandScale)
                    .position(x: localHandCenterX, y: localHandCenterY)

                seatHand(actualSeat(at: 1), viewPosition: 1, width: thickness, length: handLength)
                    .frame(width: thickness, height: handLength, alignment: .center)
                    .scaleEffect(boardScale * sideFitScale)
                    .position(x: leftHandCenterX, y: sideHandCenterY)
                seatHand(actualSeat(at: 3), viewPosition: 3, width: thickness, length: handLength)
                    .frame(width: thickness, height: handLength, alignment: .center)
                    .scaleEffect(boardScale * sideFitScale)
                    .position(x: rightHandCenterX, y: sideHandCenterY)

                frontMelds(viewPosition: 2)
                    .scaleEffect(boardScale * seatHandScale)
                    .position(
                        x: topHandCenterX,
                        y: opponentHandBottom + frontGap + MahjongSeatAreaMetrics.areaThickness * boardScale / 2
                    )
                frontMelds(viewPosition: 1)
                    .scaleEffect(boardScale * sideFitScale)
                    .position(x: leftHandCenterX + sideMeldShift, y: sideHandCenterY)
                frontMelds(viewPosition: 3)
                    .scaleEffect(boardScale * sideFitScale)
                    .position(x: rightHandCenterX - sideMeldShift, y: sideHandCenterY)

                playerInfoCard(for: actualSeat(at: 0), viewPosition: 0, width: infoWidth, height: infoHeight)
                    .scaleEffect(boardScale)
                    .position(x: localInfoCenterX, y: localInfoCenterY)
                playerInfoCard(for: actualSeat(at: 2), viewPosition: 2, width: infoWidth, height: infoHeight)
                    .scaleEffect(boardScale)
                    .position(x: topInfoCenterX, y: topHandCenterY)
                playerInfoCard(for: actualSeat(at: 1), viewPosition: 1, width: sideInfoWidth, height: sideInfoHeight)
                    .scaleEffect(boardScale)
                    .position(x: leftInfoCenterX, y: leftInfoCenterY)
                playerInfoCard(for: actualSeat(at: 3), viewPosition: 3, width: sideInfoWidth, height: sideInfoHeight)
                    .scaleEffect(boardScale)
                    .position(x: rightInfoCenterX, y: rightInfoCenterY)

                discardArea(width: width, height: height)
                    .scaleEffect(boardScale)
                    .position(x: width / 2, y: height / 2)

                if game.phase == .waitingForReady {
                    preparationControls
                        .fixedSize()
                        .position(x: width / 2, y: height / 2)
                }
                if game.phase == .roundEnded {
                    settlementControls
                        .fixedSize()
                        .position(x: width / 2, y: height / 2)
                }
            }
            .overlay(alignment: .bottomLeading) {
                localMeldCorner()
                    .scaleEffect(boardScale, anchor: .bottomLeading)
                    .padding(edgeInset)
            }
            .overlay(alignment: .bottomTrailing) {
                workflowControls()
                    .fixedSize()
                    .padding(16)
            }
        }
    }

    private func playerInfoCard(for seat: Int, viewPosition: Int, width: CGFloat, height: CGFloat) -> some View {
        let profile = playerProfile(for: seat)

        return MahjongPlayerInfoCard(
            profile: profile,
            seatName: game.seatName(seat),
            missingSuit: game.ruleset == .sichuan && game.missingSuits.indices.contains(seat)
                ? game.missingSuits[seat]
                : nil,
            countdownActive: game.isCountdownActive(for: seat),
            countdownDeadline: game.countdownDeadline(for: seat),
            stacksVertically: viewPosition == 1 || viewPosition == 3,
            detailArrowEdge: detailArrowEdge(for: viewPosition)
        )
            .frame(width: width, height: height)
            .accessibilityElement(children: .contain)
    }

    private func detailArrowEdge(for viewPosition: Int) -> Edge {
        switch viewPosition {
        case 1: .top
        case 2: .trailing
        case 3: .bottom
        default: .bottom
        }
    }

    private func actualSeat(at viewPosition: Int) -> Int {
        (game.localSeat + viewPosition) % 4
    }

    private func playerProfile(for seat: Int) -> MahjongPlayerArchive {
        if game.mode == .lan, let profile = lanRoomService.syncedProfiles[seat] {
            if seat == game.localSeat {
                return MahjongPlayerArchive(
                    id: archive.player.id, nickname: archive.player.nickname,
                    avatarStyle: archive.player.avatarStyle, customAvatarFilename: archive.player.customAvatarFilename,
                    balance: profile.balance, wins: profile.wins, losses: profile.losses, escapes: archive.player.escapes,
                    eliminatedDay: profile.eliminatedDay
                )
            }
            return profile
        }
        if game.mode == .lan, game.humanSeats.contains(seat) {
            if seat == game.localSeat { return archive.player }
            return MahjongPlayerArchive(id: "lan-seat-\(seat)", nickname: game.seatNicknames[seat], avatarStyle: .player, balance: 0)
        }
        if seat == 0 { return archive.player }
        if game.aiProfileIDs.indices.contains(seat - 1),
           let storedProfile = archive.profile(id: game.aiProfileIDs[seat - 1]) {
            return storedProfile
        }
        return MahjongPlayerArchive(
            id: "seat-\(seat)",
            nickname: game.seatName(seat),
            avatarStyle: .player,
            balance: 0,
            eliminatedDay: nil
        )
    }

    private func layoutDebugOverlay(
        width: CGFloat,
        height: CGFloat,
        boardScale: CGFloat,
        horizontalZoneWidth: CGFloat,
        sideMeldWidth: CGFloat,
        sideMeldX: CGFloat,
        seatRegionLength: CGFloat,
        operationWidth: CGFloat,
        operationCenterY: CGFloat
    ) -> some View {
        let sideMeldHeight = seatRegionLength
        let areaThickness = MahjongSeatAreaMetrics.areaThickness
        let playerInfoGap = MahjongPlayerInfoCardMetrics.gap
        let playerInfoHeight = MahjongPlayerInfoCardMetrics.height(areaThickness: areaThickness)
        let playerInfoWidth = MahjongPlayerInfoCardMetrics.width(areaThickness: areaThickness)

        return ZStack {
            debugRegion("\(game.seatName(actualSeat(at: 2)))手牌区", width: horizontalZoneWidth, height: areaThickness, scale: boardScale)
                .position(x: width / 2, y: 55 * boardScale)
            debugRegion("\(game.seatName(actualSeat(at: 0)))手牌区", width: horizontalZoneWidth, height: areaThickness, scale: boardScale)
                .position(x: width / 2, y: height - 55 * boardScale)
            debugRegion("\(game.seatName(actualSeat(at: 1)))手牌区", width: areaThickness, height: sideMeldHeight, scale: boardScale)
                .position(x: 52 * boardScale, y: height / 2)
            debugRegion("\(game.seatName(actualSeat(at: 3)))手牌区", width: areaThickness, height: sideMeldHeight, scale: boardScale)
                .position(x: width - 52 * boardScale, y: height / 2)

            debugRegion("\(game.seatName(actualSeat(at: 0)))玩家信息区", width: playerInfoWidth, height: playerInfoHeight, scale: boardScale)
                .position(
                    x: width / 2 - (horizontalZoneWidth / 2 + playerInfoGap + playerInfoWidth / 2) * boardScale,
                    y: height - (55 + (areaThickness + playerInfoGap) / 2) * boardScale
                )
            debugRegion("\(game.seatName(actualSeat(at: 2)))玩家信息区", width: playerInfoWidth, height: playerInfoHeight, scale: boardScale)
                .position(
                    x: width / 2 + (horizontalZoneWidth / 2 + playerInfoGap + playerInfoWidth / 2) * boardScale,
                    y: (55 + (areaThickness + playerInfoGap) / 2) * boardScale
                )
            debugRegion("\(game.seatName(actualSeat(at: 1)))玩家信息区", width: playerInfoWidth, height: playerInfoHeight, scale: boardScale)
                .position(
                    x: ((52 + sideMeldX) / 2 + (playerInfoWidth - playerInfoHeight) / 2) * boardScale,
                    y: height / 2 - (seatRegionLength / 2 + playerInfoGap + playerInfoHeight / 2) * boardScale
                )
            debugRegion("\(game.seatName(actualSeat(at: 3)))玩家信息区", width: playerInfoWidth, height: playerInfoHeight, scale: boardScale)
                .position(
                    x: width - ((52 + sideMeldX) / 2 + (playerInfoWidth - playerInfoHeight) / 2) * boardScale,
                    y: height / 2 + (seatRegionLength / 2 + playerInfoGap + playerInfoHeight / 2) * boardScale
                )

            debugRegion("\(game.seatName(game.localSeat))玩家操作区", width: operationWidth, height: MahjongSeatAreaMetrics.operationHeight, scale: boardScale)
                .position(x: width / 2, y: operationCenterY)

            debugRegion("\(game.seatName(actualSeat(at: 1)))弃牌区", width: MahjongDiscardMetrics.sideWidth, height: MahjongDiscardMetrics.sideAreaHeight, scale: boardScale)
                .position(MahjongDiscardMetrics.scaledCenter(for: 1, width: width, height: height, scale: boardScale))
            debugRegion("\(game.seatName(actualSeat(at: 3)))弃牌区", width: MahjongDiscardMetrics.sideWidth, height: MahjongDiscardMetrics.sideAreaHeight, scale: boardScale)
                .position(MahjongDiscardMetrics.scaledCenter(for: 3, width: width, height: height, scale: boardScale))
            debugRegion("\(game.seatName(actualSeat(at: 2)))弃牌区", width: MahjongDiscardMetrics.horizontalWidth, height: MahjongDiscardMetrics.horizontalHeight, scale: boardScale)
                .position(MahjongDiscardMetrics.scaledCenter(for: 2, width: width, height: height, scale: boardScale))
            debugRegion("\(game.seatName(actualSeat(at: 0)))弃牌区", width: MahjongDiscardMetrics.horizontalWidth, height: MahjongDiscardMetrics.horizontalHeight, scale: boardScale)
                .position(MahjongDiscardMetrics.scaledCenter(for: 0, width: width, height: height, scale: boardScale))
            debugRegion("玩家准备区", width: 620, height: 100)
                .position(x: width / 2, y: height / 2)
        }
    }

    private var preparationControls: some View {
        VStack(spacing: 10) {
            readyPlayerBadges
            Button("准备") { game.markReady() }
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .jarvisGlass(cornerRadius: 22, interactive: false)
    }

    private var settlementControls: some View {
        VStack(spacing: 14) {
            Text(game.winner.map { "恭喜【\(playerProfile(for: $0).nickname)】获得本局胜利" } ?? "本局流局")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(game.roundResult)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if let playerResults = roundSettlement?.playerResults, !playerResults.isEmpty {
                VStack(spacing: 5) {
                    ForEach(playerResults) { result in
                        HStack(spacing: 12) {
                            Text(result.nickname)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(signedBalanceChange(result.balanceChange))
                                .fontWeight(.semibold)
                                .foregroundStyle(result.balanceChange > 0 ? Color.green : (result.balanceChange < 0 ? Color.red : Color.secondary))
                                .frame(width: 112, alignment: .trailing)
                        }
                        .font(.system(size: 11, design: .rounded))
                    }
                }
                .frame(maxWidth: 300)
            }

            readyPlayerBadges

            if roundNotice?.contains("挑战获胜") == true || roundNotice?.contains("挑战已完成") == true {
                Button("返回档案") { onNextRound() }
                    .buttonStyle(JarvisSecondaryButtonStyle())
            } else {
                Button("再来一局") { onNextRound() }
                    .buttonStyle(JarvisSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .jarvisGlass(cornerRadius: 22, interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("牌局结算")
    }

    private var readyPlayerBadges: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { seat in
                if game.readySeats.indices.contains(seat), game.readySeats[seat] {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("\(playerProfile(for: seat).nickname)已就绪")
                    }
                    .mahjongAdaptiveTag()
                }
            }
        }
    }

    private func signedBalanceChange(_ value: Int) -> String {
        if value > 0 { return "+\(value.formatted()) 毛格子" }
        if value < 0 { return "−\(abs(value).formatted()) 毛格子" }
        return "0 毛格子"
    }

    private func debugRegion(_ title: String, width: CGFloat, height: CGFloat, scale: CGFloat = 1) -> some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .foregroundStyle(Color.red.opacity(0.9))
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))
                    .fixedSize()
                    .offset(x: 3, y: -11)
            }
            .scaleEffect(scale)
    }

    private func discardArea(width: CGFloat, height: CGFloat) -> some View {
        let palette = MahjongTablePalette(scheme: colorScheme)
        return ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.discardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(palette.discardStroke, lineWidth: 1)
                }
                .frame(
                    width: MahjongDiscardMetrics.sideWidth * 2
                        + MahjongDiscardMetrics.horizontalWidth + MahjongDiscardMetrics.zoneGap * 2,
                    height: MahjongDiscardMetrics.sideAreaHeight
                )
                .position(x: width / 2, y: height / 2)

            discardSeatZone(actualSeat(at: 1), viewPosition: 1)
                .frame(width: MahjongDiscardMetrics.sideWidth, height: MahjongDiscardMetrics.sideAreaHeight)
                .position(MahjongDiscardMetrics.center(for: 1, width: width, height: height))
            discardSeatZone(actualSeat(at: 3), viewPosition: 3)
                .frame(width: MahjongDiscardMetrics.sideWidth, height: MahjongDiscardMetrics.sideAreaHeight)
                .position(MahjongDiscardMetrics.center(for: 3, width: width, height: height))
            discardSeatZone(actualSeat(at: 2), viewPosition: 2)
                .frame(width: MahjongDiscardMetrics.horizontalWidth, height: MahjongDiscardMetrics.horizontalHeight)
                .position(MahjongDiscardMetrics.center(for: 2, width: width, height: height))
            discardSeatZone(actualSeat(at: 0), viewPosition: 0)
                .frame(width: MahjongDiscardMetrics.horizontalWidth, height: MahjongDiscardMetrics.horizontalHeight)
                .position(MahjongDiscardMetrics.center(for: 0, width: width, height: height))
        }
        .frame(width: width, height: height)
        .accessibilityLabel("四家已出牌区")
    }

    private func discardSeatZone(_ seat: Int, viewPosition: Int) -> some View {
        let isSide = viewPosition == 1 || viewPosition == 3
        let columnCount = isSide ? 4 : 7
        let cellWidth: CGFloat = isSide ? 68 : 48
        let cellHeight: CGFloat = isSide ? 48 : 68
        let tiles = discardGridCells(seat, viewPosition: viewPosition)
        let columns = Array(repeating: GridItem(.fixed(cellWidth), spacing: MahjongDiscardMetrics.tileSpacing), count: columnCount)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: MahjongDiscardMetrics.tileSpacing) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                if let tile {
                    orientedTile(tile, viewPosition: viewPosition)
                } else {
                    Color.clear
                        .frame(width: cellWidth, height: cellHeight)
                }
            }
        }
        .padding(MahjongDiscardMetrics.safetyInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func discardGridCells(_ seat: Int, viewPosition: Int) -> [MahjongTile?] {
        let localTiles = Array((game.discards.indices.contains(seat) ? game.discards[seat] : []).prefix(28))
        let columns = viewPosition == 1 || viewPosition == 3 ? 4 : 7
        let rows = viewPosition == 1 || viewPosition == 3 ? 7 : 4
        var cells = Array<MahjongTile?>(repeating: nil, count: columns * rows)

        for (index, tile) in localTiles.enumerated() {
            let localRow = index / 7
            let localColumn = index % 7
            let (screenRow, screenColumn): (Int, Int) = switch viewPosition {
            case 1: (localColumn, 3 - localRow)
            case 2: (3 - localRow, 6 - localColumn)
            case 3: (6 - localColumn, localRow)
            default: (localRow, localColumn)
            }
            cells[screenRow * columns + screenColumn] = tile
        }

        return cells
    }

    private func seatHand(_ seat: Int, viewPosition: Int, width: CGFloat, length: CGFloat) -> some View {
        let revealWinningHands = game.phase == .roundEnded && game.winner != nil
        let isVisible = revealWinningHands || seat == game.visibleHandSeat
        let isSideSeat = viewPosition == 1 || viewPosition == 3
        let visibleTiles = revealWinningHands || seat != game.visibleHandSeat
            ? (game.hands.indices.contains(seat) ? game.hands[seat] : [])
            : game.visibleHand
        let displayedTiles = handDisplayTiles(visibleTiles)
        let drawsSeparateTile = game.justDrew && seat == game.turn && displayedTiles.count > 1
        let baseTiles = drawsSeparateTile ? Array(displayedTiles.dropLast()) : displayedTiles
        let drawnTile = drawsSeparateTile ? displayedTiles.last : nil
        let drawDirection: CGFloat = viewPosition == 0 || viewPosition == 1 ? 1 : -1
        let baseWidth = baseHandWidth(baseTiles.count)
        let axisLength = isSideSeat ? length : width
        let hasReducedHand = baseTiles.count < 13
        // The local hand starts at local left when full, and centers when short.
        // The other three hands stay centered on their own side.
        let centersOnSide = viewPosition != 0
        let trailingSpan: CGFloat = drawnTile == nil
            ? 0
            : MahjongSeatAreaMetrics.drawGap + MahjongSeatAreaMetrics.tileWidth
        let handLeft: CGFloat = centersOnSide || hasReducedHand
            ? max(0, (axisLength - baseWidth - trailingSpan) / 2)
            : MahjongSeatAreaMetrics.safeInset
        let baseAxisPosition = screenAxis(handLeft + baseWidth / 2, axisLength: axisLength, growsPositive: drawDirection > 0)
        let drawnAxisPosition = screenAxis(
            handLeft + baseWidth + MahjongSeatAreaMetrics.drawGap + MahjongSeatAreaMetrics.tileWidth / 2,
            axisLength: axisLength,
            growsPositive: drawDirection > 0
        )

        return GeometryReader { geometry in
            ZStack {
                handRow(baseTiles, seat: seat, viewPosition: viewPosition, isVisible: isVisible, isSideSeat: isSideSeat)
                    .fixedSize()
                    .position(
                        x: isSideSeat ? geometry.size.width / 2 : baseAxisPosition,
                        y: isSideSeat ? baseAxisPosition : geometry.size.height / 2
                    )

                if let drawnTile {
                    handTileAtDrawPosition(drawnTile, seat: seat, viewPosition: viewPosition, isVisible: isVisible)
                        .position(
                            x: isSideSeat ? geometry.size.width / 2 : drawnAxisPosition,
                            y: isSideSeat ? drawnAxisPosition : geometry.size.height / 2
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(width: width, height: length, alignment: .center)
    }

    @ViewBuilder
    private func handRow(
        _ tiles: [MahjongHandDisplayTile],
        seat: Int,
        viewPosition: Int,
        isVisible: Bool,
        isSideSeat: Bool
    ) -> some View {
        if isSideSeat {
            VStack(spacing: MahjongSeatAreaMetrics.tileSpacing) {
                ForEach(tiles) { entry in
                    if isVisible {
                        sideHandTile(entry.tile, seat: seat, viewPosition: viewPosition)
                    } else {
                        sideOrientedHandBack(upsideDown: viewPosition == 3)
                    }
                }
            }
        } else {
            HStack(spacing: MahjongSeatAreaMetrics.tileSpacing) {
                ForEach(tiles) { entry in
                    if isVisible {
                        handTile(entry, seat: seat, hoverLift: seat == game.visibleHandSeat)
                    } else {
                        MahjongTileBackView()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func handTileAtDrawPosition(
        _ entry: MahjongHandDisplayTile,
        seat: Int,
        viewPosition: Int,
        isVisible: Bool
    ) -> some View {
        if isVisible {
            if viewPosition == 1 || viewPosition == 3 {
                sideHandTile(entry.tile, seat: seat, viewPosition: viewPosition)
            } else {
                handTile(entry, seat: seat, animated: false, isDrawnTile: true, hoverLift: seat == game.visibleHandSeat)
            }
        } else if viewPosition == 1 || viewPosition == 3 {
            sideOrientedHandBack(upsideDown: viewPosition == 3)
        } else {
            MahjongTileBackView()
        }
    }

    @ViewBuilder
    private func sideHandTile(_ tile: MahjongTile, seat: Int, viewPosition: Int) -> some View {
        let isMissingSuit = isMissingSuitTile(tile, seat: seat)
        if game.isHumanTurn {
            Button { game.discard(tile) } label: {
                sideOrientedHandTile(tile, upsideDown: viewPosition == 3, isMissingSuit: isMissingSuit)
            }
            .buttonStyle(MahjongHandTileButtonStyle())
            .transition(.scale(scale: 0.76).combined(with: .opacity))
        } else {
            sideOrientedHandTile(tile, upsideDown: viewPosition == 3, isMissingSuit: isMissingSuit)
                .transition(.scale(scale: 0.76).combined(with: .opacity))
        }
    }

    private func handDisplayTiles(_ tiles: [MahjongTile]) -> [MahjongHandDisplayTile] {
        var occurrences: [String: Int] = [:]
        return tiles.map { tile in
            let occurrence = occurrences[tile.id, default: 0]
            occurrences[tile.id] = occurrence + 1
            return MahjongHandDisplayTile(id: "\(tile.id)-\(occurrence)", tile: tile)
        }
    }

    private func baseHandWidth(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count * 48 + (count - 1) * 2)
    }

    private func screenAxis(_ localCenter: CGFloat, axisLength: CGFloat, growsPositive: Bool) -> CGFloat {
        growsPositive ? localCenter : axisLength - localCenter
    }

    private func seatHasMelds(_ seat: Int) -> Bool {
        game.melds.indices.contains(seat) && !game.melds[seat].isEmpty
    }

    /// Other players' exposed melds sit in a strip just in front of that hand.
    @ViewBuilder
    private func frontMelds(viewPosition: Int) -> some View {
        let seat = actualSeat(at: viewPosition)
        if seatHasMelds(seat) {
            handMeldRow(seat: seat, viewPosition: viewPosition)
                .fixedSize()
        }
    }

    /// Main-view melds occupy the bottom-left corner, up to two rows of two groups.
    @ViewBuilder
    private func localMeldCorner() -> some View {
        let seat = actualSeat(at: 0)
        let melds = Array(meldsInSeatOrder(seat, viewPosition: 0).prefix(4))
        if !melds.isEmpty {
            let top = Array(melds.prefix(2))
            let bottom = Array(melds.dropFirst(2))
            VStack(alignment: .leading, spacing: MahjongSeatAreaMetrics.meldGroupGap) {
                meldCornerRow(top, seat: seat)
                if !bottom.isEmpty {
                    meldCornerRow(bottom, seat: seat)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func meldCornerRow(_ melds: [MahjongMeld], seat: Int) -> some View {
        HStack(alignment: .top, spacing: MahjongSeatAreaMetrics.meldGroupGap) {
            ForEach(melds) { meld in
                meldGroup(meld, seat: seat, viewPosition: 0, isSide: false)
            }
        }
    }

    private func localMeldCornerSize() -> CGSize {
        let seat = actualSeat(at: 0)
        let melds = Array(meldsInSeatOrder(seat, viewPosition: 0).prefix(4))
        guard !melds.isEmpty else { return .zero }
        func rowWidth(_ row: ArraySlice<MahjongMeld>) -> CGFloat {
            let widths = row.map { uprightMeldWidth($0) }
            let gaps = MahjongSeatAreaMetrics.meldGroupGap * CGFloat(max(0, widths.count - 1))
            return widths.reduce(0, +) + gaps
        }
        let width = max(rowWidth(melds.prefix(2)), rowWidth(melds.dropFirst(2)))
        let rows: CGFloat = melds.count > 2 ? 2 : 1
        let height = rows * MahjongSeatAreaMetrics.tileHeight
            + (rows - 1) * MahjongSeatAreaMetrics.meldGroupGap
        return CGSize(width: width, height: height)
    }

    private func uprightMeldWidth(_ meld: MahjongMeld) -> CGFloat {
        let count = max(meld.tiles.count, 1)
        return CGFloat(count) * MahjongSeatAreaMetrics.tileWidth
            + CGFloat(count - 1) * MahjongSeatAreaMetrics.tileSpacing
    }

    @ViewBuilder
    private func handTile(
        _ entry: MahjongHandDisplayTile,
        seat: Int,
        animated: Bool = true,
        isDrawnTile: Bool = false,
        hoverLift: Bool = false
    ) -> some View {
        let isMissingSuit = isMissingSuitTile(entry.tile, seat: seat)
        if game.isHumanTurn {
            Button {
                if isDrawnTile {
                    game.discardDrawnTile()
                } else if animated {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                        game.discard(entry.tile)
                    }
                } else {
                    game.discard(entry.tile)
                }
            } label: {
                handTileFace(entry, hoverLift: hoverLift, isMissingSuit: isMissingSuit)
            }
            .buttonStyle(MahjongHandTileButtonStyle())
            .transition(.scale(scale: 0.76).combined(with: .opacity))
        } else {
            handTileFace(entry, hoverLift: hoverLift, isMissingSuit: isMissingSuit)
                .transition(.scale(scale: 0.76).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func handTileFace(_ entry: MahjongHandDisplayTile, hoverLift: Bool, isMissingSuit: Bool) -> some View {
        let tile = MahjongTileView(tile: entry.tile, isSelected: false, isMissingSuit: isMissingSuit)
        if hoverLift {
            MahjongHandTileHoverLift(lift: MahjongSeatAreaMetrics.tileHeight / 3) {
                tile
            }
        } else {
            tile
        }
    }

    private func sideOrientedHandTile(_ tile: MahjongTile, upsideDown: Bool = false, isMissingSuit: Bool = false) -> some View {
        MahjongTileView(tile: tile, isSelected: false, isMissingSuit: isMissingSuit)
            .rotationEffect(.degrees(upsideDown ? 270 : 90))
            .frame(width: 68, height: 48)
    }

    private func isMissingSuitTile(_ tile: MahjongTile, seat: Int) -> Bool {
        guard game.ruleset == .sichuan,
              game.missingSuits.indices.contains(seat),
              let missingSuit = game.missingSuits[seat],
              case let .suited(suit, _) = tile else { return false }
        return suit == missingSuit
    }

    private func sideOrientedHandBack(upsideDown: Bool = false) -> some View {
        MahjongTileBackView()
            .rotationEffect(.degrees(upsideDown ? 270 : 90))
            .frame(width: 68, height: 48)
    }

    private func orientedTile(_ tile: MahjongTile, viewPosition: Int) -> some View {
        let rotation: Double = switch viewPosition {
        case 1: 90
        case 2: 180
        case 3: 270
        default: 0
        }
        let isSideways = viewPosition == 1 || viewPosition == 3
        return MahjongTileView(tile: tile, isSelected: false)
            .rotationEffect(.degrees(rotation))
            .frame(width: isSideways ? 68 : 48, height: isSideways ? 48 : 68)
    }

    @ViewBuilder
    private func handMeldRow(seat: Int, viewPosition: Int) -> some View {
        let isSide = viewPosition == 1 || viewPosition == 3
        let groups = meldsInSeatOrder(seat, viewPosition: viewPosition)
        Group {
            if isSide {
                VStack(alignment: .center, spacing: MahjongSeatAreaMetrics.meldGroupGap) {
                    ForEach(groups) { meld in
                        meldGroup(meld, seat: seat, viewPosition: viewPosition, isSide: true)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: MahjongSeatAreaMetrics.meldGroupGap) {
                    ForEach(groups) { meld in
                        meldGroup(meld, seat: seat, viewPosition: viewPosition, isSide: false)
                    }
                }
            }
        }
        .accessibilityLabel("\(game.seatName(seat)) 的吃碰杠明牌")
    }

    private func meldGroup(_ meld: MahjongMeld, seat: Int, viewPosition: Int, isSide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if isSide {
                VStack(spacing: 2) {
                    ForEach(Array(meldTilesInSeatOrder(meld, viewPosition: viewPosition).enumerated()), id: \.offset) { _, tile in
                        orientedTile(tile, viewPosition: viewPosition)
                    }
                }
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(meldTilesInSeatOrder(meld, viewPosition: viewPosition).enumerated()), id: \.offset) { _, tile in
                        orientedTile(tile, viewPosition: viewPosition)
                    }
                }
            }
        }
    }

    private func meldTilesInSeatOrder(_ meld: MahjongMeld, viewPosition: Int) -> [MahjongTile] {
        let sorted = meld.tiles.sorted { $0.sortKey < $1.sortKey }
        // A player seated across or to the right sees screen order reversed.
        return viewPosition == 2 || viewPosition == 3 ? Array(sorted.reversed()) : sorted
    }

    private func meldsInSeatOrder(_ seat: Int, viewPosition: Int) -> [MahjongMeld] {
        guard game.melds.indices.contains(seat) else { return [] }
        let melds = game.melds[seat]
        // The across and right seats have their local left edge on the screen's right/bottom.
        return viewPosition == 2 || viewPosition == 3 ? Array(melds.reversed()) : melds
    }
}

private struct MahjongTileBackView: View {
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
        ZStack {
            RoundedRectangle(cornerRadius: compact ? 3 : 9, style: .continuous)
                .fill(palette.tileSide)
                .offset(x: compact ? 1 : 3 * scale, y: compact ? -1.2 : -4 * scale)
            RoundedRectangle(cornerRadius: compact ? 3 : 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.88, green: 0.74, blue: 0.48), Color(red: 0.67, green: 0.50, blue: 0.28)], startPoint: .top, endPoint: .bottom))
                .offset(x: compact ? 0.5 : 1.5 * scale, y: compact ? -0.6 : -2 * scale)
            RoundedRectangle(cornerRadius: compact ? 3 : 9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isMissingSuit
                            ? [Color(red: 1.0, green: 0.82, blue: 0.82), Color(red: 0.97, green: 0.69, blue: 0.70)]
                            : [Color(red: 1.0, green: 1.0, blue: 0.98), Color(red: 0.97, green: 0.96, blue: 0.91)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(palette.tileShadowOpacity(compact: compact)), radius: compact ? 0.8 : 2.5, x: compact ? 0.5 : 1.5, y: compact ? -0.8 : -1.5)
            RoundedRectangle(cornerRadius: compact ? 3 : 9, style: .continuous)
                .strokeBorder(Color(red: 0.24, green: 0.21, blue: 0.19), lineWidth: compact ? 0.65 : 1.35 * scale)
            MahjongTileFace(tile: tile, compact: compact, rotation: faceRotation, scale: scale)
                .padding(compact ? 1 : 0)
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
        for index in 0..<16 {
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
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
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
        func p(_ x: CGFloat, _ y: CGFloat, _ ink: MahjongTileInk) -> Pip { Pip(x: x, y: y, ink: ink) }
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
        func p(_ x: CGFloat, _ y: CGFloat, _ ink: MahjongTileInk = .green) -> Pip { Pip(x: x, y: y, ink: ink) }
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

private struct MahjongLANRoomView: View {
    let localProfile: MahjongPlayerArchive
    let onStart: (MahjongLANRoomService) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = MahjongLANRoomService()
    @State private var roomCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("局域网麻将")
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
                    Button("创建房间") { service.createRoom() }
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
                                        Text("麻将房间")
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
