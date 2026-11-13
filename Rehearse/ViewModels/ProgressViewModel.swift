import Foundation
import Observation

/// The Progress tab's view model. It holds no data of its own: it works out,
/// from the interviews in `AppState`, what the tab shows.
@Observable
final class ProgressViewModel {
    struct Day: Identifiable {
        let date: Date
        let count: Int
        let isFuture: Bool
        var id: Date { date }
    }

    struct AreaRow: Identifiable {
        let area: ScoreArea
        let score: Int
        /// The change since the first interview.
        let delta: Int
        var id: ScoreArea { area }
    }

    struct RecurringSkill: Identifiable {
        let skill: Skill
        /// How many of the recent interviews flagged it.
        let count: Int
        var id: Skill { skill }
    }

    /// Interviews with feedback, oldest first.
    func interviews(in appState: AppState) -> [Rehearsal] {
        appState.interviews.reversed().filter { $0.feedback != nil }
    }

    /// The calendar week, in the locale's order, with rehearsals (interviews
    /// and practice) counted per day.
    func week(in appState: AppState) -> [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let count = appState.rehearsals.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
            return Day(date: day, count: count, isFuture: day > today)
        }
    }

    /// How many interviews "recent" covers.
    static let recentCount = 3

    /// Each weakness flagged in the last three interviews, most often first.
    func recurringSkills(in appState: AppState) -> [RecurringSkill] {
        let recent = appState.interviews.prefix(Self.recentCount)
        return Skill.allCases
            .map { skill in RecurringSkill(skill: skill, count: recent.filter { $0.feedback?.focus == skill }.count) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    /// The six areas, lowest score first so what to work on leads, each
    /// with its change since the first interview.
    func areaRows(in appState: AppState) -> [AreaRow] {
        let interviews = interviews(in: appState)
        return ScoreArea.allCases
            .compactMap { area -> AreaRow? in
                let trend = interviews.compactMap { $0.feedback?.areas.first { $0.area == area }?.score }
                guard let first = trend.first, let last = trend.last else { return nil }
                return AreaRow(area: area, score: last, delta: last - first)
            }
            .sorted { $0.score < $1.score }
    }
}
