//
// Flavia study app
//
// Persists daily symptom check-ins to Firestore. The doc ID is the
// calendar date (YYYY-MM-DD) so re-saving the same day overwrites
// the previous entry — matches the upsert-on-(user_id, date)
// behavior of the reference Supabase schema.
//

@preconcurrency import FirebaseFirestore
import Foundation


extension TemplateApplicationStandard {
    /// Upserts the given symptom log under the current user's document for the given calendar date.
    func storeSymptomLog(_ log: SymptomLog, for date: Date = Date()) async throws {
        if FeatureFlags.disableFirebase {
            logger.debug("Firebase disabled — skipping symptom log save for \(SymptomLogDate.documentID(for: date))")
            return
        }

        let documentID = SymptomLogDate.documentID(for: date)
        try await configuration.userDocumentReference
            .collection("symptomLogs")
            .document(documentID)
            .setData(from: log, merge: true)
    }

    /// Returns the existing symptom log for the given calendar date, or nil if none has been recorded yet.
    func fetchSymptomLog(for date: Date = Date()) async throws -> SymptomLog? {
        if FeatureFlags.disableFirebase {
            return nil
        }

        let documentID = SymptomLogDate.documentID(for: date)
        let snapshot = try await configuration.userDocumentReference
            .collection("symptomLogs")
            .document(documentID)
            .getDocument()
        guard snapshot.exists else {
            return nil
        }
        return try snapshot.data(as: SymptomLog.self)
    }
}
