//
// Flavia study app
//
// Persists per-user custom meal tags to Firestore at
// users/{uid}/preferences/mealTags as a single document with an array
// field `tags`. Writes use `arrayUnion`/`arrayRemove` so two devices
// editing the list concurrently don't clobber each other.
//

@preconcurrency import FirebaseFirestore
import Foundation


extension TemplateApplicationStandard {
    /// Returns the user's saved custom tags. Empty if the preference doc doesn't exist yet.
    func fetchCustomMealTags() async throws -> [String] {
        if FeatureFlags.disableFirebase {
            return []
        }

        let snapshot = try await configuration.userDocumentReference
            .collection("preferences")
            .document("mealTags")
            .getDocument()
        guard let tags = snapshot.data()?["tags"] as? [String] else {
            return []
        }
        return tags
    }

    func addCustomMealTag(_ tag: String) async throws {
        if FeatureFlags.disableFirebase {
            return
        }

        try await configuration.userDocumentReference
            .collection("preferences")
            .document("mealTags")
            .setData(["tags": FieldValue.arrayUnion([tag])], merge: true)
    }

    func removeCustomMealTag(_ tag: String) async throws {
        if FeatureFlags.disableFirebase {
            return
        }

        try await configuration.userDocumentReference
            .collection("preferences")
            .document("mealTags")
            .setData(["tags": FieldValue.arrayRemove([tag])], merge: true)
    }
}
