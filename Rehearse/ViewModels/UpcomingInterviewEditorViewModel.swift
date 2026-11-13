import Foundation
import Observation

/// The upcoming interview editor's view model: a new interview, or the date
/// of one already added. Once added, its company, role, type and time are
/// fixed, since rehearsals already done were for that interview.
@Observable
final class UpcomingInterviewEditorViewModel {
    var draft: Interview
    let isNew: Bool

    init(interview: Interview?) {
        isNew = interview == nil
        draft = interview ?? Interview(
            role: "",
            company: nil,
            experienceLevel: MockData.candidateExperienceLevel,
            type: .technical,
            date: Calendar.current.date(byAdding: .day, value: 7, to: .now)
        )
    }

    var canSave: Bool {
        draft.company != nil && !draft.role.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A blank company is stored as `nil`, which keeps Save disabled.
    var company: String {
        get { draft.company ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            draft.company = trimmed.isEmpty ? nil : newValue
        }
    }

    var time: Date {
        get { draft.date ?? .now }
        set { draft.date = newValue }
    }

    /// A new day keeps the interview's time.
    var day: Date {
        get { draft.date ?? .now }
        set {
            let calendar = Calendar.current
            let time = calendar.dateComponents([.hour, .minute], from: draft.date ?? .now)
            draft.date = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: newValue) ?? newValue
        }
    }

    func save(in appState: AppState) {
        appState.saveUpcomingInterview(draft)
    }

    func remove(in appState: AppState) {
        appState.removeUpcomingInterview(id: draft.id)
    }
}
