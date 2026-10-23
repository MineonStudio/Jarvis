import AppKit
import SwiftUI

struct GamePlazaView: View {
    @State private var selectedCategory: GamePlazaCategory = .all
    @State private var game = MahjongGame()
    @State private var archive = MahjongArchiveStore()
    @State private var lanRoomService: MahjongLANRoomService?
    @State private var idleLANRoomService = MahjongLANRoomService()
    @State private var latestSettlement: MahjongArchiveSettlement?
    @State private var lastSettledRoundNumber = 0
    @State private var gameWindowModel: MahjongGameWindowModel?

    private var gameWindow: MahjongGameWindowController {
        .shared
    }

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                JarvisToolbarSurface(id: "games.category", placement: .navigation) {
                    JarvisToolbarGroupedPicker(
                        items: GamePlazaCategory.allCases,
                        selection: $selectedCategory,
                        title: \.rawValue
                    )
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) { EmptyView() }
            },
            content: {
                ScrollView {
                    GamePlazaGallery(category: selectedCategory, onStartMahjong: presentGameWindow)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(24)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .jarvisModulePanel()
            }
        )
        .onChange(of: game.phase) { _, phase in
            if phase == .waitingForReady, game.roundNumber > lastSettledRoundNumber {
                latestSettlement = nil
            }
            guard phase == .roundEnded, lastSettledRoundNumber != game.roundNumber else { return }
            if game.mode == .lan {
                guard let service = lanRoomService else { return }
                if !service.isHosting {
                    if game.winner == nil {
                        recordCurrentMatch(settlement: nil)
                        lastSettledRoundNumber = game.roundNumber
                    } else if let settlement = service.settlement {
                        applyGuestSettlement(settlement, service: service)
                    }
                    return
                }
                settleLANRound(using: service)
            } else {
                settleRound()
            }
        }
        .onReceive((lanRoomService ?? idleLANRoomService).$settlement) { settlement in
            guard game.mode == .lan, let service = lanRoomService, !service.isHosting,
                  let settlement, game.phase == .roundEnded else { return }
            applyGuestSettlement(settlement, service: service)
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
        }
        .onChange(of: latestSettlement) { _, settlement in
            gameWindowModel?.roundNotice = settlement?.notice
            gameWindowModel?.roundSettlement = settlement
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
        game.configureLAN(humanSeats: [0], localSeat: 0, authority: true)
        game.onLANAction = nil
        game.assignAIProfiles(profiles)
        let archive = archive
        game.onRoundBalancesRequested = { [weak game] in
            guard let game else { return [] }
            return [archive.player.balance] + game.aiProfileIDs.map { archive.profile(id: $0)?.balance ?? 0 }
        }
        let aiProfileIDs = game.aiProfileIDs
        game.onMahjongVoiceCue = { cue in
            let gender: MahjongVoiceGender = if cue.seat == 0 {
                archive.player.voiceGender
            } else if aiProfileIDs.indices.contains(cue.seat - 1),
                      let profile = archive.profile(id: aiProfileIDs[cue.seat - 1])
            {
                profile.voiceGender
            } else {
                .female
            }
            MahjongVoicePlayer.shared.play(cue.key, gender: gender, seat: cue.seat)
        }
        game.start()
        lastSettledRoundNumber = 0
        latestSettlement = nil
        presentGameWindow()
    }

    private func exitMatch() {
        if game.isStarted, game.phase != .roundEnded {
            archive.recordVoluntaryEscape()
        }
        game.leaveTable()
        lanRoomService?.stop()
        lanRoomService = nil
        latestSettlement = nil
        gameWindowModel?.roundNotice = nil
        gameWindowModel?.roundSettlement = nil
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
        model.onStartSolo = { ruleset in
            game.ruleset = ruleset
            startSoloMatch()
            model.roundNotice = latestSettlement?.notice
        }
        model.onStartLAN = { service in startLANMatch(service) }
        model.onCloseMenu = {
            exitMatch()
            model.menuLANRoomService.stop()
            gameWindow.hide()
        }
        gameWindow.onUserClose = {
            exitMatch()
            model.menuLANRoomService.stop()
        }
        gameWindow.show(model: model)
    }

    private func startLANMatch(_ service: MahjongLANRoomService) {
        lanRoomService = service
        game.mode = .lan
        game.ruleset = service.roomRuleset
        if service.isHosting {
            let archive = archive
            game.onMahjongVoiceCue = { [weak service] cue in
                let gender = service?.syncedProfiles[cue.seat]?.voiceGender ?? archive.player.voiceGender
                MahjongVoicePlayer.shared.play(cue.key, gender: gender, seat: cue.seat)
                service?.broadcastVoiceCue(cue)
            }
        } else {
            game.onMahjongVoiceCue = nil
        }
        lastSettledRoundNumber = 0
        latestSettlement = nil
        if service.isHosting {
            let aiIDs = archive.prepareAIOpponents()
            game.assignAIProfiles(aiIDs)
            let aiProfiles = aiIDs.compactMap { archive.profile(id: $0) }
            service.startHostGame(game, profile: archive.player, aiProfiles: aiProfiles)
            game.start()
        } else {
            service.startJoinedGame(game, profile: archive.player)
        }
        presentGameWindow()
    }

    private func startNextRound() {
        guard latestSettlement?.campaignComplete != true,
              latestSettlement?.playerNeedsExit != true else { return }
        if game.mode == .lan {
            lanRoomService?.clearSettlement()
            game.nextRound()
            return
        }
        game.assignAIProfiles(archive.replacingBankruptOpponents(game.aiProfileIDs))
        game.nextRound()
    }

    private func settleRound() {
        lastSettledRoundNumber = game.roundNumber
        guard let winner = game.winner else {
            latestSettlement = nil
            recordCurrentMatch(settlement: nil)
            return
        }
        let settlement = archive.settle(
            winnerSeat: winner,
            discarderSeat: game.discarder,
            handType: game.winningHandType,
            byDiscard: game.winByDiscard,
            winnerConcealed: game.melds[winner].allSatisfy { $0.kind == .concealedKong },
            seatProfileIDs: ["player"] + game.aiProfileIDs,
            multipliers: game.multipliers.map { $0 ?? 1 }
        )
        latestSettlement = settlement
        recordCurrentMatch(settlement: settlement)
        if settlement.playerNeedsExit {
            game.leaveTable()
            return
        }
        if settlement.campaignComplete {
            game.declareCampaignComplete()
        }
    }

    private func settleLANRound(using service: MahjongLANRoomService) {
        lastSettledRoundNumber = game.roundNumber
        guard let winner = game.winner else {
            latestSettlement = nil
            recordCurrentMatch(settlement: nil)
            return
        }
        var seats = (0 ..< 4).map { seat in
            service.syncedProfiles[seat] ?? MahjongPlayerArchive(
                id: "empty-seat-\(seat)", nickname: game.seatName(seat), avatarStyle: .player, balance: 0
            )
        }
        seats[0] = archive.player
        let result = archive.settleLAN(
            winnerSeat: winner,
            discarderSeat: game.discarder,
            handType: game.winningHandType,
            byDiscard: game.winByDiscard,
            winnerConcealed: game.melds[winner].allSatisfy { $0.kind == .concealedKong },
            seatProfiles: seats,
            multipliers: game.multipliers.map { $0 ?? 1 }
        )
        latestSettlement = result.settlement
        recordCurrentMatch(settlement: result.settlement)
        service.publishSettlement(result.settlement, profiles: result.profiles)
    }

    private func recordCurrentMatch(settlement: MahjongArchiveSettlement?) {
        let localSeat = game.mode == .lan ? game.localSeat : 0
        let seatProfileIDs = (0 ..< 4).map { seat in
            if let settlement, settlement.playerResults.indices.contains(seat) {
                return settlement.playerResults[seat].profileID
            }
            if game.mode == .lan {
                return lanRoomService?.syncedProfiles[seat]?.id ?? ""
            }
            return seat == 0 ? archive.player.id
                : (game.aiProfileIDs.indices.contains(seat - 1) ? game.aiProfileIDs[seat - 1] : "")
        }
        let seatNames = (0 ..< 4).map { seat in
            if let settlement, settlement.playerResults.indices.contains(seat) {
                return settlement.playerResults[seat].nickname
            }
            return (game.mode == .lan ? lanRoomService?.syncedProfiles[seat]?.nickname
                : archive.profile(id: seatProfileIDs[seat])?.nickname) ?? game.seatName(seat)
        }
        archive.recordRound(MahjongRoundArchiveInput(
            mode: game.mode,
            ruleset: game.ruleset,
            roundNumber: game.roundNumber,
            winnerSeat: game.winner,
            localSeat: localSeat,
            humanSeats: game.humanSeats,
            seatProfileIDs: seatProfileIDs,
            seatNames: seatNames,
            settlement: settlement
        ))
    }

    private func applyGuestSettlement(_ settlement: MahjongArchiveSettlement, service: MahjongLANRoomService) {
        guard lastSettledRoundNumber != game.roundNumber else { return }
        latestSettlement = settlement
        if let profile = service.syncedProfiles[game.localSeat] {
            archive.applyLANPlayerProfile(profile)
        }
        archive.applyLANAIProfiles((0 ..< 4).filter { !game.humanSeats.contains($0) }
            .compactMap { service.syncedProfiles[$0] })
        recordCurrentMatch(settlement: settlement)
        lastSettledRoundNumber = game.roundNumber
    }
}
