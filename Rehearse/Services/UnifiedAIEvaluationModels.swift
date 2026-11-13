import Foundation

// MARK: - AI Evaluation Mode & Provider

enum AIEvaluationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case online = "online"
    case offline = "offline"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .online: return "Online AI"
        case .offline: return "Offline AI"
        }
    }

    var shortTitle: String {
        switch self {
        case .online: return "Online"
        case .offline: return "Offline"
        }
    }

    var icon: String {
        switch self {
        case .online: return "cloud.fill"
        case .offline: return "iphone"
        }
    }

    var subtitle: String {
        switch self {
        case .online: return "Evaluates answers via cloud AI with deep rubric feedback."
        case .offline: return "Evaluates answers locally on-device without internet."
        }
    }
}

enum AIProvider: String, Codable, Sendable {
    case googleGemini = "google_gemini"
    case appleFoundationModels = "apple_foundation_models"

    var displayName: String {
        switch self {
        case .googleGemini: return "Online AI"
        case .appleFoundationModels: return "Offline AI"
        }
    }
}

// MARK: - Input Contract (Section 12)

struct AIEvaluationInput: Codable, Sendable {
    var interview_id: String
    var question_id: String
    var question: String
    var candidate_answer: String
    var domain: String
    var subdomain: String
    var question_type: String
    var difficulty: String
    var candidate_level: String
    var previous_questions: [String] = []
    var previous_answers: [String] = []
    var interview_context: String = ""
    var duration_seconds: Double? = nil
    var transcript_analytics: TranscriptAnalyticsPayload? = nil
}

struct TranscriptAnalyticsPayload: Codable, Sendable {
    var words_per_minute: Int? = nil
    var filler_word_count: Int? = nil
    var repeated_word_count: Int? = nil
}

// MARK: - Unified Evaluation Envelope (Section 2.C & 11)

struct UnifiedAIEvaluation: Codable, Sendable, Hashable {
    var provider: String
    var model_id: String
    var execution_mode: String
    var evaluation_timestamp: String
    var overall_score: Double
    var evaluation_schema_version: String
    var latency_ms: Int?
    var evaluation_result: StructuredEvaluationPayload

    var isOnline: Bool {
        execution_mode == "online"
    }

    var providerDisplayName: String {
        isOnline ? "Online AI" : "Offline AI"
    }

    var providerBadgeText: String {
        isOnline ? "Online AI Evaluation" : "Offline AI Evaluation"
    }

    /// Overall score scaled 0-100 for existing Rehearse UI compatibility
    var scoreOutOf100: Int {
        Int(round(overall_score * 10.0))
    }

    static var sampleGeminiEvaluation: UnifiedAIEvaluation {
        UnifiedAIEvaluation(
            provider: "google_gemini",
            model_id: "gemini-3.5-flash-lite",
            execution_mode: "online",
            evaluation_timestamp: ISO8601DateFormatter().string(from: Date()),
            overall_score: 7.8,
            evaluation_schema_version: "1.0",
            latency_ms: 1850,
            evaluation_result: StructuredEvaluationPayload(
                schema_version: "1.0",
                question_id: "q-caching",
                question_type: "system_design",
                domain: "Software Development and Engineering",
                subdomain: "Distributed Systems & Caching",
                difficulty: "intermediate",
                overall_score: 7.8,
                score_label: "Good",
                evaluation: TechnicalCriteriaMap(
                    correctness: CriterionScore(score: 8, feedback: "Understood Redis TTL and caching layer mechanisms accurately."),
                    relevance: CriterionScore(score: 8, feedback: "Directly addressed the API bottleneck and latency reduction."),
                    completeness: CriterionScore(score: 7, feedback: "Addressed basic eviction and TTL; missed cache stampede prevention."),
                    clarity: CriterionScore(score: 8, feedback: "Clear structure and sequence of architectural components."),
                    technical_depth: CriterionScore(score: 8, feedback: "Good metric awareness (900ms to 100ms response time).")
                ),
                additional_rubric: nil,
                communication: CommunicationMetricsPayload(clarity: 8, structure: 8, conciseness: 8, filler_word_count: 2, words_per_minute: 138, repeated_word_count: 1, notes: "Steady and articulate delivery."),
                strengths: ["Concrete latency numbers", "Appropriate TTL selection for API workload"],
                weaknesses: ["Did not mention distributed invalidation strategy"],
                missing_concepts: ["Cache stampede / mutex lock", "Cache penetration defense"],
                feedback: FeedbackCoachingPayload(
                    summary: "Solid system design rationale with measurable impact metrics.",
                    what_went_well: "You clearly stated both the starting latency and the achieved speedup.",
                    what_to_improve: "Discuss how you handle concurrent cache misses on expired keys.",
                    ideal_answer_guidance: "Complement TTL with proactive background refresh or distributed locking."
                ),
                follow_up: FollowUpDecisionPayload(
                    needed: true,
                    reason: "Validate edge-case resilience during cache expiration spikes.",
                    question: "How would you prevent a cache stampede if thousands of users request an expired key simultaneously?",
                    tests: ["Concurrency handling", "Stampede mitigation"]
                ),
                next_question: NextQuestionPayload(
                    question: "How do you maintain cache-database consistency on high-frequency write operations?",
                    domain: "System Design",
                    difficulty: "intermediate",
                    reason: "Naturally builds upon caching into write path consistency."
                )
            )
        )
    }
}

// MARK: - Structured Evaluation Payload (Section 11)

struct StructuredEvaluationPayload: Codable, Sendable, Hashable {
    var schema_version: String
    var question_id: String
    var question_type: String
    var domain: String?
    var subdomain: String?
    var difficulty: String?
    var overall_score: Double
    var score_label: String
    var evaluation: TechnicalCriteriaMap
    var additional_rubric: AdditionalRubricPayload?
    var communication: CommunicationMetricsPayload
    var strengths: [String]
    var weaknesses: [String]
    var missing_concepts: [String]
    var feedback: FeedbackCoachingPayload
    var follow_up: FollowUpDecisionPayload
    var next_question: NextQuestionPayload?
}

struct CriterionScore: Codable, Sendable, Hashable {
    var score: Int
    var feedback: String
}

struct TechnicalCriteriaMap: Codable, Sendable, Hashable {
    var correctness: CriterionScore
    var relevance: CriterionScore
    var completeness: CriterionScore
    var clarity: CriterionScore
    var technical_depth: CriterionScore
}

struct AdditionalCriterion: Codable, Sendable, Hashable {
    var name: String
    var score: Int
    var feedback: String
}

struct AdditionalRubricPayload: Codable, Sendable, Hashable {
    var rubric_type: String
    var criteria: [AdditionalCriterion]
}

struct CommunicationMetricsPayload: Codable, Sendable, Hashable {
    var clarity: Int
    var structure: Int
    var conciseness: Int
    var filler_word_count: Int?
    var words_per_minute: Int?
    var repeated_word_count: Int?
    var notes: String
}

struct FeedbackCoachingPayload: Codable, Sendable, Hashable {
    var summary: String
    var what_went_well: String
    var what_to_improve: String
    var ideal_answer_guidance: String
}

struct FollowUpDecisionPayload: Codable, Sendable, Hashable {
    var needed: Bool
    var reason: String?
    var question: String?
    var tests: [String]?

    enum CodingKeys: String, CodingKey {
        case needed, reason, question, tests
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        needed = try container.decode(Bool.self, forKey: .needed)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        question = try container.decodeIfPresent(String.self, forKey: .question)
        if let stringTests = try? container.decodeIfPresent(String.self, forKey: .tests) {
            tests = [stringTests]
        } else {
            tests = try container.decodeIfPresent([String].self, forKey: .tests)
        }
    }

    init(needed: Bool, reason: String? = nil, question: String? = nil, tests: [String]? = nil) {
        self.needed = needed
        self.reason = reason
        self.question = question
        self.tests = tests
    }
}

struct NextQuestionPayload: Codable, Sendable, Hashable {
    var question: String?
    var domain: String?
    var difficulty: String?
    var reason: String?
}

// MARK: - Programmatic Scoring Formulas (Section 7)

enum ProgrammaticScorer {
    static func calculate(
        questionType: String,
        technical: TechnicalCriteriaMap,
        additionalRubric: AdditionalRubricPayload?
    ) -> (score: Double, label: String) {
        let cleanType = questionType.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        var score = 0.0

        if cleanType == "behavioral", let criteria = additionalRubric?.criteria {
            let map = Dictionary(uniqueKeysWithValues: criteria.map { ($0.name.lowercased(), Double($0.score)) })
            let sit = map["situation_and_context"] ?? map["situation"] ?? 6.0
            let contrib = map["personal_contribution"] ?? map["contribution"] ?? 6.0
            let act = map["actions_and_reasoning"] ?? map["actions"] ?? 6.0
            let out = map["outcome_and_learning"] ?? map["outcome"] ?? 6.0
            score = (sit * 0.20) + (contrib * 0.25) + (act * 0.30) + (out * 0.25)
        } else if cleanType == "project_based" || cleanType == "project", let criteria = additionalRubric?.criteria {
            let map = Dictionary(uniqueKeysWithValues: criteria.map { ($0.name.lowercased(), Double($0.score)) })
            let concept = map["concept"] ?? 6.0
            let completion = map["completion"] ?? 6.0
            let app = map["application"] ?? 6.0
            let terminology = map["terminology"] ?? 6.0
            let ownership = map["ownership"] ?? 6.0
            let claims = map["technical_correctness_of_claims"] ?? map["claims"] ?? 6.0
            score = (concept * 0.15) + (completion * 0.15) + (app * 0.25) + (terminology * 0.10) + (ownership * 0.20) + (claims * 0.15)
        } else if cleanType == "problem_solving" || cleanType == "algorithmic", let criteria = additionalRubric?.criteria {
            let map = Dictionary(uniqueKeysWithValues: criteria.map { ($0.name.lowercased(), Double($0.score)) })
            let und = map["problem_understanding"] ?? map["understanding"] ?? 6.0
            let app = map["approach"] ?? 6.0
            let logic = map["logical_reasoning"] ?? map["reasoning"] ?? 6.0
            let trade = map["trade_offs"] ?? map["tradeoffs"] ?? 6.0
            score = (und * 0.20) + (app * 0.30) + (logic * 0.30) + (trade * 0.20)
        } else {
            // Technical / System Design
            let c = Double(technical.correctness.score)
            let r = Double(technical.relevance.score)
            let comp = Double(technical.completeness.score)
            let cl = Double(technical.clarity.score)
            let d = Double(technical.technical_depth.score)
            score = (c * 0.30) + (r * 0.20) + (comp * 0.20) + (cl * 0.15) + (d * 0.15)
        }

        let rounded = (score * 10).rounded() / 10.0
        let clamped = max(0.0, min(10.0, rounded))

        let label: String
        switch clamped {
        case 9.8...10.0: label = "Exceptional"
        case 9.0..<9.8:  label = "Excellent"
        case 8.0..<9.0:  label = "Very Good"
        case 6.5..<8.0:  label = "Good"
        case 5.0..<6.5:  label = "Average"
        case 3.0..<5.0:  label = "Needs Significant Improvement"
        default:         label = "Very Poor"
        }

        return (clamped, label)
    }
}
