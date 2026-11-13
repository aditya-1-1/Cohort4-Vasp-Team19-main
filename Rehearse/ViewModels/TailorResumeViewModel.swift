import Foundation
import Observation
import SwiftUI

/// The tailor resume screen's view model: which job it's for, tailoring
/// (mocked), and saving the chosen version.
@Observable
final class TailorResumeViewModel {
    enum Phase {
        case input
        case tailoring
        case results([ResumeVersion])
    }

    /// The upcoming interview it's for, or `nil` for another role.
    var interviewID: Interview.ID?
    var company = ""
    var role = ""
    var posting = ""
    private(set) var phase = Phase.input
    var selection = 0

    init(interviewID: Interview.ID?) {
        self.interviewID = interviewID
    }

    var navigationTitle: String {
        switch phase {
        case .input, .tailoring: "Tailor Resume"
        case .results: "Choose a Version"
        }
    }

    /// Starts on the next interview when none was given.
    func prepare(in appState: AppState) {
        if interviewID == nil { interviewID = appState.nextInterview?.id }
    }

    /// The company and role being tailored for, once there's a role.
    func target(in appState: AppState) -> (company: String?, role: String)? {
        if let interviewID, let interview = appState.upcomingInterview(id: interviewID) {
            return (interview.company, interview.role)
        }
        let role = role.trimmingCharacters(in: .whitespaces)
        let company = company.trimmingCharacters(in: .whitespaces)
        guard !role.isEmpty else { return nil }
        return (company.isEmpty ? nil : company, role)
    }

    func tailor(in appState: AppState) {
        guard let target = target(in: appState) else { return }
        withAnimation { phase = .tailoring }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard case .tailoring = phase else { return }
            selection = 0
            withAnimation { phase = .results(MockData.tailoredVersions(company: target.company, role: target.role)) }
        }
    }

    /// Saves the chosen version, linked to the interview it was made for.
    func save(_ version: ResumeVersion, in appState: AppState) {
        var version = version
        version.interviewID = interviewID
        appState.saveTailoredResume(version)
    }
}
