import Foundation
import NaturalLanguage
import AVFoundation

/// The AI engine used for conducting and evaluating interviews.
enum AIEngineType: String, CaseIterable, Identifiable, Codable, Sendable {
    case appleOnDevice = "apple_on_device"
    case googleGemini = "google_gemini"
    case sideBySide = "side_by_side"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleOnDevice: "Apple AVFoundation + CoreML"
        case .googleGemini: "Google AI Studio (Gemini)"
        case .sideBySide: "Side-by-Side Dual AI"
        }
    }

    var shortTitle: String {
        switch self {
        case .appleOnDevice: "Apple CoreML"
        case .googleGemini: "Google Gemini"
        case .sideBySide: "Side-by-Side"
        }
    }

    var icon: String {
        switch self {
        case .appleOnDevice: "apple.logo"
        case .googleGemini: "sparkles"
        case .sideBySide: "arrow.left.arrow.right"
        }
    }

    var subtitle: String {
        switch self {
        case .appleOnDevice: "On-device, private, sub-50ms latency using NaturalLanguage & AVFoundation"
        case .googleGemini: "Cloud LLM intelligence via Google AI Studio Gemini API"
        case .sideBySide: "Run both engines simultaneously and compare evaluation, scoring & latency"
        }
    }
}

/// Detailed linguistic measurements produced by Apple's on-device NaturalLanguage & AVFoundation engine.
struct AppleLinguisticMetrics: Hashable, Codable, Sendable {
    var sentimentScore: Double // -1.0 to 1.0 (NLTagger)
    var semanticSimilarity: Double // 0.0 to 1.0 (NLEmbedding)
    var vocabularyRichness: Double // Unique words / total words
    var actionVerbCount: Int
    var technicalTermCount: Int
    var wordsPerMinute: Int?
    var fillerCount: Int
    var pauseCount: Int
    var responseTimeSeconds: Double?

    init(
        sentimentScore: Double = 0.0,
        semanticSimilarity: Double = 0.7,
        vocabularyRichness: Double = 0.6,
        actionVerbCount: Int = 0,
        technicalTermCount: Int = 0,
        wordsPerMinute: Int? = nil,
        fillerCount: Int = 0,
        pauseCount: Int = 0,
        responseTimeSeconds: Double? = nil
    ) {
        self.sentimentScore = sentimentScore
        self.semanticSimilarity = semanticSimilarity
        self.vocabularyRichness = vocabularyRichness
        self.actionVerbCount = actionVerbCount
        self.technicalTermCount = technicalTermCount
        self.wordsPerMinute = wordsPerMinute
        self.fillerCount = fillerCount
        self.pauseCount = pauseCount
        self.responseTimeSeconds = responseTimeSeconds
    }
}

/// Standardized evaluation result from either AI engine.
struct AIEvaluationResult: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var engine: AIEngineType
    var overallScore: Int // 0 - 100
    var communicationScore: Int // 0 - 100
    var technicalScore: Int // 0 - 100
    var problemSolvingScore: Int // 0 - 100
    var projectDepthScore: Int // 0 - 100
    var uncertaintyScore: Int // 0 - 100
    var confidenceScore: Int // 0 - 100

    var summary: String
    var strengths: [String]
    var growthAreas: [String]
    var actionableAdvice: String
    var suggestedFollowUp: String?
    var latencyMs: Int
    var modelName: String

    var appleMetrics: AppleLinguisticMetrics?
    var rawCloudResponse: String?

    init(
        id: UUID = UUID(),
        engine: AIEngineType,
        overallScore: Int,
        communicationScore: Int,
        technicalScore: Int,
        problemSolvingScore: Int,
        projectDepthScore: Int,
        uncertaintyScore: Int,
        confidenceScore: Int,
        summary: String,
        strengths: [String],
        growthAreas: [String],
        actionableAdvice: String,
        suggestedFollowUp: String? = nil,
        latencyMs: Int,
        modelName: String,
        appleMetrics: AppleLinguisticMetrics? = nil,
        rawCloudResponse: String? = nil
    ) {
        self.id = id
        self.engine = engine
        self.overallScore = overallScore
        self.communicationScore = communicationScore
        self.technicalScore = technicalScore
        self.problemSolvingScore = problemSolvingScore
        self.projectDepthScore = projectDepthScore
        self.uncertaintyScore = uncertaintyScore
        self.confidenceScore = confidenceScore
        self.summary = summary
        self.strengths = strengths
        self.growthAreas = growthAreas
        self.actionableAdvice = actionableAdvice
        self.suggestedFollowUp = suggestedFollowUp
        self.latencyMs = latencyMs
        self.modelName = modelName
        self.appleMetrics = appleMetrics
        self.rawCloudResponse = rawCloudResponse
    }
}

/// Dual evaluation holding both Apple and Google AI results side by side.
struct DualAIEvaluation: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var question: String
    var candidateAnswer: String
    var timestamp: Date = Date()
    var appleResult: AIEvaluationResult
    var googleResult: AIEvaluationResult?
    var googleError: String?

    init(
        id: UUID = UUID(),
        question: String,
        candidateAnswer: String,
        timestamp: Date = Date(),
        appleResult: AIEvaluationResult,
        googleResult: AIEvaluationResult? = nil,
        googleError: String? = nil
    ) {
        self.id = id
        self.question = question
        self.candidateAnswer = candidateAnswer
        self.timestamp = timestamp
        self.appleResult = appleResult
        self.googleResult = googleResult
        self.googleError = googleError
    }

    /// Difference between Google overall score and Apple overall score.
    var scoreDelta: Int? {
        guard let g = googleResult else { return nil }
        return g.overallScore - appleResult.overallScore
    }

    /// Latency comparison ratio: how many times faster Apple is compared to Google.
    var speedupRatio: Double? {
        guard let g = googleResult, appleResult.latencyMs > 0 else { return nil }
        return Double(g.latencyMs) / Double(max(appleResult.latencyMs, 1))
    }

    /// Agreement score between 0% and 100%.
    var scoreAgreementPercent: Int? {
        guard let g = googleResult else { return nil }
        let diff = abs(g.overallScore - appleResult.overallScore)
        return max(100 - diff, 0)
    }
}

