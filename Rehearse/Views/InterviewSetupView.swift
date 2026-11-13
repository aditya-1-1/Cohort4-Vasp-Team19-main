import SwiftUI

/// The last stop before a rehearsal, presented as a sheet. For an upcoming
/// interview the context is already known, so it is shown rather than asked
/// for again; a custom mock asks for the target company and role, experience
/// level and interview type, and offers the length, which sets how many
/// topics are asked. Quick Prep keeps the real interview's length. Both end
/// with the resume the interviewer reads.
struct InterviewSetupView: View {
    let mode: SetupMode

    @Environment(AppState.self) private var appState
    @State private var showsPrivacy = false
    @State private var viewModel: InterviewSetupViewModel
    @State private var resumeSource: ResumeSource?
    @Environment(\.dismiss) private var dismiss

    init(mode: SetupMode) {
        self.mode = mode
        _viewModel = State(initialValue: InterviewSetupViewModel(mode: mode))
    }

    var body: some View {
        List {
            switch mode {
            case .upcoming(let id): upcomingContext(id)
            case .custom: customContext
            }
            lengthSection
            resumeSection
        }
        .appListStyle()
        .navigationTitle(mode == .custom ? "Interview Setup" : "Quick Prep")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .safeAreaBar(edge: .bottom) {
            BottomActions {
                // What happens to the camera and microphone, right where
                // the interview starts, with the details a tap away.
                Button {
                    showsPrivacy = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "lock.fill")
                            .font(.footnote)
                        Text("No video or audio is recorded. Only the text of your answers is kept. \(Text("How It Works").fontWeight(.semibold).foregroundStyle(AppTheme.brand))")
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Explains how your camera and microphone are used")
                PrimaryButton(title: "Start Interview") {
                    viewModel.start(in: appState)
                }
                .disabled(interview == nil)
            }
        }
        .onAppear { viewModel.prepare(in: appState) }
        .resumeSources($resumeSource) { read($0) }
        .sheet(isPresented: $showsPrivacy) {
            NavigationStack { InterviewPrivacyView() }
                .presentationDetents([.large])
        }
    }

    private var interview: Interview? {
        viewModel.interview(in: appState)
    }

    // MARK: - Context

    @ViewBuilder
    private func upcomingContext(_ id: Interview.ID) -> some View {
        if let upcoming = appState.upcomingInterview(id: id) {
            Section {
                HStack(spacing: AppTheme.Spacing.sm) {
                    DateTile(date: upcoming.date)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(upcoming.title)
                            .font(.headline)
                        Text([upcoming.type.interviewName, upcoming.countdownText?.lowercased()].compactMap { $0 }.joined(separator: " "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xxs)
                .accessibilityElement(children: .combine)
            } header: {
                Text("Rehearsing For")
                .listHeadingInset()
            } footer: {
                if let focus = appState.currentFocus {
                    Text("Questions are picked for this role and type. Last time it was your \(focus.title.lowercased()), so keep an eye on that.")
                } else {
                    Text("Questions are picked for this role and type.")
                }
            }
        }
    }

    @ViewBuilder
    private var customContext: some View {
        Section {
            LabeledTextField(title: "Company Name", text: $viewModel.company, prompt: "Optional", contentType: .organizationName)
            LabeledTextField(title: "Job Role", text: $viewModel.role, prompt: "Enter job role", contentType: .jobTitle)
        }

        Section {
            Picker("Experience Level", selection: $viewModel.experienceLevel) {
                ForEach(Interview.experienceLevels + [Interview.customExperience], id: \.self) { Text($0).tag($0) }
            }
            if viewModel.experienceLevel == Interview.customExperience {
                LabeledTextField(title: "Your Level", text: $viewModel.customExperience, prompt: "Enter experience level")
            }
        }

        Section {
            ForEach(InterviewType.allCases) { option in
                typeRow(option)
            }
        } header: {
            Text("Interview Type")
            .listHeadingInset()
        }
    }

    /// One choice, checked when chosen, as in Settings.
    private func typeRow(_ option: InterviewType) -> some View {
        InterviewTypeRow(type: option, isSelected: option == viewModel.type) { viewModel.type = option }
    }

    // MARK: - Options

    /// A custom mock picks its length. Quick Prep rehearses the real
    /// interview, so its length is the interview's own and isn't changed.
    private var lengthSection: some View {
        Section {
            if mode == .custom {
                Picker("Length", selection: $viewModel.durationMinutes) {
                    ForEach(Interview.durations, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
            } else {
                LabeledContent("Length", value: "\(viewModel.durationMinutes) min")
            }
        } footer: {
            if mode != .custom {
                // A mock interview asks for nothing but the choices themselves.
                Text("About \(Interview.topicCapacity(forMinutes: viewModel.durationMinutes)) topics. You can stop early.")
            }
        }
    }
}

// MARK: - Resume

private extension InterviewSetupView {
    /// The resume the interviewer reads. The Profile one is attached already;
    /// it can be swapped for a tailored version or a new file, or removed for
    /// general questions. Nothing here changes the Profile, except that a
    /// first resume uploaded here is saved there too.
    var resumeSection: some View {
        Section {
            if case .parsing(let fileName) = viewModel.upload {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView()
                    Text("Reading \(fileName)…")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, AppTheme.Spacing.xxs)
            } else if let resumeChoice = viewModel.resumeChoice, let context = appState.resumeContext(for: resumeChoice) {
                attachedRow(resumeChoice, context: context)
                profileLink("Choose Another Resume")
                // Leaves it out of this interview only; the resume itself
                // stays, so this isn't a red, destructive action.
                Button("Don’t Use a Resume") {
                    withAnimation { viewModel.resumeChoice = nil }
                }
            } else {
                if case .failed(let fileName, let reason) = viewModel.upload {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                        Label("Couldn’t read \(fileName)", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                        Text(reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, AppTheme.Spacing.xxs)
                }
                if appState.resume.context != nil {
                    profileLink("Choose Resume")
                }
                Button("Upload New File", systemImage: "doc.badge.plus") { resumeSource = .file }
            }
        } header: {
            Text("Resume")
            .listHeadingInset()
        } footer: {
            if mode != .custom {
                Text(resumeFooter)
            }
        }
    }

    /// Pushes every resume the candidate has had, as the Library pushes a
    /// collection.
    func profileLink(_ title: String) -> some View {
        NavigationLink(title) {
            ResumeLibraryView(selection: $viewModel.resumeChoice)
        }
    }

    func attachedRow(_ choice: ResumeChoice, context: ResumeContext) -> some View {
        let title: String
        let subtitle: String
        switch choice {
        case .original:
            title = context.fileName
            subtitle = "Your resume"
        case .tailored(let id):
            let version = appState.tailoredResume(id: id)
            title = "Tailored for \(version?.target ?? "This Role")"
            subtitle = version?.angle ?? context.fileName
        case .uploaded:
            title = context.fileName
            subtitle = "For this interview only"
        }
        return HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "doc.text")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    var resumeFooter: String {
        viewModel.resumeFooter(in: appState)
    }

    func read(_ fileName: String) {
        viewModel.read(fileName, in: appState)
    }
}

#Preview("Upcoming") {
    NavigationStack { InterviewSetupView(mode: .upcoming(MockData.upcomingInterview.id)) }
        .environment(AppState())
}

#Preview("Custom") {
    NavigationStack { InterviewSetupView(mode: .custom) }
        .environment(AppState(scenario: .newUser))
}

/// How the interview uses the camera and microphone, and what's kept, in
/// plain words. Every line here is true of the app as built.
struct InterviewPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row("Camera", "Not used. The picture of you in the call is a placeholder; the camera never turns on.", "video.slash.fill")
                row("Microphone", "Listens only while you answer, to turn what you say into text. On iPhones that support it this happens on the device; otherwise Apple’s speech recognition handles it.", "mic.fill")
                row("What’s Kept", "The text of your answers and your scores, on your iPhone and in your Rehearse account when you’re signed in.", "tray.full.fill")
                row("What’s Not Kept", "Audio and video. Nothing is recorded.", "xmark.circle.fill")
            }
        }
        .appListStyle()
        .navigationTitle("Your Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func row(_ title: String, _ detail: String, _ symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.brand)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
