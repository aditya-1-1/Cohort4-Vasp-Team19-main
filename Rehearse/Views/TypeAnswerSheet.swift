import SwiftUI

/// A sheet allowing the candidate to type their answer instead of speaking it.
/// Useful for noisy environments, accessibility, and simulator testing.
/// The typed answer is evaluated directly by the chosen AI engine (Online Gemini or Offline Apple).
struct TypeAnswerSheet: View {
    let question: String
    let isFollowUp: Bool
    let evaluationMode: AIEvaluationMode
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var answerText = ""
    @FocusState private var isFocused: Bool

    private var wordCount: Int {
        answerText.split(whereSeparator: \.isWhitespace).count
    }

    private var canSubmit: Bool {
        wordCount >= 3
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    // Question banner
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Label(isFollowUp ? "Follow-up Question" : "Interview Question", systemImage: "bubble.left.and.text.bubble.right.fill")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.brand)

                        Text(question)
                            .font(.headline)
                            .foregroundStyle(Color.primary)
                    }
                    .padding(AppTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()

                    // Text editor container
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        ZStack(alignment: .topLeading) {
                            if answerText.isEmpty {
                                Text("Type your answer here in detail...\nExplain your approach, technical trade-offs, or the situation and actions taken.")
                                    .font(.body)
                                    .foregroundStyle(Color.secondary.opacity(0.6))
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                            TextEditor(text: $answerText)
                                .font(.body)
                                .frame(minHeight: 180)
                                .focused($isFocused)
                                .scrollContentBackground(.hidden)
                        }

                        HStack {
                            Text("\(wordCount) \(wordCount == 1 ? "word" : "words")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                    .cardBackground()

                    // Submit button
                    PrimaryButton(title: "Submit Answer", systemImage: "arrow.up.circle.fill") {
                        let finalAnswer = answerText
                        dismiss()
                        onSubmit(finalAnswer)
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1.0 : 0.6)
                }
                .padding(AppTheme.Spacing.md)
            }
            .groupedBackground()
            .navigationTitle(isFollowUp ? "Type Follow-up" : "Type Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

