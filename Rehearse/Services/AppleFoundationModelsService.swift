import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service for on-device offline interview evaluation using Apple's official Foundation Models framework.
/// Runs 100% locally on Apple Neural Engine without network access or cloud API keys.
final class AppleFoundationModelsService: Sendable {
    static let shared = AppleFoundationModelsService()

    private init() {}

    // MARK: - Availability Checking (Section 2.B)

    enum AvailabilityState: Equatable, Sendable {
        case available
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case unsupportedOS
        case unavailable(String)

        var isAvailable: Bool {
            self == .available
        }

        var explanation: String {
            switch self {
            case .available:
                return "Apple Foundation Models is available for on-device offline evaluation."
            case .deviceNotEligible:
                return "This device is not eligible for Apple Intelligence. Please switch to Online AI mode."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off in Settings. Please enable Apple Intelligence or switch to Online AI mode."
            case .modelNotReady:
                return "Apple Foundation Models are downloading or preparing. Please try again shortly or switch to Online AI mode."
            case .unsupportedOS:
                return "Apple Foundation Models requires iOS 26.0 or newer. Please switch to Online AI mode."
            case .unavailable(let reason):
                return "Apple Foundation Models unavailable: \(reason). Please switch to Online AI mode."
            }
        }
    }

    /// Evaluates whether Apple Foundation Models is ready to run on this device.
    func checkAvailability() -> AvailabilityState {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable(let other):
                return .unavailable(String(describing: other))
            }
        } else {
            return .unsupportedOS
        }
        #else
        return .unsupportedOS
        #endif
    }

    // MARK: - On-Device Evaluation

    enum EvaluationError: LocalizedError {
        case modelUnavailable(String)
        case malformedOutput(String)
        case contextExceeded

        var errorDescription: String? {
            switch self {
            case .modelUnavailable(let reason):
                return "Apple Foundation Models is unavailable: \(reason)"
            case .malformedOutput(let details):
                return "On-device model produced malformed evaluation: \(details)"
            case .contextExceeded:
                return "Interview context exceeded on-device model token window."
            }
        }
    }

    /// Executes on-device evaluation using Apple Foundation Models LanguageModelSession.
    func evaluate(input: AIEvaluationInput) async throws -> UnifiedAIEvaluation {
        let availability = checkAvailability()
        guard availability.isAvailable else {
            throw EvaluationError.modelUnavailable(availability.explanation)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let startTime = Date.now

            // Build compact prompt within 4,096 token limit
            let instructions = """
            You are Rehearse, an objective AI interview evaluator.
            Evaluate the candidate's answer against the question, domain, and level.
            Return STRICT JSON matching schema_version 1.0. Do not wrap in markdown or backticks.
            Score every criterion from 0 to 10 based on evidence.
            JSON schema:
            {
              "schema_version": "1.0",
              "question_id": "\(input.question_id)",
              "question_type": "\(input.question_type)",
              "domain": "\(input.domain)",
              "subdomain": "\(input.subdomain)",
              "difficulty": "\(input.difficulty)",
              "overall_score": 0.0,
              "score_label": "",
              "evaluation": {
                "correctness": {"score": 0, "feedback": ""},
                "relevance": {"score": 0, "feedback": ""},
                "completeness": {"score": 0, "feedback": ""},
                "clarity": {"score": 0, "feedback": ""},
                "technical_depth": {"score": 0, "feedback": ""}
              },
              "additional_rubric": {
                "rubric_type": "none",
                "criteria": []
              },
              "communication": {
                "clarity": 0, "structure": 0, "conciseness": 0,
                "filler_word_count": null, "words_per_minute": null, "repeated_word_count": null,
                "notes": ""
              },
              "strengths": ["", ""],
              "weaknesses": [""],
              "missing_concepts": [""],
              "feedback": {
                "summary": "", "what_went_well": "", "what_to_improve": "", "ideal_answer_guidance": ""
              },
              "follow_up": {
                "needed": false, "reason": null, "question": null, "tests": null
              },
              "next_question": {
                "question": null, "domain": null, "difficulty": null, "reason": null
              }
            }
            """

            let prompt = """
            Question: \(input.question)
            Candidate Answer: \(input.candidate_answer)
            Candidate Level: \(input.candidate_level)
            Interview Context: \(input.interview_context)
            """

            let session = LanguageModelSession(instructions: instructions)
            let options = GenerationOptions(temperature: 0.2)

            let response = try await session.respond(to: prompt, options: options)
            let rawContent = response.content

            let cleanedJSON = Self.cleanJSON(rawContent)
            guard let jsonData = cleanedJSON.data(using: .utf8) else {
                throw EvaluationError.malformedOutput("Could not convert output to data")
            }

            var parsed: StructuredEvaluationPayload
            do {
                let decoder = JSONDecoder()
                parsed = try decoder.decode(StructuredEvaluationPayload.self, from: jsonData)
            } catch {
                // Controlled repair attempt
                let repairPrompt = "Fix syntax errors in this JSON and output ONLY the valid JSON object:\n\n\(cleanedJSON)"
                let repairSession = LanguageModelSession()
                let repairResponse = try await repairSession.respond(to: repairPrompt, options: GenerationOptions(temperature: 0.0))
                let repairedData = Self.cleanJSON(repairResponse.content).data(using: .utf8) ?? Data()
                parsed = try JSONDecoder().decode(StructuredEvaluationPayload.self, from: repairedData)
            }

            // Recalculate score programmatically using Section 7 weights
            let (calculatedScore, label) = ProgrammaticScorer.calculate(
                questionType: input.question_type,
                technical: parsed.evaluation,
                additionalRubric: parsed.additional_rubric
            )
            parsed.overall_score = calculatedScore
            parsed.score_label = label

            // Embed deterministic audio/speech analytics if present
            if let analytics = input.transcript_analytics {
                parsed.communication.words_per_minute = analytics.words_per_minute
                parsed.communication.filler_word_count = analytics.filler_word_count
                parsed.communication.repeated_word_count = analytics.repeated_word_count
            }

            let elapsedMs = Int(Date.now.timeIntervalSince(startTime) * 1000)
            let nowISO = ISO8601DateFormatter().string(from: Date.now)

            return UnifiedAIEvaluation(
                provider: AIProvider.appleFoundationModels.rawValue,
                model_id: "SystemLanguageModel.default",
                execution_mode: "offline",
                evaluation_timestamp: nowISO,
                overall_score: calculatedScore,
                evaluation_schema_version: "1.0",
                latency_ms: elapsedMs,
                evaluation_result: parsed
            )
        }
        #endif

        throw EvaluationError.modelUnavailable("Foundation Models framework not supported on this platform.")
    }

    private static func cleanJSON(_ text: String) -> String {
        var str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("```") {
            str = str.replacingOccurrences(of: "^```[a-zA-Z]*\n?", with: "", options: .regularExpression)
            str = str.replacingOccurrences(of: "\n?```$", with: "", options: .regularExpression)
        }
        if let start = str.firstIndex(of: "{"), let end = str.lastIndex(of: "}") {
            return String(str[start...end])
        }
        return str
    }

    // MARK: - On-Device Dynamic Question Generation

    func generateQuestions(for interview: Interview, resume: ResumeContext?) async -> [InterviewTurn] {
        let comp = interview.company ?? "leading technology company"
        let role = interview.role
        let level = interview.experienceLevel
        let isTech = interview.type == .technical
        let count = Interview.topicCapacity(forMinutes: interview.durationMinutes)

        let questions: [String]
        if isTech {
            let roleLow = role.lowercased()
            if roleLow.contains("ios") || roleLow.contains("apple") || roleLow.contains("swift") || roleLow.contains("mobile") {
                questions = [
                    "When developing software at \(comp), maintaining 60/120fps UI fluidity and minimal battery impact is critical. How do you architect view lifecycles, background synchronization, and state isolation to prevent main thread blocking in \(role)?",
                    "Describe your approach to managing structured concurrency, data-race safety, and actor reentrancy when handling real-time data or audio streams in \(role).",
                    "Walk me through how you architect an offline-first caching and conflict resolution engine for a mobile app at \(comp), specifically handling degraded network connectivity.",
                    "How do you diagnose and eliminate persistent memory leaks, retain cycles, and retain count spikes using platform profiling tools?",
                    "Describe a situation where you had to refactor a core legacy module into modern modular packages while keeping build times minimal and zero regressions."
                ]
            } else if roleLow.contains("ml") || roleLow.contains("ai") || roleLow.contains("data") {
                questions = [
                    "At \(comp), low-latency inference and real-time model serving are essential for \(role). How do you design an inference pipeline to meet sub-50ms p99 SLAs under high query volume?",
                    "How do you detect and mitigate feature drift, covariate shift, and label degradation in continuous production pipelines?",
                    "Explain how you design an evaluation harness and guardrails to benchmark LLM outputs and structured schema adherence in production.",
                    "Walk me through how you approach feature engineering and storage tradeoffs between a real-time feature store and offline batch data lakes."
                ]
            } else if roleLow.contains("backend") || roleLow.contains("distributed") || roleLow.contains("cloud") || roleLow.contains("systems") {
                questions = [
                    "For a mission-critical backend service at \(comp), how do you ensure high availability and partition tolerance while preventing split-brain scenarios and data loss in \(role)?",
                    "Walk me through how you implement distributed idempotency and distributed rate limiting across multi-region server clusters.",
                    "How do you design a database sharding and indexing strategy when a relational database exceeds write throughput limits?",
                    "Explain how you handle cascading failures, thundering herds, and circuit breaking when third-party upstream dependencies fail."
                ]
            } else {
                questions = [
                    "As a \(level) \(role) at \(comp), how do you structure an end-to-end architecture to balance fast iteration velocity with long-term maintainability and system resilience?",
                    "Describe how you design APIs and contracts between client consumers and distributed backend microservices to ensure graceful error handling and forward compatibility.",
                    "Walk me through a complex architectural tradeoff you made where you had to sacrifice one system property for another.",
                    "How do you approach automated testing, end-to-end integration verification, and deployment safety in a continuous delivery pipeline?"
                ]
            }
        } else {
            questions = [
                "Tell me about a high-stakes technical initiative you drove as a \(level) \(role) at \(comp) where you encountered conflicting cross-functional priorities. How did you achieve consensus?",
                "Describe an instance where you pushed back against an unrealistic project deadline or scope requirement. What empirical data and architectural alternatives did you present to leadership?",
                "Can you share an experience where a production bug or outage occurred due to an unforeseen edge case under your watch? How did you manage the immediate remediation and post-mortem?",
                "How do you handle a situation where two senior engineers on your team strongly disagree on an architectural decision or technology choice?"
            ]
        }

        let selected = Array(questions.prefix(count))
        return selected.enumerated().map { idx, q in
            InterviewTurn(
                id: "ondevice-q-\(idx + 1)",
                question: q,
                origin: "Tailored for \(level) \(role) at \(comp)",
                mockAnswer: "",
                followUp: nil,
                moment: InterviewTurn.Moment(kind: .strength, note: "\(role) Assessment")
            )
        }
    }
}

