import Foundation
import Observation

/// The live interview screen's view model. It stands in for the future
/// interviewer: it picks predefined questions for the interview context,
/// captures an answer through `AnswerRecorder`, and decides whether to follow
/// up or move on. No audio is recorded.
@Observable
final class LiveInterviewViewModel {
    enum Phase: Equatable {
        /// The question is on screen; the candidate can start answering.
        case ready
        case recording(startedAt: Date)
        /// The answer was submitted and is being "analyzed".
        case processing
        /// The answer was captured; the interviewer is about to respond.
        case captured
        /// Every topic has been covered.
        case finished
    }

    let interview: Interview
    let resume: ResumeContext?
    let evaluationMode: AIEvaluationMode
    private(set) var turns: [InterviewTurn]
    let startedAt = Date.now

    private(set) var latestEvaluation: UnifiedAIEvaluation?
    private(set) var latestDualEvaluation: DualAIEvaluation?
    private(set) var phase: Phase = .ready
    private(set) var turnIndex = 0
    private(set) var isFollowUp = false
    private var dynamicFollowUpQuestion: String? = nil
    private(set) var transcript: [TranscriptEntry] = []
    /// Shown when an answer couldn't be captured, e.g. it was too short.
    private(set) var notice: String?
    /// Main questions answered, and ones skipped, by turn.
    private(set) var answeredTurnIDs: [String] = []
    private(set) var skippedTurnIDs: [String] = []

    /// Hears each answer and measures how it was said.
    private let recorder = AnswerRecorder()
    private var isStartingRecording = false
    /// False when speech recognition couldn't start: the answer is still
    /// timed and the interview goes on, it just isn't transcribed.
    private var isTranscribing = true

    /// Answers shorter than this are treated as a failed recording.
    private let minimumAnswerSeconds: TimeInterval = 2

    init(interview: Interview, resume: ResumeContext?, evaluationMode: AIEvaluationMode = .online) {
        self.interview = interview
        self.resume = resume
        self.evaluationMode = evaluationMode
        self.turns = Self.initialTailoredPlan(for: interview, resume: resume)
        self.requestAIQuestions()
    }

    private func requestAIQuestions() {
        Task { [weak self] in
            guard let self else { return }
            let aiTurns = await AIEvaluationCoordinator.shared.generateQuestions(for: self.interview, resume: self.resume)
            if !aiTurns.isEmpty {
                await MainActor.run {
                    if self.turnIndex == 0 && self.phase == .ready && self.answeredTurnIDs.isEmpty {
                        self.turns = aiTurns
                    } else if self.turnIndex < aiTurns.count {
                        let remaining = Array(aiTurns.dropFirst(self.turnIndex))
                        self.turns = Array(self.turns.prefix(self.turnIndex)) + remaining
                    }
                }
            }
        }
    }

    var currentTurn: InterviewTurn? {
        turns.indices.contains(turnIndex) ? turns[turnIndex] : nil
    }

    var currentQuestion: String? {
        guard let turn = currentTurn else { return nil }
        return isFollowUp ? (dynamicFollowUpQuestion ?? turn.followUp?.question) : turn.question
    }

    /// The candidate's previous answer, kept on screen so a follow-up reads as a
    /// response to it rather than a new, unrelated question.
    var previousAnswer: String? {
        guard isFollowUp else { return nil }
        return transcript.last?.answer
    }

    /// Main topics the candidate has answered (follow-ups don't count);
    /// skipped ones aren't among them, so they aren't scored.
    var answeredTurns: [InterviewTurn] {
        turns.filter { answeredTurnIDs.contains($0.id) }
    }

    /// Where a question stands, for the list of questions.
    enum TurnStatus { case answered, skipped, current, upcoming }

    func status(ofTurn index: Int) -> TurnStatus {
        let id = turns[index].id
        if answeredTurnIDs.contains(id) && index != turnIndex { return .answered }
        if skippedTurnIDs.contains(id) { return .skipped }
        if index == turnIndex && phase != .finished { return .current }
        return index < turnIndex ? .answered : .upcoming
    }


    var progress: Double {
        guard !turns.isEmpty else { return 0 }
        return Double(min(turnIndex, turns.count)) / Double(turns.count)
    }

    /// Approximate position, deliberately not a question count.
    var progressDescription: String {
        switch progress {
        case 1...: "Interview complete"
        case 0.75...: "Last topic"
        case 0.4...: "About halfway"
        case 0.01...: "Getting going"
        default: "Just started"
        }
    }

    // MARK: - The screen's stages

    enum Stage: Equatable {
        case interviewing
        /// Stands in for evaluation latency, so the wait is designed for.
        case preparingFeedback
        case feedback(Rehearsal.ID)
    }

    private(set) var stage: Stage = .interviewing

    /// Saves the finished interview, waits as an evaluation would, then
    /// shows its feedback.
    func finish(savingTo appState: AppState, usedResume: Bool) {
        guard stage == .interviewing else { return }
        stage = .preparingFeedback
        let rehearsal = appState.saveInterview(self, usedResume: usedResume)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            stage = .feedback(rehearsal.id)
        }
    }

    // MARK: - Answering

    /// The answer button: starts an answer, or stops and keeps it.
    func toggleRecording() {
        switch phase {
        case .ready: startRecording()
        case .recording: Task { await stopRecording() }
        default: break
        }
    }

    func startRecording() {
        guard phase == .ready, !isStartingRecording else { return }
        notice = nil
        isStartingRecording = true
        // The clock starts once the microphone is listening, not while a
        // permission prompt is up.
        Task {
            defer { isStartingRecording = false }
            do {
                try await recorder.start()
                guard phase == .ready else { recorder.cancel(); return }
                isTranscribing = true
                phase = .recording(startedAt: .now)
            } catch AnswerRecorder.Failure.unavailable {
                // Without speech recognition (as in the simulator) the
                // interview still goes on; the answer just isn't written down.
                guard phase == .ready else { return }
                isTranscribing = false
                notice = "Speech recognition isn’t available, so this answer won’t be transcribed."
                phase = .recording(startedAt: .now)
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    /// Stops listening without keeping anything, as when the interview closes.
    func cancelRecording() {
        recorder.cancel()
    }

    func stopRecording() async {
        guard case .recording(let startedAt) = phase, let turn = currentTurn else { return }

        guard Date.now.timeIntervalSince(startedAt) >= minimumAnswerSeconds else {
            recorder.cancel()
            notice = "That was too short to catch. Tap when you’re ready and answer out loud."
            phase = .ready
            return
        }

        phase = .processing
        // A failed or empty transcription never holds the interview up: the
        // answer counts, it's just left out of the transcript.
        let spoken = isTranscribing ? try? await recorder.stop() : nil
        guard phase == .processing else { return }

        #if targetEnvironment(simulator)
        // SFSpeechRecognizer is often unavailable or silent on iOS Simulator.
        // Fall back to turn's mock answer text so the user's audio test triggers real AI evaluation.
        let resolvedAnswerText: String? = (spoken?.text.isEmpty == false) ? spoken!.text : turn.mockAnswer
        let isSimulatedAudio = (spoken?.text.isEmpty != false)
        notice = isSimulatedAudio ? "Mic transcription unavailable in Simulator. Evaluated reference answer with real AI." : nil
        #else
        let resolvedAnswerText: String? = spoken?.text
        notice = spoken == nil ? "We couldn’t transcribe that answer, so it’s left out of your transcript." : nil
        #endif

        var aiEval: UnifiedAIEvaluation?
        if let answerText = resolvedAnswerText, !answerText.isEmpty {
            let input = AIEvaluationInput(
                interview_id: interview.id.uuidString,
                question_id: turn.id,
                question: currentQuestion ?? "",
                candidate_answer: answerText,
                domain: interview.type == .technical ? "Computer Science Fundamentals" : "Behavioral Interviews",
                subdomain: interview.role,
                question_type: interview.type == .technical ? "technical" : "behavioral",
                difficulty: "intermediate",
                candidate_level: interview.experienceLevel.lowercased(),
                previous_questions: transcript.map(\.question),
                previous_answers: transcript.map(\.answer),
                interview_context: "\(interview.role) at \(interview.company ?? "Tech Company")",
                duration_seconds: Date.now.timeIntervalSince(startedAt),
                transcript_analytics: TranscriptAnalyticsPayload(
                    words_per_minute: spoken?.measurements.wordsPerMinute ?? 135,
                    filler_word_count: spoken?.measurements.fillerWords ?? 1,
                    repeated_word_count: spoken?.measurements.longPauses ?? 0
                )
            )

            do {
                let eval = try await AIEvaluationCoordinator.shared.evaluate(input: input, mode: evaluationMode)
                aiEval = eval
                self.latestEvaluation = eval
                if eval.evaluation_result.follow_up.needed, let fq = eval.evaluation_result.follow_up.question, !fq.isEmpty {
                    self.dynamicFollowUpQuestion = fq
                }
                if let nq = eval.evaluation_result.next_question?.question, !nq.isEmpty {
                    let nextIdx = turnIndex + 1
                    if nextIdx < self.turns.count {
                        self.turns[nextIdx] = InterviewTurn(
                            id: "ai-adaptive-\(nextIdx)",
                            question: nq,
                            origin: "AI Adaptive Progression",
                            mockAnswer: "",
                            followUp: nil,
                            moment: InterviewTurn.Moment(kind: .strength, note: "Adaptive Question")
                        )
                    }
                }
            } catch {
                print("[AIEvaluation] \(evaluationMode.rawValue) evaluation error: \(error)")
                notice = "AI evaluation notice: \(error.localizedDescription)"
            }
        }

        if !isFollowUp { answeredTurnIDs.append(turn.id) }
        var turnMeasurements = spoken?.measurements ?? Measurements(wordsPerMinute: 135, fillerWords: 1)
        let eyePercent = CameraManager.shared.currentEyeContactPercent
        if eyePercent > 0 {
            turnMeasurements.eyeContactPercent = eyePercent
        }
        CameraManager.shared.resetEyeContactTracking()

        transcript.append(TranscriptEntry(
            question: currentQuestion ?? "",
            answer: resolvedAnswerText ?? TranscriptEntry.notTranscribed,
            isFollowUp: isFollowUp,
            // Still the prepared evaluation until answers are judged.
            moment: isFollowUp ? nil : turn.moment,
            measurements: turnMeasurements,
            evaluation: aiEval
        ))
        phase = .captured

        try? await Task.sleep(for: .seconds(1.8))
        guard phase == .captured else { return }
        advance()
    }

    /// Submits a typed answer for real AI evaluation (online Gemini or offline Apple Foundation Models).
    func submitTypedAnswer(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let turn = currentTurn else { return }

        phase = .processing
        notice = nil

        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        let estimatedWpm = min(160, max(110, wordCount * 2))
        var measurements = Measurements(
            wordsPerMinute: estimatedWpm,
            fillerWords: 0,
            longPauses: 0
        )
        if CameraManager.shared.currentEyeContactPercent > 0 {
            measurements.eyeContactPercent = CameraManager.shared.currentEyeContactPercent
        }

        let input = AIEvaluationInput(
            interview_id: interview.id.uuidString,
            question_id: turn.id,
            question: currentQuestion ?? "",
            candidate_answer: trimmed,
            domain: interview.type == .technical ? "Computer Science Fundamentals" : "Behavioral Interviews",
            subdomain: interview.role,
            question_type: interview.type == .technical ? "technical" : "behavioral",
            difficulty: "intermediate",
            candidate_level: interview.experienceLevel.lowercased(),
            previous_questions: transcript.map(\.question),
            previous_answers: transcript.map(\.answer),
            interview_context: "\(interview.role) at \(interview.company ?? "Tech Company")",
            duration_seconds: max(15.0, Double(wordCount) / 2.0),
            transcript_analytics: TranscriptAnalyticsPayload(
                words_per_minute: estimatedWpm,
                filler_word_count: 0,
                repeated_word_count: 0
            )
        )

        var aiEval: UnifiedAIEvaluation?
        do {
            let eval = try await AIEvaluationCoordinator.shared.evaluate(input: input, mode: evaluationMode)
            aiEval = eval
            self.latestEvaluation = eval
            if eval.evaluation_result.follow_up.needed, let fq = eval.evaluation_result.follow_up.question, !fq.isEmpty {
                self.dynamicFollowUpQuestion = fq
            }
            if let nq = eval.evaluation_result.next_question?.question, !nq.isEmpty {
                let nextIdx = turnIndex + 1
                if nextIdx < self.turns.count {
                    self.turns[nextIdx] = InterviewTurn(
                        id: "ai-adaptive-\(nextIdx)",
                        question: nq,
                        origin: "AI Adaptive Progression",
                        mockAnswer: "",
                        followUp: nil,
                        moment: InterviewTurn.Moment(kind: .strength, note: "Adaptive Question")
                    )
                }
            }
        } catch {
            print("[AIEvaluation] \(evaluationMode.rawValue) typed answer evaluation error: \(error)")
            notice = "AI evaluation error: \(error.localizedDescription)"
        }

        if !isFollowUp { answeredTurnIDs.append(turn.id) }
        transcript.append(TranscriptEntry(
            question: currentQuestion ?? "",
            answer: trimmed,
            isFollowUp: isFollowUp,
            moment: isFollowUp ? nil : turn.moment,
            measurements: measurements,
            evaluation: aiEval
        ))
        phase = .captured

        try? await Task.sleep(for: .seconds(1.8))
        guard phase == .captured else { return }
        advance()
    }

    private func advance() {
        if !isFollowUp, (dynamicFollowUpQuestion != nil || currentTurn?.followUp != nil) {
            isFollowUp = true
        } else {
            isFollowUp = false
            dynamicFollowUpQuestion = nil
            turnIndex += 1
        }
        phase = turnIndex < turns.count ? .ready : .finished
    }

    // MARK: - Dynamic Role-Tailored Question Planning

    /// Dynamically constructs an opening set of questions deeply calibrated to the
    /// candidate's target company, role, experience level, and interview type.
    /// Completely removes generic static questions (e.g. distributed caching for all roles).
    static func initialTailoredPlan(for interview: Interview, resume: ResumeContext?) -> [InterviewTurn] {
        let comp = interview.company ?? "leading technology company"
        let role = interview.role
        let level = interview.experienceLevel
        let capacity = Interview.topicCapacity(forMinutes: interview.durationMinutes)
        let isTech = interview.type == .technical
        let roleLow = role.lowercased()

        var questions: [String] = []

        if isTech {
            if roleLow.contains("ios") || roleLow.contains("apple") || roleLow.contains("swift") || roleLow.contains("mobile") {
                questions.append("When developing software for \(comp), maintaining 60/120fps UI fluidity and zero main-thread hitches is critical. How do you architect view state, background synchronization, and task isolation in \(role)?")
                questions.append("Describe your approach to managing structured Swift Concurrency, data-race safety, and actor isolation when handling asynchronous network updates or persistent storage.")
                questions.append("Walk me through how you architect an offline-first caching and conflict resolution engine for a mobile app at \(comp) under degraded connectivity.")
                questions.append("How do you diagnose and eliminate persistent memory leaks, retain cycles, and layout thrashing using platform Instruments?")
            } else if roleLow.contains("ml") || roleLow.contains("ai") || roleLow.contains("data") {
                questions.append("At \(comp), low-latency inference and real-time model serving are essential for \(role). How do you design an inference pipeline to meet sub-50ms p99 latency under heavy query spikes?")
                questions.append("How do you detect and mitigate feature distribution drift, covariate shift, and label degradation in continuous production pipelines?")
                questions.append("Explain how you design an evaluation harness and guardrails to benchmark model performance and structured schema adherence.")
                questions.append("Walk me through how you approach feature engineering and storage tradeoffs between a real-time feature store and offline batch data lakes.")
            } else if roleLow.contains("backend") || roleLow.contains("distributed") || roleLow.contains("cloud") || roleLow.contains("systems") || roleLow.contains("sre") {
                questions.append("For a mission-critical backend service at \(comp), how do you ensure high availability and partition tolerance while preventing cascading retry storms and data loss in \(role)?")
                questions.append("Walk me through how you implement distributed idempotency and distributed rate limiting across multi-region server clusters.")
                questions.append("How do you design a database sharding and index strategy when a high-throughput relational database exceeds write capacity?")
                questions.append("Explain how you handle cascading service failures, thundering herds, and circuit breaking when third-party upstream dependencies fail.")
            } else {
                questions.append("As a \(level) \(role) at \(comp), how do you structure an end-to-end architecture to balance rapid feature iteration with long-term maintainability and system resilience?")
                questions.append("Describe how you design APIs and contracts between client applications and backend microservices to ensure graceful error handling and forward compatibility.")
                questions.append("Walk me through a complex architectural tradeoff you made where you had to sacrifice one system property for another.")
                questions.append("How do you approach automated testing, end-to-end integration verification, and deployment safety in a continuous delivery pipeline?")
            }
        } else {
            questions.append("Tell me about a high-stakes technical initiative you drove as a \(level) \(role) at \(comp) where you encountered conflicting cross-functional priorities. How did you achieve consensus?")
            questions.append("Describe an instance where you pushed back against an unrealistic project deadline or scope requirement. What empirical data and architectural alternatives did you present to leadership?")
            questions.append("Can you share an experience where a production incident occurred due to an unforeseen edge case under your watch? How did you manage the immediate remediation and post-mortem?")
            questions.append("How do you handle a situation where two senior engineers on your team strongly disagree on an architectural decision or technology choice?")
        }

        let selected = Array(questions.prefix(capacity))
        return selected.enumerated().map { index, q in
            InterviewTurn(
                id: "initial-q-\(index + 1)",
                question: q,
                origin: "Tailored for \(level) \(role) at \(comp)",
                mockAnswer: "",
                followUp: nil,
                moment: InterviewTurn.Moment(kind: .strength, note: "\(role) Assessment")
            )
        }
    }
}
