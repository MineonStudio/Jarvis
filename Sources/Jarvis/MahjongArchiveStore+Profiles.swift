import Foundation
import Observation

extension MahjongArchiveStore {
    /// The LAN host owns settlement values; a guest mirrors the participating AI archives.
    func applyLANAIProfiles(_ remoteProfiles: [MahjongPlayerArchive]) {
        var changed = false
        for remote in remoteProfiles {
            guard let index = aiProfiles.firstIndex(where: { $0.id == remote.id }) else { continue }
            let current = aiProfiles[index]
            let balance = max(0, remote.balance)
            guard current.balance != balance || current.wins != remote.wins
                || current.losses != remote.losses || current.escapes != remote.escapes
                || current.eliminatedDay != remote.eliminatedDay else { continue }
            aiProfiles[index].balance = balance
            aiProfiles[index].wins = remote.wins
            aiProfiles[index].losses = remote.losses
            aiProfiles[index].escapes = remote.escapes
            aiProfiles[index].eliminatedDay = remote.eliminatedDay
            changed = true
        }
        if changed {
            save()
        }
    }

    func updatePlayerProfile(
        nickname: String? = nil,
        avatarStyle: MahjongArchiveAvatarStyle? = nil,
        voiceGender: MahjongVoiceGender? = nil
    ) {
        if let nickname {
            let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                player.nickname = String(trimmed.prefix(16))
            }
        }
        if let avatarStyle {
            player.avatarStyle = avatarStyle
            player.customAvatarFilename = nil
        }
        if let voiceGender {
            player.voiceGender = voiceGender
        }
        save()
    }

    func updateAIVoiceGender(profileID: String, voiceGender: MahjongVoiceGender) {
        guard let index = aiProfiles.firstIndex(where: { $0.id == profileID }) else { return }
        aiProfiles[index].voiceGender = voiceGender
        save()
    }

    static var avatarDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jarvis/MahjongAvatars", isDirectory: true)
    }

    /// Validate the AI roster once on the first match of the local calendar day.
    func prepareAIOpponents() -> [String] {
        if lastAIRosterCheckDay != dayKey {
            for index in aiProfiles.indices where aiProfiles[index].balance < Self.initialBalance {
                aiProfiles[index].balance = Self.initialBalance
            }
            lastAIRosterCheckDay = dayKey
        }
        let eligible = aiProfiles.filter { $0.balance > 0 && $0.eliminatedDay != dayKey }.shuffled()
        save()
        return Array(eligible.prefix(3).map(\.id))
    }

    /// After a round, preserve funded opponents and fill bankrupt seats from the unused roster.
    func replacingBankruptOpponents(_ currentIDs: [String]) -> [String] {
        var next = currentIDs
        let eligible = aiProfiles.filter { profile in
            profile.balance > 0 && profile.eliminatedDay != dayKey && !currentIDs.contains(profile.id)
        }.shuffled()
        var replacementIndex = 0
        for index in next.indices {
            guard (profile(id: next[index])?.balance ?? 0) <= 0 else { continue }
            if replacementIndex < eligible.count {
                next[index] = eligible[replacementIndex].id
                replacementIndex += 1
            } else {
                next[index] = ""
            }
        }
        return next
    }
}
