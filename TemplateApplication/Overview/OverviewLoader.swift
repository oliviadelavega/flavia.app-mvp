//
// Flavia study app
//
// Read-side helpers for the Overview tab: pulls the most recent
// symptom logs and meals from Firestore for the signed-in user.
//

@preconcurrency import FirebaseFirestore
import Foundation


extension TemplateApplicationStandard {
    /// Most recent symptom logs, keyed by their YYYY-MM-DD document ID.
    func fetchSymptomLogs(days: Int) async throws -> [String: SymptomLog] {
        if FeatureFlags.disableFirebase {
            return [:]
        }

        let snapshot = try await configuration.userDocumentReference
            .collection("symptomLogs")
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: days)
            .getDocuments()

        var result: [String: SymptomLog] = [:]
        for doc in snapshot.documents {
            if let log = try? doc.data(as: SymptomLog.self) {
                result[doc.documentID] = log
            }
        }
        return result
    }

    /// Meals logged within the last `days` days, newest first.
    func fetchMealLogs(days: Int) async throws -> [MealLog] {
        if FeatureFlags.disableFirebase {
            return []
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let snapshot = try await configuration.userDocumentReference
            .collection("meals")
            .whereField("loggedAt", isGreaterThan: Timestamp(date: cutoff))
            .order(by: "loggedAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { try? $0.data(as: MealLog.self) }
    }
}
