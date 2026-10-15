import CryptoKit
import Foundation

enum MeetingMinutesError: LocalizedError, Equatable {
    case schemaRejected
    case network
    case quota
    case tooLong
    case stalled

    var errorDescription: String? {
        switch self {
        case .schemaRejected:
            "纪要格式连续两次不合格，没有写入半成品。逐字稿已保留，可以重试。"
        case .network:
            "生成纪要时网络不可用。逐字稿已保留，可以重试。"
        case .quota:
            "AI 服务额度不足。逐字稿已保留，可以稍后重试。"
        case .tooLong:
            "逐字稿过长，模型没有完成纪要。逐字稿已保留，可以重试。"
        case .stalled:
            "AI 服务长时间没有返回内容，已放弃这次请求。逐字稿已保留，可以重试。"
        }
    }

    static func classify(_ error: Error) -> Error {
        if error is CancellationError || error is MeetingMinutesError {
            return error
        }
        if let apiError = error as? AIAPIError, apiError.isStreamInterruption {
            return MeetingMinutesError.stalled
        }
        if error is URLError {
            return MeetingMinutesError.network
        }
        let description = error.localizedDescription
        // DeepSeek reports an empty account as "Insufficient Balance", not 429 or quota.
        // Bare "余额" or "balance" is not a billing refusal.
        if description.contains("429")
            || description.contains("额度")
            || description.contains("余额不足")
            || description.localizedCaseInsensitiveContains("insufficient balance")
            || description.localizedCaseInsensitiveContains("quota")
        {
            return MeetingMinutesError.quota
        }
        if description.localizedCaseInsensitiveContains("context")
            || description.contains("过长")
            || description.contains("maximum context")
        {
            return MeetingMinutesError.tooLong
        }
        return error
    }
}

/// What the meeting view shows while the answer is still being written.
enum MeetingSummaryLiveUpdate: Equatable, Sendable {
    /// The model has started answering: thinking tokens are arriving, no minutes yet.
    case thinking
    case draft(MeetingSummary)
}

struct MeetingSummaryService: Sendable {
    typealias CheckpointHandler = @MainActor @Sendable (MeetingSummaryCheckpoint) -> Void
    typealias ProgressHandler = @MainActor @Sendable (Double?) -> Void
    typealias LiveHandler = @MainActor @Sendable (MeetingSummaryLiveUpdate) -> Void

    let api: any AITextCompletionAPI
    var policy: AIStreamingPolicy = .default
    var budgets: AIContextBudgetStore = .shared

    private static let maxConcurrentSummaryRequests = 3

    func summarize(
        record: MeetingRecord,
        configuration: AIAPIConfiguration,
        checkpoint: MeetingSummaryCheckpoint? = nil,
        preserveUserEdits: Bool = true,
        onCheckpoint: CheckpointHandler? = nil,
        onProgress: ProgressHandler? = nil,
        onLiveUpdate: LiveHandler? = nil
    ) async throws -> MeetingSummary {
        do {
            return try await summarizeUnchecked(
                record: record,
                configuration: configuration,
                checkpoint: checkpoint,
                preserveUserEdits: preserveUserEdits,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress,
                onLiveUpdate: onLiveUpdate
            )
        } catch {
            throw MeetingMinutesError.classify(error)
        }
    }

    private func summarizeUnchecked(
        record: MeetingRecord,
        configuration: AIAPIConfiguration,
        checkpoint: MeetingSummaryCheckpoint?,
        preserveUserEdits: Bool,
        onCheckpoint: CheckpointHandler?,
        onProgress: ProgressHandler?,
        onLiveUpdate: LiveHandler?
    ) async throws -> MeetingSummary {
        guard !record.transcript.isEmpty else {
            throw AIAPIError.emptyGeneratedContent(context: "会议逐字稿")
        }
        let fingerprint = transcriptFingerprint(record.transcript)
        if let finished = resumableFinishedSummary(checkpoint, fingerprint: fingerprint) {
            return preserveUserEdits
                ? MeetingMinutesAlgorithm.merging(finished, preserving: record.summary)
                : finished
        }

        let context = SummaryContext(
            record: record,
            configuration: configuration,
            index: TranscriptIndex(transcript: record.transcript),
            generation: MeetingMinutesGeneration(
                modelName: configuration.model,
                promptVersion: MeetingMinutesAlgorithm.promptVersion,
                generatedAt: Date(),
                transcriptFingerprint: fingerprint
            ),
            fingerprint: fingerprint,
            speakerNames: record.speakers.map(\.name)
        )
        let lines = MeetingTranscriptFormat.render(
            segments: record.transcript,
            speakerNames: Dictionary(uniqueKeysWithValues: record.speakers.map { ($0.id, $0.name) }),
            shortIDs: context.index.shortIDs
        ).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // One request covers a normal meeting. Splitting is for models that cannot take
        // the whole transcript, not the default path.
        let windows = MeetingTranscriptFormat.windows(
            forLines: lines,
            budget: budgets.budget(for: configuration)
        )
        guard !windows.isEmpty else {
            throw AIAPIError.emptyGeneratedContent(context: "会议逐字稿")
        }

        if windows.count == 1 {
            await report(nil, to: onProgress)
            let summary = try await summarizedWindow(
                window: windows[0],
                windowLabel: nil,
                context: context,
                onLiveUpdate: onLiveUpdate
            )
            let finished = try await consolidated(summary, context: context)
            let merged = preserveUserEdits
                ? MeetingMinutesAlgorithm.merging(finished, preserving: record.summary)
                : finished
            await publish(
                finishedCheckpoint(
                    fingerprint: fingerprint,
                    chunkCount: 1,
                    windows: [finished],
                    finished: merged
                ),
                to: onCheckpoint
            )
            return merged
        }

        let resumable = resumableCheckpoint(checkpoint, fingerprint: fingerprint, chunkCount: windows.count)
        var windowSummaries = resumable?.windowSummaries ?? []
        let completed = min(windowSummaries.count, windows.count)
        await report(
            Self.summaryProgress(
                completedChunks: completed,
                totalChunks: windows.count,
                completedSynthesisSteps: 0,
                totalSynthesisSteps: 1
            ),
            to: onProgress
        )

        if completed < windows.count {
            windowSummaries = try await requestWindows(
                windows: windows,
                completed: completed,
                summaries: windowSummaries,
                context: context,
                onCheckpoint: onCheckpoint,
                onProgress: onProgress,
                onLiveUpdate: onLiveUpdate
            )
        }

        await report(
            Self.summaryProgress(
                completedChunks: windows.count,
                totalChunks: windows.count,
                completedSynthesisSteps: 0,
                totalSynthesisSteps: 1
            ),
            to: onProgress
        )
        let outcome = try await reduce(
            summaries: windowSummaries,
            context: context,
            onLiveUpdate: onLiveUpdate
        )
        // A stitched overview is a concatenation by construction, so it is always outside
        // the preferred length. Asking the model to shorten it would be one more request
        // than the run that just failed could afford.
        let finished = outcome.isStitched
            ? outcome.summary
            : try await consolidated(outcome.summary, context: context)
        let merged = preserveUserEdits
            ? MeetingMinutesAlgorithm.merging(finished, preserving: record.summary)
            : finished
        await report(
            Self.summaryProgress(
                completedChunks: windows.count,
                totalChunks: windows.count,
                completedSynthesisSteps: 1,
                totalSynthesisSteps: 1
            ),
            to: onProgress
        )
        await publish(
            finishedCheckpoint(
                fingerprint: fingerprint,
                chunkCount: windows.count,
                windows: windowSummaries,
                finished: merged
            ),
            to: onCheckpoint
        )
        return merged
    }

    /// Extraction fills the first 80% of the bar. The merge uses the rest, and
    /// stops at 99 so 100% is reserved for the finished state.
    static func summaryProgress(
        completedChunks: Int,
        totalChunks: Int,
        completedSynthesisSteps: Int,
        totalSynthesisSteps: Int
    ) -> Double {
        let safeChunks = max(totalChunks, 1)
        let extraction = 0.8 * Double(min(max(completedChunks, 0), safeChunks)) / Double(safeChunks)
        let safeSteps = max(totalSynthesisSteps, 1)
        let synthesis = 0.19 * Double(min(max(completedSynthesisSteps, 0), safeSteps)) / Double(safeSteps)
        return min(0.99, extraction + synthesis)
    }

    static func extractJSONObject(_ raw: String) -> String {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = normalized.firstIndex(of: "{"),
              let end = normalized.lastIndex(of: "}"),
              start < end
        else {
            return normalized
        }
        return String(normalized[start ... end])
    }

    // MARK: - One request

    /// Everything the model produced is already usable; the only thing worth a second call
    /// is an overview outside the requested length, and that second call carries nothing but
    /// the overview itself.
    private func consolidated(
        _ summary: MeetingSummary,
        context: SummaryContext
    ) async throws -> MeetingSummary {
        guard MeetingMinutesAlgorithm.summaryOutsidePreferredRange(summary.overview) else {
            return summary
        }
        return try await repairedOverview(summary, context: context)
    }

    /// A repair is cosmetic: if it fails, the minutes that already exist are kept. Cancelling
    /// is not a failure though — swallowing it would let a stopped run report itself as
    /// finished and overwrite the state the user just asked for.
    private func repairedOverview(
        _ summary: MeetingSummary,
        context: SummaryContext
    ) async throws -> MeetingSummary {
        let content: String
        do {
            content = try await api.stream(
                systemPrompt: Self.overviewRepairSystemPrompt,
                userPrompt: Self.overviewRepairPrompt(overview: summary.overview),
                configuration: context.configuration,
                options: .meetingSummary,
                policy: policy,
                onEvent: { _ in }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return summary
        }
        guard let overview = Self.repairedOverviewText(from: content) else {
            return summary
        }
        var repaired = summary
        repaired.overview = overview
        return repaired
    }

    /// Only a JSON answer counts. An answer that ignored the schema is not an overview, and
    /// storing it verbatim would put the model's chatter in the meeting's minutes.
    static func repairedOverviewText(from raw: String) -> String? {
        let extracted = extractJSONObject(raw)
        guard let data = extracted.data(using: .utf8),
              let draft = try? JSONDecoder().decode(MeetingMinutesAlgorithm.DraftMinutes.self, from: data),
              let text = (draft.summary ?? draft.overview)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return nil
        }
        return text
    }

    /// One window, with the two retries that are worth paying for: a structurally unusable
    /// answer is asked for again, and a window the model cannot fit is split and merged.
    private func minutes(
        window: TranscriptWindow,
        windowLabel: String?,
        context: SummaryContext,
        onLiveUpdate: LiveHandler?
    ) async throws -> MeetingSummary {
        var correction: String?
        var lastResult: MeetingMinutesAlgorithm.ValidationResult?
        for attempt in 0 ..< 2 {
            do {
                let raw = try await streamed(
                    systemPrompt: Self.systemPrompt,
                    userPrompt: userPrompt(
                        context: context,
                        transcript: window.text,
                        windowLabel: windowLabel,
                        correction: correction
                    ),
                    context: context,
                    onLiveUpdate: onLiveUpdate
                )
                let result = try validate(raw, context: context)
                lastResult = result
                logDrops(result, meetingID: context.record.id)
                if attempt == 0, needsAnotherAnswer(result) {
                    correction = retryCorrection(for: result)
                    continue
                }
                return result.summary
            } catch is CancellationError {
                throw CancellationError()
            } catch is MeetingMinutesError {
                if attempt == 1 {
                    throw MeetingMinutesError.schemaRejected
                }
                correction = "输出不是规定的 JSON。"
            } catch let error as AIAPIError where error.isStreamInterruption {
                if attempt == 1 {
                    throw error
                }
                correction = "上一次请求没有返回完整结果，请重新输出完整的 JSON。"
            }
        }
        if let lastResult, lastResult.hasUsableMinutes {
            return lastResult.summary
        }
        throw MeetingMinutesError.schemaRejected
    }

    /// A window that does not fit the model is split and merged back together, and the
    /// lesson is remembered so the next meeting starts from a size the model accepts.
    private func summarizedWindow(
        window: TranscriptWindow,
        windowLabel: String?,
        context: SummaryContext,
        onLiveUpdate: LiveHandler? = nil
    ) async throws -> MeetingSummary {
        do {
            return try await minutes(
                window: window,
                windowLabel: windowLabel,
                context: context,
                onLiveUpdate: onLiveUpdate
            )
        } catch {
            let classified = MeetingMinutesError.classify(error)
            guard classified as? MeetingMinutesError == .tooLong else { throw error }
            let pieces = MeetingTranscriptFormat.split(window)
            guard pieces.count > 1 else { throw error }
            budgets.recordTooLong(estimatedTokens: window.estimatedTokens, for: context.configuration)
            JarvisLog.info(
                category: .meeting,
                event: "summary.window_split",
                fields: [
                    "meetingID": context.record.id.uuidString,
                    "estimatedTokens": String(window.estimatedTokens),
                    "pieces": String(pieces.count)
                ]
            )
            var summaries: [MeetingSummary] = []
            for (index, piece) in pieces.enumerated() {
                try await summaries.append(
                    minutes(
                        window: piece,
                        windowLabel: windowLabel.map { "\($0) 之 \(index + 1)/\(pieces.count)" }
                            ?? "第 \(index + 1)/\(pieces.count) 段",
                        context: context,
                        onLiveUpdate: nil
                    )
                )
            }
            let outcome = try await merged(
                pair: summaries.map { ReduceOutcome(summary: $0, isStitched: false) },
                context: context
            )
            return outcome.summary
        }
    }

    private func requestWindows(
        windows: [TranscriptWindow],
        completed: Int,
        summaries: [MeetingSummary],
        context: SummaryContext,
        onCheckpoint: CheckpointHandler?,
        onProgress: ProgressHandler?,
        onLiveUpdate: LiveHandler?
    ) async throws -> [MeetingSummary] {
        var summaries = summaries
        var completedPrefix = completed
        var nextIndex = completed
        var buffered: [Int: MeetingSummary] = [:]
        let total = windows.count
        try await withThrowingTaskGroup(of: (Int, MeetingSummary).self) { group in
            func enqueue() {
                guard nextIndex < total else { return }
                let index = nextIndex
                nextIndex += 1
                let window = windows[index]
                group.addTask { [self] in
                    let summary = try await summarizedWindow(
                        window: window,
                        windowLabel: "第 \(index + 1)/\(total) 段",
                        context: context
                    )
                    return (index, summary)
                }
            }

            let initialCount = min(Self.maxConcurrentSummaryRequests, total - completed)
            for _ in 0 ..< initialCount {
                enqueue()
            }

            for try await (index, summary) in group {
                buffered[index] = summary
                while let ready = buffered.removeValue(forKey: completedPrefix) {
                    summaries.append(ready)
                    completedPrefix += 1
                    var checkpoint = MeetingSummaryCheckpoint(
                        transcriptFingerprint: context.fingerprint,
                        stage: .extractingFacts,
                        completedChunkCount: completedPrefix,
                        totalChunkCount: total
                    )
                    checkpoint.windowSummaries = summaries
                    await publish(checkpoint, to: onCheckpoint)
                    // Show what is already extracted instead of an empty pane.
                    if let combined = MeetingMinutesAlgorithm.combiningWindows(summaries) {
                        await send(.draft(combined), to: onLiveUpdate)
                    }
                    await report(
                        Self.summaryProgress(
                            completedChunks: completedPrefix,
                            totalChunks: total,
                            completedSynthesisSteps: 0,
                            totalSynthesisSteps: 1
                        ),
                        to: onProgress
                    )
                }
                enqueue()
            }
        }
        return summaries
    }

    /// A tree of merges rather than one merge of everything: each level is a short request,
    /// and the levels can run at the same time.
    private struct ReduceOutcome {
        var summary: MeetingSummary
        /// True when a merge did not run and the windows were joined instead.
        var isStitched: Bool
    }

    private func reduce(
        summaries: [MeetingSummary],
        context: SummaryContext,
        onLiveUpdate: LiveHandler?
    ) async throws -> ReduceOutcome {
        guard summaries.count > 1 else {
            let only = summaries.first
                ?? MeetingSummary(overview: "", keyPoints: [], decisions: [], actionItems: [], openQuestions: [])
            return ReduceOutcome(summary: only, isStitched: false)
        }
        var level = summaries.map { ReduceOutcome(summary: $0, isStitched: false) }
        var isTopLevel = true
        while level.count > 1 {
            var next: [ReduceOutcome] = []
            var index = 0
            while index < level.count {
                if index + 1 == level.count {
                    next.append(level[index])
                    index += 1
                    continue
                }
                let pair = [level[index], level[index + 1]]
                try await next.append(
                    merged(
                        pair: pair,
                        context: context,
                        onLiveUpdate: isTopLevel ? onLiveUpdate : nil
                    )
                )
                index += 2
            }
            level = next
            isTopLevel = false
        }
        return level[0]
    }

    private func merged(
        pair: [ReduceOutcome],
        context: SummaryContext,
        onLiveUpdate: LiveHandler? = nil
    ) async throws -> ReduceOutcome {
        do {
            let summary = try await requestMergedMinutes(
                summaries: pair.map(\.summary),
                context: context,
                onLiveUpdate: onLiveUpdate
            )
            return ReduceOutcome(summary: summary, isStitched: false)
        } catch {
            // Windows already succeeded. Only an empty account keeps those windows,
            // without inventing text.
            let classified = MeetingMinutesError.classify(error)
            if classified as? MeetingMinutesError == .quota,
               let stitched = MeetingMinutesAlgorithm.combiningWindows(pair.map(\.summary))
            {
                JarvisLog.info(
                    category: .meeting,
                    event: "summary.merge_quota_stitched",
                    fields: [
                        "meetingID": context.record.id.uuidString,
                        "windows": String(pair.count)
                    ]
                )
                return ReduceOutcome(summary: stitched, isStitched: true)
            }
            throw error
        }
    }

    private func requestMergedMinutes(
        summaries: [MeetingSummary],
        context: SummaryContext,
        onLiveUpdate: LiveHandler?
    ) async throws -> MeetingSummary {
        let payload = try summaries.enumerated().map { index, summary -> String in
            let data = try JSONEncoder().encode(MergePayload(summary, shortIDs: context.index.shortIDs))
            return "第 \(index + 1) 段纪要：\n\(String(decoding: data, as: UTF8.self))"
        }.joined(separator: "\n\n")

        var correction: String?
        var lastResult: MeetingMinutesAlgorithm.ValidationResult?
        for attempt in 0 ..< 2 {
            do {
                let raw = try await streamed(
                    systemPrompt: Self.systemPrompt,
                    userPrompt: """
                    下面是同一场会议按时间顺序切分后的纪要。请合并成一份。
                    不要丢掉中间段。同一事项只保留一次。evidence 里的 segment_id 和 keyword 必须原样保留。

                    \(payload)
                    \(correction.map { "\n上一次输出不合格：\($0)" } ?? "")
                    """,
                    context: context,
                    onLiveUpdate: onLiveUpdate
                )
                let result = try validate(raw, context: context)
                lastResult = result
                logDrops(result, meetingID: context.record.id)
                if attempt == 0, needsAnotherAnswer(result) {
                    correction = retryCorrection(for: result)
                    continue
                }
                return result.summary
            } catch is CancellationError {
                throw CancellationError()
            } catch is MeetingMinutesError {
                if attempt == 1 {
                    throw MeetingMinutesError.schemaRejected
                }
                correction = "输出不是规定的 JSON。"
            } catch let error as AIAPIError where error.isStreamInterruption {
                if attempt == 1 {
                    throw error
                }
                correction = "上一次请求没有返回完整结果，请重新输出完整的 JSON。"
            }
        }
        if let lastResult, lastResult.hasUsableMinutes {
            return lastResult.summary
        }
        throw MeetingMinutesError.schemaRejected
    }

    /// Every model call goes through here: streamed, with events handed to the live view.
    private func streamed(
        systemPrompt: String,
        userPrompt: String,
        context: SummaryContext,
        onLiveUpdate: LiveHandler?
    ) async throws -> String {
        // Everything the assembler shows is a preview. What comes back here is parsed in
        // full and validated again, and that is what ends up stored.
        let assembler = MinutesStreamAssembler(
            context: context,
            onUpdate: onLiveUpdate
        )
        return try await api.stream(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            configuration: context.configuration,
            options: .meetingSummary,
            policy: policy,
            onEvent: { assembler.handle($0) }
        )
    }

    // MARK: - Validation

    private func validate(
        _ raw: String,
        context: SummaryContext
    ) throws -> MeetingMinutesAlgorithm.ValidationResult {
        let extracted = Self.extractJSONObject(raw)
        guard let data = extracted.data(using: .utf8) else {
            throw MeetingMinutesError.schemaRejected
        }
        let draft: MeetingMinutesAlgorithm.DraftMinutes
        do {
            draft = try JSONDecoder().decode(MeetingMinutesAlgorithm.DraftMinutes.self, from: data)
        } catch {
            throw MeetingMinutesError.schemaRejected
        }
        return MeetingMinutesAlgorithm.validate(
            draft,
            transcript: context.record.transcript,
            speakers: context.record.speakers,
            meetingDate: context.record.createdAt,
            generation: context.generation
        )
    }

    /// Only a materially unusable answer is worth another full request. A length complaint
    /// is not: it is cheaper to rewrite the overview alone than to re-read the transcript.
    private func needsAnotherAnswer(_ result: MeetingMinutesAlgorithm.ValidationResult) -> Bool {
        result.summary.overview.isEmpty || result.droppedAllCitedItems
    }

    private func retryCorrection(for result: MeetingMinutesAlgorithm.ValidationResult) -> String {
        if result.summary.overview.isEmpty {
            return "缺少 summary。"
        }
        if result.droppedAllCitedItems {
            return "evidence 的 segment_id 必须是逐字稿行首的编号，keyword 必须是该片段里连续出现的原文。"
        }
        return "输出必须是规定的 JSON。"
    }

    private func logDrops(_ result: MeetingMinutesAlgorithm.ValidationResult, meetingID: UUID) {
        guard !result.log.droppedPointIDs.isEmpty || !result.log.droppedTodoIDs.isEmpty else { return }
        JarvisLog.info(
            category: .meeting,
            event: "summary.dropped_items",
            fields: [
                "meetingID": meetingID.uuidString,
                "points": result.log.droppedPointIDs.joined(separator: ","),
                "todos": result.log.droppedTodoIDs.joined(separator: ",")
            ]
        )
    }

    // MARK: - Prompts

    private struct MergePayload: Encodable {
        struct Point: Encodable {
            var id: String
            var title: String
            var detail: String
            var evidence: [Evidence]
        }

        struct Todo: Encodable {
            var id: String
            var task: String
            var owner: String?
            var due: String?
            var evidence: [Evidence]
        }

        struct Evidence: Encodable {
            var segment_id: String
            var keyword: String
        }

        var summary: String
        var points: [Point]
        var todos: [Todo]

        init(_ summary: MeetingSummary, shortIDs: [UUID: String]) {
            self.summary = summary.overview
            func evidence(_ items: [MeetingEvidence]) -> [Evidence] {
                items.map { item in
                    Evidence(
                        segment_id: shortIDs[item.segmentID] ?? item.segmentID.uuidString,
                        keyword: item.quote
                    )
                }
            }
            points = summary.points.map { point in
                Point(
                    id: point.id,
                    title: point.title,
                    detail: point.detail,
                    evidence: evidence(point.evidence)
                )
            }
            todos = summary.actionItems.map { item in
                Todo(
                    id: item.id.uuidString,
                    task: item.task,
                    owner: item.owner.isEmpty ? nil : item.owner,
                    due: item.dueDate.isEmpty ? nil : item.dueDate,
                    evidence: evidence(item.evidence)
                )
            }
        }
    }

    private static let systemPrompt = """
    你是会议纪要编辑。只根据给出的逐字稿写中文纪要。禁止补充逐字稿里没有的事实、人名、数字、日期或结论。
    只输出一个 JSON 对象，不要 Markdown，不要解释。

    {
      "summary": "200到400字的概要",
      "points": [
        {
          "id": "P1",
          "title": "这个议题的结论或分歧",
          "detail": "展开说明，不能加入逐字稿没有的事实",
          "evidence": [
            {"segment_id": "S12", "keyword": "该片段里的一个关键词"}
          ]
        }
      ],
      "todos": [
        {
          "id": "T1",
          "task": "一句完整、可执行的待办",
          "owner": null,
          "due": null,
          "owner_missing": "未指定",
          "due_missing": "未提及",
          "evidence": [
            {"segment_id": "S12", "keyword": "该片段里的一个关键词"}
          ]
        }
      ]
    }

    规则：
    - 逐字稿每一行的开头是片段编号，形如 [S12]。segment_id 必须是行首那个编号，不要自己编号。
    - evidence 只写 segment_id 和 keyword。keyword 是这一段里连续出现的两到八个字，用来定位原话，不要抄整句，也不要改写。
    - 每个 point 和每个 todo 至少一条 evidence，而且 keyword 必须真的出现在该片段里。
    - title 和 detail 可以归纳，但不能加入输入里没有的事实。
    - 待办写成完整任务，不要照抄半句口头语，也不要把没有答应要做的话写成待办。
    - owner 只能使用逐字稿、keyword 或说话人显示名里出现过的名字。没有明确负责人时 owner 为 null，owner_missing 为「未指定」。不要猜测或编造人名。
    - 没有明确期限时 due 为 null，due_missing 为「未提及」。「待会」「回头」「尽快」不是期限。
    - 相对时间保留原话，例如「下周三」，不要改成你自己推算的日期。
    - 讨论要点写结论和分歧。不要把寒暄、确认能否听到、卡顿、散会写成要点。
    - 没有依据的 point 或 todo 不要输出。
    """

    private static let overviewRepairSystemPrompt = """
    你负责把一段会议概要改写到规定长度。只改写给出的概要，不要新增原文没有的事实、人名、数字或日期。
    只输出一个 JSON 对象，不要 Markdown，不要解释：{"summary": "改写后的概要"}
    """

    private static func overviewRepairPrompt(overview: String) -> String {
        let range = MeetingMinutesAlgorithm.summaryCharacterRange
        let payload = (try? JSONSerialization.data(
            withJSONObject: ["summary": overview],
            options: [.withoutEscapingSlashes]
        )).map { String(decoding: $0, as: UTF8.self) } ?? overview
        return """
        下面这段会议概要不符合长度要求，请改写。
        要求：\(range.lowerBound) 到 \(range.upperBound) 字，保留原意，不要新增事实。

        \(payload)
        """
    }

    private func userPrompt(
        context: SummaryContext,
        transcript: String,
        windowLabel: String?,
        correction: String?
    ) -> String {
        let scope = windowLabel.map { "这是会议的\($0)，只根据这一段写。" } ?? "这是完整逐字稿。"
        // The correction goes last: anything before it stays a stable prefix, which is what
        // providers with prompt caching charge the least for.
        return """
        会议：\(context.record.title)
        会议日期：\(context.record.createdAt.formatted(date: .numeric, time: .omitted))
        说话人：\(context.speakerNames.joined(separator: "、"))
        \(scope)

        逐字稿每一行的格式是 [片段编号] 说话人：原文
        \(transcript)
        \(correction.map { "\n上一次输出不合格：\($0) 请按 schema 重写。" } ?? "")
        """
    }

    // MARK: - Checkpoints

    private func finishedCheckpoint(
        fingerprint: String,
        chunkCount: Int,
        windows: [MeetingSummary],
        finished: MeetingSummary
    ) -> MeetingSummaryCheckpoint {
        var checkpoint = MeetingSummaryCheckpoint(
            transcriptFingerprint: fingerprint,
            stage: .completed,
            completedChunkCount: chunkCount,
            totalChunkCount: chunkCount,
            directSummary: chunkCount == 1
        )
        checkpoint.windowSummaries = windows
        checkpoint.finishedSummary = finished
        return checkpoint
    }

    private func resumableFinishedSummary(
        _ checkpoint: MeetingSummaryCheckpoint?,
        fingerprint: String
    ) -> MeetingSummary? {
        guard let checkpoint,
              checkpoint.pipelineVersion == MeetingSummaryCheckpoint.currentPipelineVersion,
              checkpoint.transcriptFingerprint == fingerprint,
              checkpoint.stage == .completed,
              let finished = checkpoint.finishedSummary
        else { return nil }
        return finished
    }

    private func resumableCheckpoint(
        _ checkpoint: MeetingSummaryCheckpoint?,
        fingerprint: String,
        chunkCount: Int
    ) -> MeetingSummaryCheckpoint? {
        guard let checkpoint,
              checkpoint.pipelineVersion == MeetingSummaryCheckpoint.currentPipelineVersion,
              checkpoint.transcriptFingerprint == fingerprint,
              checkpoint.totalChunkCount == chunkCount,
              let windows = checkpoint.windowSummaries,
              windows.count <= chunkCount
        else { return nil }
        return checkpoint
    }

    private func transcriptFingerprint(_ segments: [MeetingTranscriptSegment]) -> String {
        let canonical = segments.map {
            "\($0.id.uuidString)|\($0.startTime)|\($0.endTime)|\($0.speakerID)|\($0.text)"
        }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func publish(_ checkpoint: MeetingSummaryCheckpoint, to handler: CheckpointHandler?) async {
        guard let handler else { return }
        await handler(checkpoint)
    }

    private func report(_ progress: Double?, to handler: ProgressHandler?) async {
        guard let handler else { return }
        await handler(progress)
    }

    private func send(_ update: MeetingSummaryLiveUpdate, to handler: LiveHandler?) async {
        guard let handler else { return }
        await handler(update)
    }
}

/// What every request in one summarization run shares.
struct SummaryContext: Sendable {
    var record: MeetingRecord
    var configuration: AIAPIConfiguration
    var index: TranscriptIndex
    var generation: MeetingMinutesGeneration
    var fingerprint: String
    var speakerNames: [String]
}

/// Turns the streamed answer into a summary the view can show while it is still arriving.
///
/// Items are validated as they complete, using the same rules the final parse uses, so what
/// the user reads mid-stream is what they keep unless the finished document disagrees.
private final class MinutesStreamAssembler: @unchecked Sendable {
    private static let emitInterval: TimeInterval = 0.12

    private let context: SummaryContext
    private let onUpdate: MeetingSummaryService.LiveHandler?
    private let allowedOwnerText: String
    private let lock = NSLock()

    private var decoder = MeetingMinutesStreamDecoder()
    private var overview = ""
    private var points: [MeetingDiscussionPoint] = []
    private var actionItems: [MeetingActionItem] = []
    private var reportedThinking = false
    private var lastEmit: TimeInterval = 0

    init(context: SummaryContext, onUpdate: MeetingSummaryService.LiveHandler?) {
        self.context = context
        self.onUpdate = onUpdate
        allowedOwnerText = (context.record.transcript.map(\.text) + context.speakerNames)
            .joined(separator: "\n")
    }

    func handle(_ event: AIStreamEvent) {
        var update: MeetingSummaryLiveUpdate?
        lock.lock()
        switch event {
        case .reasoning:
            if !reportedThinking {
                reportedThinking = true
                update = .thinking
            }
        case let .content(text):
            var sawItem = false
            for decoded in decoder.feed(text) {
                switch decoded {
                case let .overviewDelta(chunk):
                    overview += chunk
                case .overviewRestarted:
                    overview = ""
                case let .pointCompleted(json):
                    sawItem = appendPoint(json) || sawItem
                case let .todoCompleted(json):
                    sawItem = appendActionItem(json) || sawItem
                }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if sawItem || now - lastEmit >= Self.emitInterval {
                lastEmit = now
                update = .draft(snapshot())
            }
        }
        lock.unlock()
        guard let update else { return }
        deliver(update)
    }

    private func appendPoint(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let draft = try? JSONDecoder().decode(MeetingMinutesAlgorithm.DraftPoint.self, from: data)
        else { return false }
        let identifier = draft.id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "P\(points.count + 1)"
        guard let point = MeetingMinutesAlgorithm.makePoint(
            draft,
            identifier: (identifier?.isEmpty == false ? identifier : nil) ?? fallback,
            index: context.index
        ) else { return false }
        points.append(point)
        return true
    }

    private func appendActionItem(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let draft = try? JSONDecoder().decode(MeetingMinutesAlgorithm.DraftTodo.self, from: data)
        else { return false }
        let identifier = draft.id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "T\(actionItems.count + 1)"
        guard let item = MeetingMinutesAlgorithm.makeActionItem(
            draft,
            identifier: (identifier?.isEmpty == false ? identifier : nil) ?? fallback,
            index: context.index,
            allowedOwnerText: allowedOwnerText,
            speakerNames: context.speakerNames,
            meetingDate: context.record.createdAt,
            calendar: .current
        ) else { return false }
        actionItems.append(item)
        return true
    }

    private func snapshot() -> MeetingSummary {
        MeetingSummary(
            overview: overview,
            keyPoints: [],
            decisions: [],
            actionItems: actionItems,
            openQuestions: [],
            points: points,
            generation: context.generation
        )
    }

    private func deliver(_ update: MeetingSummaryLiveUpdate) {
        guard let onUpdate else { return }
        Task { @MainActor in
            onUpdate(update)
        }
    }
}
