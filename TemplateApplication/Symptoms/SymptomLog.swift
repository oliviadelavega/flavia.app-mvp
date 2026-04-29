//
// Flavia study app
//
// Daily symptom check-in model. One row per (user, date), upserted to
// Firestore at users/{uid}/symptomLogs/{YYYY-MM-DD}. Mirrors the
// `manual_log` table in the MVP_Flavia reference web app.
//

import FirebaseFirestore
import Foundation


struct SymptomLog: Codable, Equatable, Sendable {
    /// 0 = clear, 5 = severe
    var eczemaSeverity: Int?
    /// 0 = none, 5 = unbearable
    var itchLevel: Int?
    /// 0 = calm, 5 = overwhelmed
    var stressLevel: Int?
    /// nil = unanswered, true/false = explicit yes/no
    var onPeriod: Bool?
    var bodyPartsAffected: [String]
    var topicalsUsed: [String]
    var notes: String?

    /// Last-write timestamp, set by the Firestore server on every save.
    @ServerTimestamp var updatedAt: Timestamp?

    init(
        eczemaSeverity: Int? = nil,
        itchLevel: Int? = nil,
        stressLevel: Int? = nil,
        onPeriod: Bool? = nil,
        bodyPartsAffected: [String] = [],
        topicalsUsed: [String] = [],
        notes: String? = nil
    ) {
        self.eczemaSeverity = eczemaSeverity
        self.itchLevel = itchLevel
        self.stressLevel = stressLevel
        self.onPeriod = onPeriod
        self.bodyPartsAffected = bodyPartsAffected
        self.topicalsUsed = topicalsUsed
        self.notes = notes
    }
}


enum SymptomVocabulary {
    static let bodyParts: [String] = [
        "hands", "wrists", "inner_elbows", "behind_knees",
        "face", "eyelids", "neck", "scalp",
        "torso", "back", "feet", "ankles"
    ]

    static let topicals: [String] = [
        "none", "moisturizer", "cortisone",
        "prescription_cream", "other"
    ]

    /// Human-readable label for a vocabulary token (`inner_elbows` → `inner elbows`).
    static func label(for token: String) -> String {
        token.replacingOccurrences(of: "_", with: " ")
    }
}


enum SymptomLogDate {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Stable YYYY-MM-DD identifier used as the Firestore document ID for a given calendar day.
    static func documentID(for date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    /// Inverse of ``documentID(for:)`` — parses a stored document ID back into a `Date`.
    static func date(from documentID: String) -> Date? {
        formatter.date(from: documentID)
    }
}
