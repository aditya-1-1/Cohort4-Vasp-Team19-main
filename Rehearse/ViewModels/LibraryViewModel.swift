import Foundation
import Observation

/// The Library tab's view model: the filters, and how many of the matching
/// questions are shown. Thousands of rows at once make scrolling and
/// filtering heavy, so the list grows a page at a time, and a new filter
/// starts from the top again.
@Observable
final class LibraryViewModel {
    static let pageSize = 50

    var category: QuestionCategory? { didSet { shownCount = Self.pageSize } }
    /// Set when arriving from feedback, looking for questions that build a skill.
    var focus: Skill? { didSet { shownCount = Self.pageSize } }
    var difficulty: Difficulty? { didSet { shownCount = Self.pageSize } }
    /// One subject, such as System Design, or every subject.
    var area: String? { didSet { shownCount = Self.pageSize } }
    private(set) var shownCount = LibraryViewModel.pageSize

    init(focus: Skill?) {
        self.focus = focus
    }

    var isFiltered: Bool { difficulty != nil || area != nil }

    func questions(in appState: AppState) -> [Question] {
        appState.questions(category: category, difficulty: difficulty, skill: focus, area: area, matching: "")
    }

    func showMore() {
        shownCount += Self.pageSize * 2
    }

    func clearFilters() {
        category = nil
        difficulty = nil
        area = nil
        focus = nil
    }
}
