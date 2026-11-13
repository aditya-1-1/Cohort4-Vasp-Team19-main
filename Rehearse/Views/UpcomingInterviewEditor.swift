import SwiftUI

/// Adds one of the candidate's real upcoming interviews, or reschedules one.
/// Only the facts that change the rehearsal are asked for; experience level
/// comes from the candidate, and rehearsal length is chosen at setup. Once
/// added, an interview's company, role, type and time are fixed, since
/// rehearsals already done were for that interview, so only its date can
/// change.
struct UpcomingInterviewEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: UpcomingInterviewEditorViewModel
    @State private var isConfirmingRemoval = false
    private var isNew: Bool { viewModel.isNew }
    private var draft: Interview { viewModel.draft }

    init(interview: Interview? = nil) {
        _viewModel = State(initialValue: UpcomingInterviewEditorViewModel(interview: interview))
    }

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section {
                        LabeledTextField(title: "Company Name", text: $viewModel.company, prompt: "Enter company name", contentType: .organizationName)
                        LabeledTextField(title: "Role", text: $viewModel.draft.role, prompt: "Enter job role", contentType: .jobTitle)
                    }

                    Section {
                        ForEach(InterviewType.allCases) { option in
                            InterviewTypeRow(type: option, isSelected: draft.type == option) { viewModel.draft.type = option }
                        }
                    } header: {
                        Text("Interview Type")
                            .listHeadingInset()
                    }
                } else {
                    Section {
                        LabeledContent("Company Name", value: draft.company ?? "")
                        LabeledContent("Role", value: draft.role)
                        LabeledContent("Interview Type", value: draft.type.rawValue)
                    } footer: {
                        Text("To change these, remove the interview and add it again.")
                    }
                }

                Section {
                    DatePicker("Date", selection: $viewModel.day, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                    if isNew {
                        DatePicker("Time", selection: $viewModel.time, displayedComponents: .hourAndMinute)
                    } else {
                        // Set when it was added, and locked after that.
                        LabeledContent("Time") {
                            Label(draft.date?.formatted(date: .omitted, time: .shortened) ?? "", systemImage: "lock.fill")
                                .labelStyle(TrailingIconLabelStyle())
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button("Remove Interview", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                    } footer: {
                        Text("Your past rehearsals stay in History.")
                    }
                }
            }
            .appListStyle()
            .navigationTitle(isNew ? "Add Interview" : "Edit Interview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        viewModel.save(in: appState)
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .confirmationDialog("Remove this interview?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                Button("Remove Interview", role: .destructive) {
                    viewModel.remove(in: appState)
                    dismiss()
                }
            }
        }
    }
}

/// The text, then a small gray symbol after it.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview("Add") {
    UpcomingInterviewEditor()
        .environment(AppState(scenario: .newUser))
}

#Preview("Edit") {
    UpcomingInterviewEditor(interview: MockData.upcomingInterview)
        .environment(AppState())
}
