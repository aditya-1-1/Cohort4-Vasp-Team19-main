import Foundation
import Observation

/// One collection's view model: its questions, narrowed by a search.
@Observable
final class QuestionCollectionViewModel {
    let collection: QuestionCollection
    var searchText = ""

    init(collection: QuestionCollection) {
        self.collection = collection
    }

    func questions(in appState: AppState) -> [Question] {
        appState.questions(in: collection)
    }

    /// The collection's questions that match the search, or all of them.
    func matchingQuestions(in appState: AppState) -> [Question] {
        let questions = questions(in: appState)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return questions }
        return questions.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
}
