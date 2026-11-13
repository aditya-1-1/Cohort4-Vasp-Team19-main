import Foundation
import Observation
import SwiftUI

/// The interview setup sheet's view model. For an upcoming interview the
/// context is already known; a custom mock asks for the company and role,
/// experience level and type. Both end with the resume the interviewer reads.
@Observable
final class InterviewSetupViewModel {
    let mode: SetupMode

    var role = ""
    var company = ""
    var type: InterviewType = .technical
    var experienceLevel = MockData.candidateExperienceLevel
    /// Typed when Experience Level is Custom.
    var customExperience = ""
    var durationMinutes = 20
    /// AI Evaluation Mode: Online (Gemini Flash-Lite) vs Offline (Apple Foundation Models)
    var evaluationMode: AIEvaluationMode = .online
    /// Availability of Apple Foundation Models on this device
    var appleFMAvailability: AppleFoundationModelsService.AvailabilityState {
        AppleFoundationModelsService.shared.checkAvailability()
    }
    /// Starts as the version made for this interview, or the Profile resume.
    var resumeChoice: ResumeChoice?
    /// A file being read, or one that couldn't be, when uploading here.
    private(set) var upload: ResumeStatus = .none
    private var hasAppeared = false

    init(mode: SetupMode) {
        self.mode = mode
    }

    /// Sets the starting choices once. Coming back from the Resume Library
    /// keeps what was chosen there.
    func prepare(in appState: AppState) {
        guard !hasAppeared else { return }
        hasAppeared = true
        if case .upcoming(let id) = mode, let upcoming = appState.upcomingInterview(id: id) {
            durationMinutes = upcoming.durationMinutes
            resumeChoice = appState.defaultResumeChoice(for: id)
        } else {
            resumeChoice = appState.defaultResumeChoice(for: nil)
        }
    }

    /// The interview that will be rehearsed. For the upcoming interview its
    /// identity is kept, so the rehearsal counts towards it on Home.
    func interview(in appState: AppState) -> Interview? {
        switch mode {
        case .upcoming(let id):
            guard var upcoming = appState.upcomingInterview(id: id) else { return nil }
            upcoming.durationMinutes = durationMinutes
            return upcoming
        case .custom:
            let role = role.trimmingCharacters(in: .whitespaces)
            let company = company.trimmingCharacters(in: .whitespaces)
            let level = experienceLevel == Interview.customExperience
                ? customExperience.trimmingCharacters(in: .whitespaces)
                : experienceLevel
            guard !role.isEmpty, !level.isEmpty else { return nil }
            return Interview(
                role: role,
                company: company.isEmpty ? nil : company,
                experienceLevel: level,
                type: type,
                durationMinutes: durationMinutes
            )
        }
    }

    func start(in appState: AppState) {
        guard let interview = interview(in: appState) else { return }
        appState.startInterview(
            interview,
            resume: resumeChoice.flatMap(appState.resumeContext(for:)),
            mode: evaluationMode
        )
    }

    func resumeFooter(in appState: AppState) -> String {
        guard let resumeChoice, appState.resumeContext(for: resumeChoice) != nil else {
            return "Without a resume, you’ll get general questions."
        }
        return "The interviewer will ask about the projects on this resume."
    }

    /// A first resume is saved to the Profile; otherwise the file is used for
    /// this interview only, so the Profile resume is never replaced by surprise.
    func read(_ fileName: String, in appState: AppState) {
        upload = .parsing(fileName: fileName)
        Task {
            let result = await AppState.readResume(named: fileName)
            guard upload == .parsing(fileName: fileName) else { return }
            withAnimation {
                guard let context = result.context else {
                    upload = result
                    return
                }
                upload = .none
                if appState.resume.context == nil {
                    appState.resume = result
                    resumeChoice = .original
                } else {
                    resumeChoice = .uploaded(context)
                }
            }
        }
    }
}
