import Foundation

/// Unified coordinator for evaluating interview answers.
/// Automatically routes evaluations: prioritizes the Online Backend (Gemini Flash-Lite),
/// and seamlessly fails over to On-Device Apple Intelligence (Foundation Models)
/// if network connectivity drops or the backend cannot be reached.
final class AIEvaluationCoordinator: Sendable {
    static let shared = AIEvaluationCoordinator()

    private init() {}

    /// Evaluates an interview answer using automatic system selection and resilient failover.
    /// Tries online evaluation first; if the connection drops or fails, automatically evaluates on-device.
    func evaluate(input: AIEvaluationInput, mode: AIEvaluationMode = .online) async throws -> UnifiedAIEvaluation {
        // If explicitly requested offline or in automatic online-first mode:
        if mode == .offline {
            return try await AppleFoundationModelsService.shared.evaluate(input: input)
        }

        // Automatic mode (online first, with seamless on-device failover)
        do {
            let onlineEvaluation = try await RehearseBackendClient.shared.evaluate(input: input)
            return onlineEvaluation
        } catch {
            print("[AIEvaluationCoordinator] Online evaluation unavailable (\(error.localizedDescription)). Seamlessly falling back to on-device Apple Foundation Models...")
            do {
                let offlineEvaluation = try await AppleFoundationModelsService.shared.evaluate(input: input)
                return offlineEvaluation
            } catch let fallbackError {
                print("[AIEvaluationCoordinator] Offline failover encountered error: \(fallbackError.localizedDescription)")
                // Re-throw original or fallback error
                throw error
            }
        }
    }

    /// Dynamically generates tailored, high-signal interview questions for the candidate's exact
    /// company, role, experience level, and background.
    /// Prioritizes Online Gemini Flash-Lite, with automatic failover to on-device Apple Intelligence.
    func generateQuestions(for interview: Interview, resume: ResumeContext?) async -> [InterviewTurn] {
        do {
            let items = try await RehearseBackendClient.shared.generateQuestions(
                company: interview.company,
                role: interview.role,
                experienceLevel: interview.experienceLevel,
                interviewType: interview.type,
                durationMinutes: interview.durationMinutes,
                resume: resume
            )
            if !items.isEmpty {
                return items.enumerated().map { index, item in
                    InterviewTurn(
                        id: item.id.isEmpty ? "ai-q-\(index + 1)" : item.id,
                        question: item.question,
                        origin: item.origin ?? "Tailored for \(interview.role)",
                        mockAnswer: "",
                        followUp: nil,
                        moment: InterviewTurn.Moment(kind: .strength, note: item.topic ?? "\(interview.role) Competency")
                    )
                }
            }
        } catch {
            print("[AIEvaluationCoordinator] Online question generation error (\(error.localizedDescription)). Seamlessly falling back to on-device Apple Foundation Models...")
        }

        return await AppleFoundationModelsService.shared.generateQuestions(for: interview, resume: resume)
    }

    /// Converts a UnifiedAIEvaluation into the app's existing `Feedback` model
    /// so the existing radar charts, score donuts, and area breakdowns are seamlessly populated.
    static func convertToFeedback(
        evaluation: UnifiedAIEvaluation,
        interview: Interview,
        plannedTurns: [InterviewTurn],
        answeredTurns: [InterviewTurn],
        measurements: Measurements?
    ) -> Feedback {
        let res = evaluation.evaluation_result
        let overall100 = evaluation.scoreOutOf100

        // Map criteria scores to 0-100 scale
        let technicalScore = Int(Double(res.evaluation.correctness.score + res.evaluation.completeness.score + res.evaluation.technical_depth.score) / 30.0 * 100.0)
        let commScore = Int(Double(res.communication.clarity + res.communication.structure + res.communication.conciseness) / 30.0 * 100.0)
        let problemSolvingScore = Int(Double(res.evaluation.relevance.score + res.evaluation.technical_depth.score) / 20.0 * 100.0)

        // Focus area selection from weaknesses
        let primaryFocus: Skill
        if let firstWeakness = res.weaknesses.first?.lowercased() {
            if firstWeakness.contains("trade") || firstWeakness.contains("compromise") {
                primaryFocus = .tradeoffs
            } else if firstWeakness.contains("concrete") || firstWeakness.contains("metric") || firstWeakness.contains("result") {
                primaryFocus = .concreteResults
            } else {
                primaryFocus = .answerStructure
            }
        } else {
            primaryFocus = .answerStructure
        }

        let focusEvidence = res.feedback.what_to_improve.isEmpty ? (res.weaknesses.first ?? "Focus on structuring key decisions upfront.") : res.feedback.what_to_improve

        var feedback = Feedback(
            overall: overall100,
            communication: commScore,
            communicationNote: res.communication.notes.isEmpty ? "Clear structure and delivery." : res.communication.notes,
            answerQuality: technicalScore,
            answerQualityNote: res.feedback.what_went_well,
            summary: res.feedback.summary,
            strengths: Array(res.strengths.prefix(3)),
            focus: primaryFocus,
            focusEvidence: focusEvidence,
            coverageNote: answeredTurns.count < plannedTurns.count ? "Based on \(answeredTurns.count) of \(plannedTurns.count) questions." : nil,
            deduction: 0
        )

        func toVerdict(_ score: Int) -> JudgedPart.Verdict {
            if score >= 8 { return .met }
            if score >= 5 { return .partly }
            return .missed
        }

        // Judged parts mapped to the domain schema
        let parts: [JudgedPart] = [
            JudgedPart(key: .concept, verdict: toVerdict(res.evaluation.correctness.score), evidence: res.evaluation.correctness.feedback),
            JudgedPart(key: .completeness, verdict: toVerdict(res.evaluation.completeness.score), evidence: res.evaluation.completeness.feedback),
            JudgedPart(key: .application, verdict: toVerdict(res.evaluation.technical_depth.score), evidence: res.evaluation.technical_depth.feedback),
            JudgedPart(key: .terminology, verdict: toVerdict(res.evaluation.clarity.score), evidence: res.evaluation.clarity.feedback),
            JudgedPart(key: .relevance, verdict: toVerdict(res.evaluation.relevance.score), evidence: res.evaluation.relevance.feedback),
            JudgedPart(key: .understanding, verdict: toVerdict(res.evaluation.relevance.score), evidence: "Topical focus"),
            JudgedPart(key: .approach, verdict: toVerdict(res.evaluation.technical_depth.score), evidence: "Technical approach"),
            JudgedPart(key: .logicalReasoning, verdict: toVerdict(res.evaluation.clarity.score), evidence: "Clarity of reasoning"),
            JudgedPart(key: .tradeoffs, verdict: toVerdict(res.evaluation.technical_depth.score), evidence: "Architectural trade-offs")
        ]

        feedback.verdicts = parts
        feedback.measurements = measurements
        return feedback
    }
}
