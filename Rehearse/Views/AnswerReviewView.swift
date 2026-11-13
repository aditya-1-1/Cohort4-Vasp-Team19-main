import SwiftUI

/// One answer, reviewed: the question and its score out of 100, the five
/// areas that score is the average of, the answer itself with the part that went
/// wrong marked, how a stronger answer would open, and a way into a chat
/// with Rehearse about it. Opened from a question in Your Score.
struct AnswerReviewView: View {
    let number: Int
    let entry: TranscriptEntry
    /// The interview's focus, for a follow-up or a strong answer to point at.
    let focus: Skill
    /// This answer scored on the five areas.
    let areas: [AreaScore]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var openArea: AreaScore?
    /// Kept here, so going back to the answer and into the chat again
    /// keeps the conversation.
    @State private var viewModel: AnswerReviewViewModel

    init(number: Int, entry: TranscriptEntry, focus: Skill, areas: [AreaScore]) {
        self.number = number
        self.entry = entry
        self.focus = focus
        self.areas = areas
        _viewModel = State(initialValue: AnswerReviewViewModel(entry: entry, focus: focus, areas: areas))
    }

    private var score: Int? { viewModel.score }

    private var skill: Skill { viewModel.skill }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                header
                aiEvaluationDetailsCard
                areasCard
                answerCard
                if !entry.hindiLines.isEmpty {
                    englishCard
                }
                if entry.weakSkill != nil {
                    betterCard
                }
                chatLink
                retakeButton
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            // Exactly the page's width, so it never drifts sideways.
            .containerRelativeFrame(.horizontal)
        }
        .scrollDismissesKeyboard(.interactively)
        .debugScrollAnchor()
        .groupedBackground()
        .navigationTitle(entry.isFollowUp ? "Follow-up" : "Question \(number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Chat

    /// Opens the chat on its own screen, pushed like any other page.
    private var chatLink: some View {
        NavigationLink {
            AnswerChatView(viewModel: viewModel)
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask Rehearse")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(viewModel.messages.isEmpty ? "Questions about this answer" : "\(viewModel.askedCount) asked so far")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.md)
            .cardBackground()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityHint("Opens a chat about this answer")
    }

    // MARK: - Re-take Button

    private var retakeButton: some View {
        Button {
            let question = appState.library.first { $0.text == entry.question } ?? Question(
                id: UUID().uuidString,
                text: entry.question,
                category: .roleBased,
                difficulty: .medium,
                role: appState.targetRole,
                skills: [focus]
            )
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                appState.activePractice = question
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Re-take This Question")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text("Practice again with coaching insights in mind")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.md)
            .cardBackground()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityHint("Practices this question again immediately")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
            // The verdict leads the question on its first line, as in the
            // Review Your Answers list.
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                verdict
                Text(entry.question)
                    .font(.questionInCard)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let score {
                ScoreRing(score: score, caption: "out of 100", size: 84)
            }
        }
        .padding(AppTheme.Spacing.md)
        .cardBackground()
    }

    // MARK: - AI Evaluation Details Card

    @ViewBuilder
    private var aiEvaluationDetailsCard: some View {
        if let eval = entry.evaluation {
            let res = eval.evaluation_result
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Label("Answer Evaluation", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.brand)
                    Spacer()
                    Text("Score: \(eval.scoreOutOf100)/100 (\(res.score_label))")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.brand.opacity(0.12), in: Capsule())
                        .foregroundStyle(AppTheme.brand)
                }

                Divider()

                Text("Technical Rubric Breakdown")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    rubricPill("Correct", score: res.evaluation.correctness.score)
                    rubricPill("Depth", score: res.evaluation.technical_depth.score)
                    rubricPill("Relevance", score: res.evaluation.relevance.score)
                    rubricPill("Clarity", score: res.evaluation.clarity.score)
                    rubricPill("Complete", score: res.evaluation.completeness.score)
                }

                if !res.strengths.isEmpty {
                    Text("Strengths: " + res.strengths.joined(separator: " • "))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.success)
                }

                if !res.weaknesses.isEmpty {
                    Text("Areas to Improve: " + res.weaknesses.joined(separator: " • "))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.record)
                }

                if let fq = res.follow_up.question, res.follow_up.needed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Follow-up Prompted by AI:")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.brand)
                        Text(fq)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(AppTheme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(AppTheme.Spacing.md)
            .cardBackground()
        }
    }

    private func rubricPill(_ name: String, score: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(score)/10")
                .font(.caption.bold())
            Text(name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - What the score came from

    /// This answer on the five areas, and their average. Tap an area for
    /// the parts it's worked out from.
    @ViewBuilder
    private var areasCard: some View {
        if !areas.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                    if index > 0 { Divider().padding(.leading, 52) }
                    Button {
                        openArea = area
                    } label: {
                        AreaRow(area: area)
                    }
                    .buttonStyle(CardRowButtonStyle())
                }
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("Average of the six")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(score ?? 0) / 100")
                        .font(.headline.monospacedDigit())
                }
                .padding(AppTheme.Spacing.md)
            }
            .cardBackground()
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .sheet(item: $openArea) { area in
                NavigationStack {
                    AreaDetailView(area: area)
                }
                .presentationDetents([.large])
                .presentationBackground(AppTheme.background)
            }
        }
    }

    /// The tick, exclamation mark or cross alone, no words.
    @ViewBuilder
    private var verdict: some View {
        if let score {
            VerdictIcon(score: score)
                .font(.body)
        }
    }

    // MARK: - The answer

    /// The answer as it was heard. No recording is kept, only the text. Lines said in Hindi are marked, with their English in
    /// the card below; otherwise the part that went wrong is marked.
    private var answerCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Your Answer")
                .font(.label)
                .foregroundStyle(.secondary)
            Text(entry.hindiLines.isEmpty ? markedAnswer : saidAnswer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// What was said, with each line said in Hindi marked, so it's clear
    /// which part the English below is for.
    private var saidAnswer: AttributedString {
        var text = AttributedString(entry.spokenAnswer ?? entry.answer)
        for line in entry.hindiLines {
            if let range = text.range(of: line.said) {
                text[range].backgroundColor = AppTheme.graphic.opacity(0.18)
                text[range].foregroundColor = AppTheme.brand
            }
        }
        return text
    }

    /// Each Hindi line, and how to say it in English: what was meant, in
    /// the words to use next time.
    private var englishCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Say It in English")
                .font(.label)
                .foregroundStyle(.secondary)
            ForEach(entry.hindiLines, id: \.self) { line in
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(line.said)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(line.english)
                        .font(.body.weight(.semibold))
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// The answer, with its opening sentence marked when the answer fell
    /// short: that's where the point should have been.
    private var markedAnswer: AttributedString {
        var text = AttributedString(entry.answer)
        guard entry.weakSkill != nil,
              let end = entry.answer.firstIndex(where: { ".!?".contains($0) }) else { return text }
        let firstSentence = String(entry.answer[...end])
        if let range = text.range(of: firstSentence) {
            text[range].backgroundColor = AppTheme.graphic.opacity(0.18)
            text[range].foregroundColor = AppTheme.brand
        }
        return text
    }

    // MARK: - A stronger answer

    private var betterCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Try It Like This")
                .font(.label)
                .foregroundStyle(.secondary)
            Text(skill.exampleOpening)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

// MARK: - Chat screen

/// A chat with Rehearse about one answer, on its own screen: the
/// conversation scrolls, suggested questions sit under it, and the field to
/// type in is pinned above the keyboard, as Messages does. Every reply is
/// predefined in this prototype.
struct AnswerChatView: View {
    @Bindable var viewModel: AnswerReviewViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    // What the chat is about, so it reads on its own.
                    Text(viewModel.entry.question)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, AppTheme.Spacing.xs)
                    bubble(ChatMessage(fromUser: false, text: "Ask me anything about this answer."))
                    ForEach(viewModel.messages) { message in
                        bubble(message)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if viewModel.isTyping {
                        bubble(ChatMessage(fromUser: false, text: "…"))
                            .transition(.opacity)
                    }
                    if !viewModel.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            ForEach(viewModel.suggestions, id: \.self) { suggestion in
                                Button(suggestion) { viewModel.send(suggestion) }
                                    .font(.subheadline.weight(.medium))
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .tint(AppTheme.brand)
                                    .disabled(viewModel.isTyping)
                            }
                        }
                        .padding(.top, AppTheme.Spacing.xs)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(AppTheme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages) {
                withAnimation { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .groupedBackground()
        .navigationTitle("Ask Rehearse")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
            HStack(spacing: AppTheme.Spacing.xs) {
                TextField("Ask about this answer", text: $viewModel.draft, prompt: .prompt("Ask about this answer"))
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit { viewModel.send(viewModel.draft) }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .frame(minHeight: 44)
                    .glassEffect(.regular, in: Capsule())
                Button {
                    viewModel.send(viewModel.draft)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color(.tertiaryLabel) : AppTheme.brand)
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
        }
        .animation(.smooth(duration: 0.3), value: viewModel.messages)
        .animation(.smooth(duration: 0.2), value: viewModel.isTyping)
        #if DEBUG
        .task {
            // `-chat` asks the first suggestion, for screenshots.
            guard ProcessInfo.processInfo.arguments.contains("-chat"), viewModel.messages.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1))
            if let first = viewModel.suggestions.first { viewModel.send(first) }
        }
        #endif
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: AppTheme.Spacing.xs) {
            if message.fromUser { Spacer(minLength: 48) }
            if !message.fromUser {
                // Rehearse speaks as its app icon, as a contact's picture.
                AppLogo(size: 28)
            }
            Text(message.text)
                .font(.body)
                .foregroundStyle(message.fromUser ? Color.white : Color.primary)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xs)
                .background(message.fromUser ? AppTheme.buttonFill : AppTheme.cardFill,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            if !message.fromUser { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: message.fromUser ? .trailing : .leading)
    }
}
