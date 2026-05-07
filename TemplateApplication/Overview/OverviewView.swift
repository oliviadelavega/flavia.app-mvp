//
// Flavia study app
//
// Day-by-day rollup of the user's recent answers. Pulls the last
// `daysToShow` days of symptom logs + meals and groups them by date.
//

@_spi(TestingSupport) import SpeziAccount
import SpeziViews
import SwiftUI


struct OverviewView: View {
    private static let daysToShow = 14

    @Environment(Account.self) private var account: Account?
    @Environment(TemplateApplicationStandard.self) private var standard

    @Binding private var presentingAccount: Bool

    @State private var symptomsByDate: [String: SymptomLog] = [:]
    @State private var meals: [MealLog] = []
    @State private var isLoading = false
    @State private var viewState: ViewState = .idle


    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Overview")
                .brandIvoryBackground()
                .viewStateAlert(state: $viewState)
                .refreshable { await load() }
                .task { await load() }
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


    @ViewBuilder private var content: some View {
        if isLoading && symptomsByDate.isEmpty && meals.isEmpty {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(daysInRange, id: \.self) { dayKey in
                    Section(header: Text(headerLabel(for: dayKey))) {
                        let mealsForDay = mealsByDate[dayKey] ?? []
                        let symptom = symptomsByDate[dayKey]

                        if symptom == nil && mealsForDay.isEmpty {
                            Text("No entries")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let symptom {
                            symptomRow(symptom)
                        }

                        ForEach(Array(mealsForDay.enumerated()), id: \.offset) { _, meal in
                            mealRow(meal)
                        }
                    }
                }
            }
        }
    }


    private var daysInRange: [String] {
        let calendar = Calendar.current
        let today = Date()
        return (0..<Self.daysToShow).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
                .map { SymptomLogDate.documentID(for: $0) }
        }
    }

    private var mealsByDate: [String: [MealLog]] {
        Dictionary(grouping: meals) { meal in
            SymptomLogDate.documentID(for: meal.loggedAt)
        }
    }


    private func headerLabel(for dayKey: String) -> String {
        guard let date = SymptomLogDate.date(from: dayKey) else {
            return dayKey
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func symptomRow(_ log: SymptomLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Symptoms", systemImage: "heart.text.square")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 16) {
                if let severity = log.eczemaSeverity {
                    metric("Eczema", value: severity)
                }
                if let itch = log.itchLevel {
                    metric("Itch", value: itch)
                }
                if let stress = log.stressLevel {
                    metric("Stress", value: stress)
                }
            }

            if !log.bodyPartsAffected.isEmpty {
                Text("Affected: \(humanList(log.bodyPartsAffected))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !log.topicalsUsed.isEmpty {
                Text("Topicals: \(humanList(log.topicalsUsed))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let notes = log.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func mealRow(_ meal: MealLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(timeOnly(meal.loggedAt), systemImage: "fork.knife")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            if let desc = meal.description, !desc.isEmpty {
                Text(desc)
                    .font(.body)
            }

            if !meal.tags.isEmpty {
                Text(humanList(meal.tags))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func metric(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)/5")
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    private func humanList(_ tokens: [String]) -> String {
        tokens.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: ", ")
    }

    private func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }


    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let symptoms = standard.fetchSymptomLogs(days: Self.daysToShow)
            async let meals = standard.fetchMealLogs(days: Self.daysToShow)
            self.symptomsByDate = try await symptoms
            self.meals = try await meals
        } catch {
            viewState = .error(AnyLocalizedError(error: error))
        }
    }
}


#Preview {
    @Previewable @State var presentingAccount = false

    OverviewView(presentingAccount: $presentingAccount)
        .previewWith(standard: TemplateApplicationStandard()) {
            AccountConfiguration(service: InMemoryAccountService())
        }
}
