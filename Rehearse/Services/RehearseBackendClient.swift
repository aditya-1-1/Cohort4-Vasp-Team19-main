import Foundation

/// Production client for communicating with the Rehearse backend server.
/// Handles online evaluation requests powered by Google Gemini.
final class RehearseBackendClient: Sendable {
    static let shared = RehearseBackendClient()

    /// Backend base URL (default: http://localhost:8080)
    var baseURL: URL {
        if let custom = UserDefaults.standard.string(forKey: "rehearse_backend_base_url"),
           let url = URL(string: custom), !custom.isEmpty {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 35
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    /// Health check to verify Rehearse backend availability
    func checkHealth() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return json?["status"] as? String == "healthy"
        } catch {
            return false
        }
    }

    /// Submits interview answer to the Rehearse backend for online evaluation.
    func evaluate(input: AIEvaluationInput) async throws -> UnifiedAIEvaluation {
        let url = baseURL.appendingPathComponent("api/evaluate")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Rehearse-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let encoder = JSONEncoder()
        req.httpBody = try encoder.encode(input)

        var lastError: Error?
        let maxAttempts = 2

        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if http.statusCode == 200 {
                    let decoder = JSONDecoder()
                    return try decoder.decode(UnifiedAIEvaluation.self, from: data)
                } else if http.statusCode >= 400 && http.statusCode < 500 {
                    // Client error: don't retry malformed requests
                    let errorObj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let msg = errorObj?["error"] as? String ?? "Backend request failed with status \(http.statusCode)"
                    throw NSError(domain: "RehearseBackend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
                } else {
                    // Server error (5xx)
                    let errorObj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let msg = errorObj?["error"] as? String ?? "Backend server error (\(http.statusCode))"
                    throw NSError(domain: "RehearseBackend", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
                }
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(for: .seconds(1.0))
                }
            }
        }

        throw lastError ?? URLError(.unknown)
    }

    // MARK: - Dynamic AI Interview Questions Generation

    struct GenerateQuestionsPayload: Encodable {
        let company: String?
        let role: String
        let experience_level: String
        let interview_type: String
        let duration_minutes: Int
        let resume_context: String?
        let skills: [String]
    }

    struct GeneratedQuestionsResponse: Decodable {
        struct Item: Decodable {
            let id: String
            let question: String
            let topic: String?
            let origin: String?
            let focus: String?
        }
        let questions: [Item]
    }

    /// Asks the AI backend (Gemini 3.5 Flash-Lite) to dynamically generate tailored,
    /// high-signal interview questions tailored to the company, role, level, and resume.
    func generateQuestions(
        company: String?,
        role: String,
        experienceLevel: String,
        interviewType: InterviewType,
        durationMinutes: Int,
        resume: ResumeContext?
    ) async throws -> [GeneratedQuestionsResponse.Item] {
        let url = baseURL.appendingPathComponent("api/generate_questions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Rehearse-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let payload = GenerateQuestionsPayload(
            company: company,
            role: role,
            experience_level: experienceLevel,
            interview_type: interviewType == .technical ? "technical" : "behavioral",
            duration_minutes: durationMinutes,
            resume_context: resume?.text ?? (resume?.highlights.map { "\($0.title): \($0.detail)" }.joined(separator: "\n")),
            skills: resume?.skills ?? []
        )

        let encoder = JSONEncoder()
        req.httpBody = try encoder.encode(payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(GeneratedQuestionsResponse.self, from: data)
        return decoded.questions
    }
}

