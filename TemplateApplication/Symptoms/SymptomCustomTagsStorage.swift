//
// Flavia study app
//
// Persists per-user custom body parts and topicals to Firestore at
// users/{uid}/preferences/bodyParts and users/{uid}/preferences/topicals
// as documents with an array field `tags`. Writes use `arrayUnion`/
// `arrayRemove` so two devices editing concurrently don't clobber each
// other. Mirrors `MealCustomTagsStorage`.
//

@preconcurrency import FirebaseFirestore
import Foundation


extension TemplateApplicationStandard {
    func fetchCustomBodyParts() async throws -> [String] {
        try await fetchCustomTags(document: "bodyParts")
    }

    func addCustomBodyPart(_ tag: String) async throws {
        try await addCustomTag(tag, document: "bodyParts")
    }

    func removeCustomBodyPart(_ tag: String) async throws {
        try await removeCustomTag(tag, document: "bodyParts")
    }

    func fetchCustomTopicals() async throws -> [String] {
        try await fetchCustomTags(document: "topicals")
    }

    func addCustomTopical(_ tag: String) async throws {
        try await addCustomTag(tag, document: "topicals")
    }

    func removeCustomTopical(_ tag: String) async throws {
        try await removeCustomTag(tag, document: "topicals")
    }


    private func fetchCustomTags(document: String) async throws -> [String] {
        if FeatureFlags.disableFirebase {
            return []
        }

        let snapshot = try await configuration.userDocumentReference
            .collection("preferences")
            .document(document)
            .getDocument()
        guard let tags = snapshot.data()?["tags"] as? [String] else {
            return []
        }
        return tags
    }

    private func addCustomTag(_ tag: String, document: String) async throws {
        if FeatureFlags.disableFirebase {
            return
        }

        try await configuration.userDocumentReference
            .collection("preferences")
            .document(document)
            .setData(["tags": FieldValue.arrayUnion([tag])], merge: true)
    }

    private func removeCustomTag(_ tag: String, document: String) async throws {
        if FeatureFlags.disableFirebase {
            return
        }

        try await configuration.userDocumentReference
            .collection("preferences")
            .document(document)
            .setData(["tags": FieldValue.arrayRemove([tag])], merge: true)
    }
}
