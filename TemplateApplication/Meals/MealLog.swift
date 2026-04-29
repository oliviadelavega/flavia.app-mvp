//
// Flavia study app
//
// Meal entry model. One Firestore doc per meal under
// users/{uid}/meals/{autoId}. Mirrors the `food_log` table in the
// MVP_Flavia reference web app.
//

import FirebaseFirestore
import Foundation


struct MealLog: Codable, Equatable, Sendable {
    var description: String?
    var tags: [String]
    var loggedAt: Date

    /// Set by the Firestore server on insert. Used for ordering when
    /// `loggedAt` collides (e.g. two meals saved at the same minute).
    @ServerTimestamp var createdAt: Timestamp?


    init(
        description: String? = nil,
        tags: [String] = [],
        loggedAt: Date = Date()
    ) {
        self.description = description
        self.tags = tags
        self.loggedAt = loggedAt
    }
}


enum MealVocabulary {
    /// Common eczema-relevant food tags. Free-form add-ons can come later.
    static let tags: [String] = [
        "dairy", "gluten", "egg", "nut",
        "soy", "seafood", "spicy", "processed",
        "sugar", "alcohol", "vegetables", "fruits"
    ]
}
