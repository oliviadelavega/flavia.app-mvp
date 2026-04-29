//
// Flavia study app
//
// Persists environment snapshots to Firestore. Each refresh writes a
// timestamped document into the user's `environment` history collection
// and mirrors the same payload into `environment/current` so other parts
// of the app can read the latest reading without scanning history.
//

@preconcurrency import FirebaseFirestore
import Foundation
import Spezi


/// Standard constraint declared by the environment subsystem so `EnvironmentRefresh`
/// can resolve the Standard via `@StandardActor` without leaking the concrete type.
protocol EnvironmentSnapshotConstraint: Standard {
    func storeEnvironmentSnapshot(_ snapshot: EnvironmentSnapshot) async throws
}


extension TemplateApplicationStandard: EnvironmentSnapshotConstraint {
    func storeEnvironmentSnapshot(_ snapshot: EnvironmentSnapshot) async throws {
        if FeatureFlags.disableFirebase {
            logger.debug("Firebase disabled — skipping environment snapshot save")
            return
        }

        let collection = try await configuration.userDocumentReference.collection("environment")
        let documentID = EnvironmentSnapshotID.documentID(for: snapshot.capturedAt)

        try await collection.document(documentID).setData(from: snapshot, merge: true)
        try await collection.document("current").setData(from: snapshot, merge: true)
    }
}
