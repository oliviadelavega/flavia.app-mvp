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


    var body: some View {
        NavigationStack {
            Form {
                severitySection
                periodSection
                bodyPartsSection
                topicalsSection
                notesSection
                saveSection
            }
            .navigationTitle("Symptoms")
            .viewStateAlert(state: $viewState)
            .alert("Saved", isPresented: $showSavedConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Today's check-in was recorded.")
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
                options: SymptomVocabulary.bodyParts,
                selection: $log.bodyPartsAffected
            )
        }
    }

    @ViewBuilder private var topicalsSection: some View {
        Section("Topicals used today") {
            ChipMultiSelect(
                options: SymptomVocabulary.topicals,
                selection: $log.topicalsUsed
            )
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
        }
    }

    @ViewBuilder private var saveSection: some View {
        Section {
            Button {
                Task { await save() }
            } label: {
                HStack {
                    Spacer()
                    Text("Save check-in")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(viewState == .processing)
        }
    }


    private func save() async {
        viewState = .processing
        do {
            try await standard.storeSymptomLog(log)
            reminders.cancelToday()
            await reminders.ensureRollingWindow()
            viewState = .idle
            log = SymptomLog()
            showSavedConfirmation = true
        } catch {
            viewState = .error(AnyLocalizedError(error: error))
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
