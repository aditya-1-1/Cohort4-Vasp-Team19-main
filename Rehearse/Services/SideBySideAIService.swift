import Foundation

/// Orchestrator for running Apple AVFoundation + CoreML and Google AI Studio (Gemini) side by side.
@MainActor
final class SideBySideAIService: Sendable {
    static let shared = SideBySideAIService()

    private let enginePreferenceDefaultsKey = "rehearse_selected_ai_engine"

    private init() {}

    /// The user's active AI engine mode: Apple on-device, Google Gemini cloud, or Side-by-Side dual mode.
    var activeEngine: AIEngineType {
        get {
            if let saved = UserDefaults.standard.string(forKey: enginePreferenceDefaultsKey),
               let engine = AIEngineType(rawValue: saved) {
                return engine
            }
            return .sideBySide // Default to side-by-side comparison mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: enginePreferenceDefaultsKey)
        }
    }

    /// Evaluates a question and answer with both Apple On-Device and Google AI Studio simultaneously.
    func evaluateSideBySide(
        question: String,
        answer: String,
        role: String = "Software Engineer",
        interviewType: InterviewType = .technical,
        measurements: Measurements? = nil,
        resume: ResumeContext? = nil
    ) async -> DualAIEvaluation {
        // Run Apple CoreML and Google AI Studio concurrently
        async let appleTask = AppleCoreMLInterviewerService.shared.evaluate(
            question: question,
            answer: answer,
            role: role,
            measurements: measurements,
            resume: resume
        )

        async let googleTask: Result<AIEvaluationResult, Error> = {
            do {
                let res = try await GoogleAIStudioService.shared.evaluate(
                    question: question,
                    answer: answer,
                    role: role,
                    interviewType: interviewType,
                    resume: resume
                )
                return .success(res)
            } catch {
                return .failure(error)
            }
        }()

        let appleResult = await appleTask
        let googleOutcome = await googleTask

        switch googleOutcome {
        case .success(let googleResult):
            return DualAIEvaluation(
                question: question,
                candidateAnswer: answer,
                appleResult: appleResult,
                googleResult: googleResult,
                googleError: nil
            )
        case .failure(let error):
            return DualAIEvaluation(
                question: question,
                candidateAnswer: answer,
                appleResult: appleResult,
                googleResult: nil,
                googleError: error.localizedDescription
            )
        }
    }
}
