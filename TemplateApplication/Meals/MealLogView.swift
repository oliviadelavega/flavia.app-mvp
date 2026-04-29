//
// Flavia study app
//
// Form for adding a meal entry. Mirrors the food-log UI in the
// MVP_Flavia reference adapted to native SwiftUI idioms.
//

@_spi(TestingSupport) import SpeziAccount
import SpeziViews
import SwiftUI


struct MealLogView: View {
    @Environment(Account.self) private var account: Account?
    @Environment(TemplateApplicationStandard.self) private var standard

    @Binding private var presentingAccount: Bool

    @State private var log = MealLog()
    @State private var viewState: ViewState = .idle
    @State private var showSavedConfirmation = false
    @State private var dictation = MealDictation()
    @State private var dictationBaseline: String = ""
    @State private var dictationAlertMessage: String?
    @State private var suggester = MealTagSuggester()
    @State private var lastSuggestedFor: String?


    var body: some View {
        NavigationStack {
            Form {
                descriptionSection
                timeSection
                tagsSection
                saveSection
            }
            .navigationTitle("Meals")
            .viewStateAlert(state: $viewState)
            .alert("Saved", isPresented: $showSavedConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Meal entry recorded.")
            }
            .alert(
                "Dictation unavailable",
                isPresented: Binding(
                    get: { dictationAlertMessage != nil },
                    set: { if !$0 { dictationAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(dictationAlertMessage ?? "")
            }
            .toolbar {
                if account != nil {
                    AccountButton(isPresented: $presentingAccount)
                }
            }
        }
    }


    init(presentingAccount: Binding<Bool>) {
        self._presentingAccount = presentingAccount
    }


    @ViewBuilder private var descriptionSection: some View {
        Section("What did you eat?") {
            TextField(
                "e.g. oatmeal with berries",
                text: Binding(
                    get: { log.description ?? "" },
                    set: { log.description = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(2...4)
            .disabled(dictation.isRecording)

            dictationButton
            polishButton
        }
        .onChange(of: dictation.transcript) { _, transcript in
            guard dictation.isRecording else { return }
            let separator = dictationBaseline.isEmpty ? "" : " "
            log.description = (dictationBaseline + separator + transcript).isEmpty
                ? nil
                : dictationBaseline + separator + transcript
        }
        .onChange(of: dictation.status) { _, status in
            switch status {
            case .denied(let message), .unavailable(let message), .failed(let message):
                dictationAlertMessage = message
            case .idle, .starting, .recording:
                break
            }
        }
        .onChange(of: dictation.isRecording) { wasRecording, isRecording in
            // When dictation transitions from on → off, the dictated text is at its
            // most error-prone — automatically run the on-device polish + tag pass.
            if wasRecording && !isRecording {
                Task { await applySuggestions(trigger: .dictationStopped) }
            }
        }
    }

    @ViewBuilder private var dictationButton: some View {
        Button {
            Task { await toggleDictation() }
        } label: {
            HStack {
                Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .imageScale(.large)
                    .symbolEffect(.pulse, isActive: dictation.isRecording)
                Text(dictation.isRecording ? "Listening… tap to stop" : "Dictate")
                    .fontWeight(.medium)
                Spacer()
            }
            .foregroundStyle(dictation.isRecording ? Color.red : Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Start dictation")
    }

    @ViewBuilder private var polishButton: some View {
        if suggester.isAvailable {
            Button {
                Task { await applySuggestions(trigger: .manual) }
            } label: {
                HStack {
                    if suggester.isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                            .imageScale(.large)
                    }
                    Text(suggester.isWorking ? "Polishing…" : "Polish & tag")
                        .fontWeight(.medium)
                    Spacer()
                }
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(
                suggester.isWorking ||
                dictation.isRecording ||
                (log.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            )
            .accessibilityLabel("Polish description and suggest tags")
        }
    }

    @ViewBuilder private var timeSection: some View {
        Section("When") {
            DatePicker(
                "Time",
                selection: $log.loggedAt,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }

    @ViewBuilder private var tagsSection: some View {
        Section("Tags") {
            ChipMultiSelect(
                options: MealVocabulary.tags,
                selection: $log.tags
            )
        }
    }

    @ViewBuilder private var saveSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    Text("Save meal")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(viewState == .processing || !canSave)
        }
    }


    private var canSave: Bool {
        !(log.description?.isEmpty ?? true) || !log.tags.isEmpty
    }

    private func toggleDictation() async {
        if dictation.isRecording {
            dictation.stop()
        } else {
            dictationBaseline = log.description ?? ""
            await dictation.start()
        }
    }

    private enum SuggestionTrigger {
        /// Auto-fired right after the user stops dictating.
        case dictationStopped
        /// User tapped the "Polish & tag" button.
        case manual
    }

    private func applySuggestions(trigger: SuggestionTrigger) async {
        let raw = (log.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return
        }
        // Skip the auto-trigger if we already ran the model on this exact input
        // (e.g. user toggled dictation on and off without speaking).
        if trigger == .dictationStopped, lastSuggestedFor == raw {
            return
        }

        guard let suggestion = await suggester.suggest(for: raw) else {
            return
        }

        log.description = suggestion.cleanedDescription
        // Union with existing user-selected tags so a manual chip stays selected
        // even if the model didn't pick it. Keep canonical vocabulary order.
        let combined = Set(log.tags).union(suggestion.tags)
        log.tags = MealVocabulary.tags.filter { combined.contains($0) }
        lastSuggestedFor = suggestion.cleanedDescription
    }

    private func save() async {
        if dictation.isRecording {
            dictation.stop()
        }
        viewState = .processing
        do {
            try await standard.storeMealLog(log)
            viewState = .idle
            log = MealLog()
            dictationBaseline = ""
            showSavedConfirmation = true
        } catch {
            viewState = .error(AnyLocalizedError(error: error))
        }
    }
}


#Preview {
    @Previewable @State var presentingAccount = false

    MealLogView(presentingAccount: $presentingAccount)
        .previewWith(standard: TemplateApplicationStandard()) {
            AccountConfiguration(service: InMemoryAccountService())
        }
}
