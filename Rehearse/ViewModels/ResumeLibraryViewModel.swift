import Foundation
import Observation

/// The resume library's view model: every resume the candidate has had,
/// the ones in use now above the ones from before, narrowed by kind or a
/// search.
@Observable
final class ResumeLibraryViewModel {
    enum Kind: String, CaseIterable {
        case uploaded = "Uploaded"
        case tailored = "Tailored"
    }

    /// One resume in the library, however it came to be.
    struct Entry: Identifiable {
        let id: String
        let choice: ResumeChoice
        let kind: Kind
        let title: String
        let subtitle: String
        let date: Date?
    }

    var searchText = ""
    var kind: Kind?

    func clearFilters() {
        searchText = ""
        kind = nil
    }

    /// The Profile resume, a file added just for this mock, and versions
    /// tailored for upcoming interviews.
    func current(in appState: AppState, selection: ResumeChoice?) -> [Entry] {
        var entries: [Entry] = []
        if let original = appState.resume.context {
            entries.append(Entry(id: "original", choice: .original, kind: .uploaded, title: original.fileName, subtitle: "Your resume", date: nil))
        }
        if case .uploaded(let context) = selection, !appState.pastResumes.contains(where: { $0.context == context }) {
            entries.append(Entry(id: "this-interview", choice: .uploaded(context), kind: .uploaded, title: context.fileName, subtitle: "For this interview only", date: nil))
        }
        entries += appState.tailoredResumes.filter { isCurrent($0, in: appState) }.map(entry)
        return filtered(entries)
    }

    /// Earlier uploads and versions tailored for interviews already done,
    /// newest first.
    func previous(in appState: AppState) -> [Entry] {
        let uploads = appState.pastResumes.map { past in
            Entry(id: past.id.uuidString, choice: .uploaded(past.context), kind: .uploaded, title: past.context.fileName, subtitle: "Uploaded \(dateText(past.uploadedOn))", date: past.uploadedOn)
        }
        let versions = appState.tailoredResumes.filter { !isCurrent($0, in: appState) }.map(entry)
        return filtered((uploads + versions).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) })
    }

    private func isCurrent(_ version: ResumeVersion, in appState: AppState) -> Bool {
        let upcomingCompanies = Set(appState.upcomingInterviews.compactMap(\.company))
        return version.interviewID != nil || version.company.map(upcomingCompanies.contains) ?? true
    }

    private func entry(_ version: ResumeVersion) -> Entry {
        Entry(
            id: version.id.uuidString,
            choice: .tailored(version.id),
            kind: .tailored,
            title: "Tailored for \(version.target)",
            subtitle: "\(version.angle), made \(dateText(version.createdOn))",
            date: version.createdOn
        )
    }

    private func filtered(_ entries: [Entry]) -> [Entry] {
        entries.filter { entry in
            (kind == nil || entry.kind == kind)
                && (searchText.isEmpty
                    || entry.title.localizedCaseInsensitiveContains(searchText)
                    || entry.subtitle.localizedCaseInsensitiveContains(searchText))
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }
}
