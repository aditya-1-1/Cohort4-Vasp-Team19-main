import Foundation
import Observation
import SwiftUI

/// The resume builder's view model: the candidate's notes, what's still
/// missing, writing the resume (mocked), and using it.
@Observable
final class ResumeBuilderViewModel {
    enum Phase: Equatable {
        case form
        case writing
        /// The resume, always written from the notes as they are now, so
        /// editing a project from here updates it straight away.
        case result
    }

    var draft = ResumeDraft.blank
    var phase = Phase.form
    /// The project forms pushed, by index.
    var path: [Int] = []

    var title: String {
        switch phase {
        case .form: "Build Resume"
        case .writing: "Writing"
        case .result: "Your Resume"
        }
    }

    /// Everything marked Required, at least one complete project, and no
    /// project half filled in.
    var canWrite: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.college.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.degree.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.projects.contains(where: \.isComplete)
            && draft.projects.allSatisfy { $0.isComplete || $0.isBlank }
    }

    /// Why Write My Resume can't be pressed yet, in one line.
    var missingNote: String? {
        guard !canWrite else { return nil }
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Add your name to write your resume." }
        let noCollege = draft.college.trimmingCharacters(in: .whitespaces).isEmpty
        let noDegree = draft.degree.trimmingCharacters(in: .whitespaces).isEmpty
        if noCollege || noDegree {
            return noCollege && noDegree ? "Add your college and degree." : noCollege ? "Add your college." : "Add your degree."
        }
        if let half = draft.projects.first(where: { !$0.isComplete && !$0.isBlank }) {
            return half.title.isEmpty ? "Finish your project: add its name and description." : "Finish “\(half.title)”: add a description."
        }
        return "Add a project to write your resume."
    }

    // MARK: - Actions

    /// Picks up the notes left last time, and fills in what the account
    /// already knows.
    func prepare(in appState: AppState) {
        if let saved = appState.resumeDraft {
            draft = saved
            // The resume in use came from these notes: open on it.
            if appState.builderOpensOnPage || (canWrite && appState.resume.context?.fileName == draft.written().fileName) { phase = .result }
        }
        if draft.name.isEmpty { draft.name = appState.account?.fullName ?? appState.candidateName }
        if draft.email.isEmpty { draft.email = appState.account?.email ?? "" }
        if draft.role.isEmpty { draft.role = appState.targetRole }
        appState.builderOpensOnPage = false
    }

    /// Kept as it's typed, so leaving and coming back loses nothing.
    func keepDraft(in appState: AppState) {
        appState.resumeDraft = draft
    }

    /// Adds a blank project and opens its form.
    func addProject() {
        draft.projects.append(ProjectNote(title: "", notes: ""))
        path.append(draft.projects.count - 1)
    }

    func removeProject(at index: Int) {
        _ = draft.projects.remove(at: index)
    }

    func write() {
        withAnimation { phase = .writing }
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard phase == .writing else { return }
            withAnimation(.smooth(duration: 0.4)) { phase = .result }
        }
    }

    func useResume(in appState: AppState) {
        appState.useBuiltResume(draft.written())
    }
}
