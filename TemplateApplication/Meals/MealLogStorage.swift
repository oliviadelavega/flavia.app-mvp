//
// Flavia study app
//
// Persists meal entries to Firestore under users/{uid}/meals/{autoId}.
// Each save creates a new document — meals are not upserted per day.
//

@preconcurrency import FirebaseFirestore
import Foundation


extension TemplateApplicationStandard {
    /// Inserts a new meal entry under the current user's document.
    func storeMealLog(_ log: MealLog) async throws {
        if FeatureFlags.disableFirebase {
            logger.debug("Firebase disabled — skipping meal log save")
            return
        }

        _ = try await configuration.userDocumentReference
            .collection("meals")
            .addDocument(from: log)
    }
}
