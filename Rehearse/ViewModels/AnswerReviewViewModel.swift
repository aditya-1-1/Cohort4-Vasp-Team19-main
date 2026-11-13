import Foundation
import Observation

/// The view model behind one answer's review and its chat with Rehearse.
/// The review keeps it, so going back to the answer and into the chat again
/// keeps the conversation. Every reply is predefined in this prototype.
@Observable
final class AnswerReviewViewModel {
    let entry: TranscriptEntry
    /// The interview's focus, for a follow-up or a strong answer to point at.
    let focus: Skill
    /// This answer scored on the five areas.
    let areas: [AreaScore]

    private(set) var messages: [ChatMessage] = []
    var draft = ""
    private(set) var isTyping = false

    init(entry: TranscriptEntry, focus: Skill, areas: [AreaScore]) {
        self.entry = entry
        self.focus = focus
        self.areas = areas
    }

    /// The answer's score out of 100: from AI evaluation if available, or the average of its areas.
    var score: Int? {
        if let eval = entry.evaluation {
            return eval.scoreOutOf100
        }
        return areas.isEmpty ? nil : Scoring.overall(areas)
    }

    /// The habit this answer is about.
    var skill: Skill { entry.weakSkill ?? focus }

    var askedCount: Int { messages.filter(\.fromUser).count }

    /// Suggested questions not asked yet.
    var suggestions: [String] {
        let asked = Set(messages.filter(\.fromUser).map(\.text))
        let all = entry.weakSkill != nil
            ? ["Why was this marked down?", "Show me a better answer", "How do I practice this?"]
            : ["What made this answer strong?", "How could it be even better?"]
        return all.filter { !asked.contains($0) }
    }

    var canSend: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty && !isTyping }

    func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isTyping else { return }
        messages.append(ChatMessage(fromUser: true, text: question))
        draft = ""
        isTyping = true
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            isTyping = false
            messages.append(ChatMessage(fromUser: false, text: reply(to: question)))
        }
    }

    private func reply(to question: String) -> String {
        switch question {
        case "Why was this marked down?":
            return entry.moment?.note ?? "The point came late, so the details were hard to place."
        case "Show me a better answer":
            return "Open like this: \(skill.exampleOpening) Then give the details."
        case "How do I practice this?":
            return "\(skill.advice) Try it on a question from \(skill.title) in Practice."
        case "What made this answer strong?":
            return entry.moment?.note ?? "You were specific and easy to follow."
        case "How could it be even better?":
            return "Keep it as it is, and add one number for the result."
        default:
            return "Good question. For this answer, the biggest win is this: \(skill.advice)"
        }
    }
}
