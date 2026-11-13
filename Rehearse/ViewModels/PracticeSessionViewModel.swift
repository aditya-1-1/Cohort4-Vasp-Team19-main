import Foundation
import Observation

/// The practice screen's view model: answering one question out loud. It
/// mirrors the interview: too-short answers aren't captured, and a short
/// wait stands in for evaluation.
@Observable
final class PracticeSessionViewModel {
    let question: Question
    let focus: Skill?

    private(set) var answerState: AnswerState = .ready
    private(set) var notice: String?
    private(set) var result: String?
    /// What was heard, shown back so the candidate can check it.
    private(set) var heard: SpokenAnswer?
    /// One practice session counts once, however many attempts.
    private var isSaved = false
    /// False when speech recognition couldn't start: the answer still
    /// counts, it just isn't written down.
    private var isTranscribing = true
    private let recorder = AnswerRecorder()

    init(question: Question, focus: Skill?) {
        self.question = question
        self.focus = focus
    }

    /// "142 words a minute, 2 filler words, 1 long pause", from what was measured.
    var heardSummary: String? {
        guard let measured = heard?.measurements else { return nil }
        var parts: [String] = []
        if let pace = measured.wordsPerMinute { parts.append("\(pace) words a minute") }
        if Scoring.flagsFillerWords, let fillers = measured.fillerWords { parts.append(fillers == 1 ? "1 filler word" : "\(fillers) filler words") }
        if let pauses = measured.longPauses, pauses > 0 { parts.append(pauses == 1 ? "1 long pause" : "\(pauses) long pauses") }
        return parts.isEmpty ? "Answer heard" : parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst()
    }

    // MARK: - Actions

    /// The answer button: starts an answer, or stops and checks it.
    func toggleRecording(in appState: AppState) {
        switch answerState {
        case .ready:
            notice = nil
            // The clock starts once the microphone is listening.
            answerState = .processing
            Task {
                do {
                    try await recorder.start()
                    isTranscribing = true
                    answerState = .recording(startedAt: .now)
                } catch AnswerRecorder.Failure.unavailable {
                    // Practice still works without speech recognition; the
                    // answer just isn't written down.
                    isTranscribing = false
                    notice = "Speech recognition isn’t available, so this answer won’t be transcribed."
                    answerState = .recording(startedAt: .now)
                } catch {
                    notice = error.localizedDescription
                    answerState = .ready
                }
            }
        case .recording(let startedAt):
            guard Date.now.timeIntervalSince(startedAt) >= 2 else {
                recorder.cancel()
                notice = "That was too short to catch. Tap when you’re ready and answer out loud."
                answerState = .ready
                return
            }
            answerState = .processing
            Task {
                // A failed or empty transcription still finishes the attempt.
                let spoken = isTranscribing ? try? await recorder.stop() : nil
                guard answerState == .processing else { return }
                notice = spoken == nil ? "We couldn’t transcribe that answer, so there’s no transcript this time." : nil
                heard = spoken
                answerState = .captured

                if let spoken, !spoken.text.isEmpty {
                    let input = AIEvaluationInput(
                        interview_id: "practice-\(question.id)",
                        question_id: question.id,
                        question: question.text,
                        candidate_answer: spoken.text,
                        domain: question.category == .behavioral ? "Behavioral Interviews" : "Computer Science Fundamentals",
                        subdomain: question.role ?? "Software Engineer",
                        question_type: question.category == .behavioral ? "behavioral" : "technical",
                        difficulty: question.difficulty.rawValue.lowercased(),
                        candidate_level: "intermediate",
                        interview_context: "Practice Question",
                        transcript_analytics: TranscriptAnalyticsPayload(
                            words_per_minute: spoken.measurements.wordsPerMinute,
                            filler_word_count: spoken.measurements.fillerWords,
                            repeated_word_count: spoken.measurements.longPauses
                        )
                    )
                    if let eval = try? await AIEvaluationCoordinator.shared.evaluate(input: input, mode: .online) {
                        result = eval.evaluation_result.feedback.summary + "\n\n" + eval.evaluation_result.feedback.ideal_answer_guidance
                    } else {
                        result = MockFeedbackService.practiceNote(for: focus)
                    }
                } else {
                    result = MockFeedbackService.practiceNote(for: focus)
                }

                if !isSaved {
                    appState.savePractice(question, focus: focus, answer: spoken)
                    isSaved = true
                }
            }
        default:
            break
        }
    }

    func tryAgain() {
        result = nil
        heard = nil
        answerState = .ready
    }

    /// Stops listening without keeping anything, as when the screen closes.
    func cancel() {
        recorder.cancel()
    }
}
