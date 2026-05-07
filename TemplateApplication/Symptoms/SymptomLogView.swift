//
// Flavia study app
//
// Daily symptom check-in form. Mirrors the `manual_log` daily check-in
// from the MVP_Flavia reference, adapted to native SwiftUI idioms.
//

@_spi(TestingSupport) import SpeziAccount
import SpeziViews
import SwiftUI


struct SymptomLogView: View {
    @Environment(Account.self) private var account: Account?
    @Environment(TemplateApplicationStandard.self) private var standard
    @Environment(SymptomReminderScheduler.self) private var reminders

    @Binding private var presentingAccount: Bool

    @State private var log = SymptomLog()
    @State private var viewState: ViewState = .idle
    @State private var showSavedConfirmation = false
    @State private var hasExistingEntry = false
    @State private var customBodyParts: [String] = []
    @State private var newCustomBodyPart: String = ""
    @State private var customBodyPartError: String?
    @State private var customTopicals: [String] = []
    @State private var newCustomTopical: String = ""
    @State private var customTopicalError: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case notes
        case customBodyPart
        case customTopical
    }


    var body: some View {
        NavigationStack {
            Form {
                if hasExistingEntry {
                    existingEntryBanner
                }
                severitySection
                periodSection
                bodyPartsSection
                topicalsSection
                notesSection
                saveSection
            }
            .navigationTitle("Symptoms")
            .brandIvoryBackground()
            .task { await loadInitialState() }
            .viewStateAlert(state: $viewState)
            .alert("Saved", isPresented: $showSavedConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(hasExistingEntry ? "Today's check-in was updated." : "Today's check-in was recorded.")
            }
            .toolbar {
                if account != nil {
                    AccountButton(isPresented: $presentingAccount)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }


    init(presentingAccount: Binding<Bool>) {
        self._presentingAccount = presentingAccount
    }


    @ViewBuilder private var existingEntryBanner: some View {
        Section {
            Label("Editing today's check-in. Your previous answers are pre-filled — adjust anything that's changed.", systemImage: "arrow.clockwise")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.brandBlush.opacity(0.4))
    }

    @ViewBuilder private var severitySection: some View {
        Section {
            ScalePicker(
                title: "Eczema severity",
                anchors: ("clear", "severe"),
                selection: $log.eczemaSeverity
            )
            ScalePicker(
                title: "Itch level",
                anchors: ("none", "unbearable"),
                selection: $log.itchLevel
            )
            ScalePicker(
                title: "Stress level",
                anchors: ("calm", "overwhelmed"),
                selection: $log.stressLevel
            )
        } header: {
            Text("How did today feel?")
        } footer: {
            Text("Rate each from 0 to 5.")
        }
    }

    @ViewBuilder private var periodSection: some View {
        Section("On your period today?") {
            Picker("On your period today?", selection: $log.onPeriod) {
                Text("Skip").tag(Bool?.none)
                Text("No").tag(Bool?.some(false))
                Text("Yes").tag(Bool?.some(true))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder private var bodyPartsSection: some View {
        Section("Body parts affected") {
            ChipMultiSelect(
                options: SymptomVocabulary.bodyParts + customBodyParts,
                selection: $log.bodyPartsAffected
            )
            addCustomBodyPartRow
        }
    }

    @ViewBuilder private var addCustomBodyPartRow: some View {
        HStack {
            TextField("Add custom body part", text: $newCustomBodyPart)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .customBodyPart)
                .submitLabel(.done)
                .onSubmit { Task { await addCustomBodyPart() } }
            Button("Add") {
                Task { await addCustomBodyPart() }
            }
            .disabled(newCustomBodyPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let customBodyPartError {
            Text(customBodyPartError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder private var topicalsSection: some View {
        Section("Topicals used today") {
            ChipMultiSelect(
                options: SymptomVocabulary.topicals + customTopicals,
                selection: $log.topicalsUsed
            )
            addCustomTopicalRow
        }
    }

    @ViewBuilder private var addCustomTopicalRow: some View {
        HStack {
            TextField("Add custom topical", text: $newCustomTopical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .customTopical)
                .submitLabel(.done)
                .onSubmit { Task { await addCustomTopical() } }
            Button("Add") {
                Task { await addCustomTopical() }
            }
            .disabled(newCustomTopical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let customTopicalError {
            Text(customTopicalError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder private var notesSection: some View {
        Section("Notes") {
            TextField(
                "Anything else worth remembering",
                text: Binding(
                    get: { log.notes ?? "" },
                    set: { log.notes = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3...6)
            .focused($focusedField, equals: .notes)
        }
    }

    @ViewBuilder private var saveSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    Text(hasExistingEntry ? "Update check-in" : "Save check-in")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(viewState == .processing)
        }
    }


}


extension SymptomLogView {
    fileprivate func save() async {
        viewState = .processing
        do {
            try await standard.storeSymptomLog(log)
            reminders.cancelToday()
            await reminders.ensureRollingWindow()
            viewState = .idle
            // Keep the just-saved values on screen so re-opening the form later
            // today shows what was recorded; flip into "editing" mode.
            hasExistingEntry = true
            showSavedConfirmation = true
        } catch {
            viewState = .error(AnyLocalizedError(error: error))
        }
    }

    fileprivate func loadInitialState() async {
        async let bodyParts = (try? await standard.fetchCustomBodyParts()) ?? []
        async let topicals = (try? await standard.fetchCustomTopicals()) ?? []
        async let existing: SymptomLog? = (try? await standard.fetchSymptomLog()) ?? nil
        customBodyParts = await bodyParts
        customTopicals = await topicals
        if let existing = await existing {
            log = existing
            hasExistingEntry = true
        }
    }

    fileprivate func addCustomBodyPart() async {
        customBodyPartError = nil
        let normalized = newCustomBodyPart
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return }
        guard normalized.count <= 30 else {
            customBodyPartError = "Tags must be 30 characters or fewer."
            return
        }
        if SymptomVocabulary.bodyParts.contains(normalized) || customBodyParts.contains(normalized) {
            customBodyPartError = "\"\(normalized)\" is already in your list."
            return
        }

        do {
            try await standard.addCustomBodyPart(normalized)
            customBodyParts.append(normalized)
            if !log.bodyPartsAffected.contains(normalized) {
                log.bodyPartsAffected.append(normalized)
            }
            newCustomBodyPart = ""
        } catch {
            customBodyPartError = "Couldn't save tag. Try again."
        }
    }

    fileprivate func addCustomTopical() async {
        customTopicalError = nil
        let normalized = newCustomTopical
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return }
        guard normalized.count <= 30 else {
            customTopicalError = "Tags must be 30 characters or fewer."
            return
        }
        if SymptomVocabulary.topicals.contains(normalized) || customTopicals.contains(normalized) {
            customTopicalError = "\"\(normalized)\" is already in your list."
            return
        }

        do {
            try await standard.addCustomTopical(normalized)
            customTopicals.append(normalized)
            if !log.topicalsUsed.contains(normalized) {
                log.topicalsUsed.append(normalized)
            }
            newCustomTopical = ""
        } catch {
            customTopicalError = "Couldn't save tag. Try again."
        }
    }
}


#Preview {
    @Previewable @State var presentingAccount = false

    SymptomLogView(presentingAccount: $presentingAccount)
        .previewWith(standard: TemplateApplicationStandard()) {
            AccountConfiguration(service: InMemoryAccountService())
            SymptomReminderScheduler()
        }
}
