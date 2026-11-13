import Foundation

/// One message in the chat about an answer.
struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let fromUser: Bool
    let text: String
}
