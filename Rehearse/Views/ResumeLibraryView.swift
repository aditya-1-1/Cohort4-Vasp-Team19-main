import SwiftUI

/// Every resume the candidate has had, as the Library keeps questions: the
/// ones in use now above the ones from before, each narrowed by kind or a
/// search. Choosing one attaches it to the mock and goes back.
struct ResumeLibraryView: View {
    @Binding var selection: ResumeChoice?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = ResumeLibraryViewModel()

    private typealias Kind = ResumeLibraryViewModel.Kind
    private typealias Entry = ResumeLibraryViewModel.Entry

    var body: some View {
        List {
            Section {
                SearchField(prompt: "Search resumes", text: $viewModel.searchText)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Picker("Kind", selection: $viewModel.kind) {
                    Text("All").tag(Kind?.none)
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if current.isEmpty && previous.isEmpty {
                ContentUnavailableView {
                    Label("No Resumes", systemImage: "magnifyingglass")
                } description: {
                    Text("Nothing matches. Try a different filter.")
                } actions: {
                    Button("Show All Resumes") {
                        viewModel.clearFilters()
                    }
                }
                .listRowBackground(Color.clear)
            }

            if !current.isEmpty {
                Section {
                    ForEach(current) { row($0) }
                } header: {
                    Text("Current")
                        .listHeadingInset()
                } footer: {
                    Text("Your resume and the versions tailored for your upcoming interviews.")
                }
            }

            if !previous.isEmpty {
                Section {
                    ForEach(previous) { row($0) }
                } header: {
                    Text("Previous")
                        .listHeadingInset()
                } footer: {
                    Text("Earlier uploads and versions tailored for interviews you’ve done.")
                }
            }
        }
        .appListStyle()
        .navigationTitle("Resume Library")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Entries

    private var current: [Entry] { viewModel.current(in: appState, selection: selection) }

    private var previous: [Entry] { viewModel.previous(in: appState) }

    // MARK: - Row

    private func row(_ entry: Entry) -> some View {
        let isSelected = entry.choice == selection
        return Button {
            withAnimation { selection = entry.choice }
            dismiss()
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: entry.kind == .tailored ? "wand.and.sparkles" : "doc.text")
                    .font(.title3)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(entry.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: AppTheme.Spacing.xs)
                SelectionMark(isSelected: isSelected)
            }
            .padding(.vertical, AppTheme.Spacing.xxs)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack { ResumeLibraryView(selection: .constant(.original)) }
        .environment(AppState())
}
