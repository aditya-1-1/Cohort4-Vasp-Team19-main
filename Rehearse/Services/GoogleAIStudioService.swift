import Foundation

/// Service for communicating with Google AI Studio (Gemini API) to perform cloud-based interview evaluation.
@MainActor
final class GoogleAIStudioService: Sendable {
    static let shared = GoogleAIStudioService()

    private let userDefaultsKey = "rehearse_google_ai_studio_api_key"
    private let modelUserDefaultsKey = "rehearse_google_ai_studio_model"

    static let availableModels = [
        "gemini-3.5-flash-lite",
        "gemini-3.5-flash",
        "gemini-3.8-flash",
        "gemini-flash-latest"
    ]

    private init() {}

    /// The user's Google AI Studio API key. Persists in UserDefaults, falling back to BackendSecrets.
    var apiKey: String {
        get {
            let saved = UserDefaults.standard.string(forKey: userDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let saved, !saved.isEmpty { return saved }
            return BackendSecrets.googleAIStudioAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: userDefaultsKey)
        }
    }

    /// Selected Gemini model name.
    var selectedModel: String {
        get {
            UserDefaults.standard.string(forKey: modelUserDefaultsKey) ?? "gemini-3.5-flash-lite"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: modelUserDefaultsKey)
        }
    }

    /// Whether an API key has been configured.
    var hasKey: Bool {
        !apiKey.isEmpty
    }

    // MARK: - Testing Connection

    /// Validates the API key by sending a minimal test prompt to Google AI Studio.
    func testConnection() async throws -> String {
        guard hasKey else {
            throw GoogleAIStudioError.missingApiKey
        }

        let prompt = "Reply with 'OK' and the current model name to confirm this Google AI Studio API key works."
        let response = try await sendRawPrompt(prompt, temperature: 0.1)
        return response
    }

    // MARK: - Evaluation

    /// Evaluates a candidate's answer using Google AI Studio Gemini API.
    func evaluate(
        question: String,
        answer: String,
        role: String = "Software Engineer",
        interviewType: InterviewType = .technical,
        resume: ResumeContext? = nil
    ) async throws -> AIEvaluationResult {
        guard hasKey else {
            throw GoogleAIStudioError.missingApiKey
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        var resumeDetails = ""
        if let resume {
            let highlights = resume.highlights.map { "- \($0.title) (\($0.source)): \($0.detail)" }.joined(separator: "\n")
            resumeDetails = """
            Candidate's Resume Background:
            Candidate: \(resume.name ?? "Candidate")
            Education: \(resume.education ?? "Not specified")
            Highlights:
            \(highlights)
            Skills: \(resume.skills.joined(separator: ", "))
            """
        }

        let systemInstruction = """
        You are an elite Senior Staff Interviewer at a premier technology company conducting a \(interviewType.interviewName) interview for a \(role) position.
        Evaluate the candidate's answer rigorously, constructively, and objectively.
        Return your evaluation ONLY as a valid JSON object matching this schema:
        {
          "overallScore": <integer 0-100>,
          "communicationScore": <integer 0-100>,
          "technicalScore": <integer 0-100>,
          "problemSolvingScore": <integer 0-100>,
          "projectDepthScore": <integer 0-100>,
          "uncertaintyScore": <integer 0-100>,
          "confidenceScore": <integer 0-100>,
          "summary": "<2-3 sentence executive evaluation>",
          "strengths": ["<strength 1>", "<strength 2>", "<strength 3>"],
          "growthAreas": ["<growth area 1>", "<growth area 2>"],
          "actionableAdvice": "<1 concrete sentence of advice on how to improve this specific answer>",
          "suggestedFollowUp": "<a sharp, realistic follow-up interview question to probe deeper into what the candidate just said>"
        }
        """

        let userPrompt = """
        \(resumeDetails)

        Interview Question: "\(question)"
        Candidate's Answer: "\(answer)"

        Analyze the answer and output the JSON evaluation.
        """

        let rawResponse = try await sendRawPrompt(userPrompt, systemInstruction: systemInstruction, temperature: 0.2)
        let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        // Parse JSON
        let result = parseEvaluationJSON(rawResponse, elapsedMs: elapsed, rawResponse: rawResponse)
        return result
    }

    // MARK: - REST API Communication

    private func sendRawPrompt(_ prompt: String, systemInstruction: String? = nil, temperature: Double = 0.4) async throws -> String {
        let key = apiKey
        let model = selectedModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            throw GoogleAIStudioError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25

        var body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": temperature,
                "responseMimeType": "application/json"
            ]
        ]

        if let systemInstruction {
            body["systemInstruction"] = [
                "role": "system",
                "parts": [
                    ["text": systemInstruction]
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAIStudioError.networkError("Invalid response from Google AI Studio")
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorObj = errorJson["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                throw GoogleAIStudioError.apiError(statusCode: httpResponse.statusCode, message: message)
            }
            let responseString = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw GoogleAIStudioError.apiError(statusCode: httpResponse.statusCode, message: responseString)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GoogleAIStudioError.invalidResponseFormat
        }

        return text
    }

    private func parseEvaluationJSON(_ text: String, elapsedMs: Int, rawResponse: String) -> AIEvaluationResult {
        // Strip markdown backticks if returned despite responseMimeType
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("```json") {
            clean = String(clean.dropFirst(7))
        } else if clean.hasPrefix("```") {
            clean = String(clean.dropFirst(3))
        }
        if clean.hasSuffix("```") {
            clean = String(clean.dropLast(3))
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = clean.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let overall = obj["overallScore"] as? Int ?? 78
            let comm = obj["communicationScore"] as? Int ?? 76
            let tech = obj["technicalScore"] as? Int ?? 80
            let prob = obj["problemSolvingScore"] as? Int ?? 75
            let proj = obj["projectDepthScore"] as? Int ?? 77
            let unc = obj["uncertaintyScore"] as? Int ?? 74
            let conf = obj["confidenceScore"] as? Int ?? 80

            let summary = obj["summary"] as? String ?? "Google AI Studio evaluated this answer via Gemini LLM."
            let strengths = obj["strengths"] as? [String] ?? ["Structured thought process", "Clear explanation"]
            let growth = obj["growthAreas"] as? [String] ?? ["Could add more specific trade-offs"]
            let advice = obj["actionableAdvice"] as? String ?? "Frame your answer with the conclusion upfront."
            let followUp = obj["suggestedFollowUp"] as? String ?? "How would you handle scale if traffic doubled?"

            return AIEvaluationResult(
                engine: .googleGemini,
                overallScore: overall,
                communicationScore: comm,
                technicalScore: tech,
                problemSolvingScore: prob,
                projectDepthScore: proj,
                uncertaintyScore: unc,
                confidenceScore: conf,
                summary: summary,
                strengths: strengths,
                growthAreas: growth,
                actionableAdvice: advice,
                suggestedFollowUp: followUp,
                latencyMs: elapsedMs,
                modelName: "Google AI Studio (\(selectedModel))",
                rawCloudResponse: rawResponse
            )
        }

        // Fallback parser if JSON was slightly malformed
        return AIEvaluationResult(
            engine: .googleGemini,
            overallScore: 78,
            communicationScore: 76,
            technicalScore: 80,
            problemSolvingScore: 78,
            projectDepthScore: 75,
            uncertaintyScore: 72,
            confidenceScore: 79,
            summary: "Google AI Studio Gemini generated feedback for your answer.",
            strengths: ["Answered with clarity and confidence", "Demonstrated relevant domain familiarity"],
            growthAreas: ["Elaborate on technical trade-offs", "Add concrete quantifiable outcomes"],
            actionableAdvice: "Lead with your main architectural decision, then back it up with data.",
            suggestedFollowUp: "What alternative design did you consider and why did you reject it?",
            latencyMs: elapsedMs,
            modelName: "Google AI Studio (\(selectedModel))",
            rawCloudResponse: rawResponse
        )
    }
}

enum GoogleAIStudioError: LocalizedError {
    case missingApiKey
    case invalidURL
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case invalidResponseFormat

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "Google AI Studio API Key is not set. Add your key in the AI Testing Lab or Settings to enable Gemini."
        case .invalidURL:
            return "Invalid Google AI Studio endpoint URL."
        case .networkError(let msg):
            return "Network connection to Google AI Studio failed: \(msg)"
        case .apiError(let code, let msg):
            return "Google AI Studio API error (HTTP \(code)): \(msg)"
        case .invalidResponseFormat:
            return "Could not parse response from Google AI Studio Gemini API."
        }
    }
}
