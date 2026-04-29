//
// Flavia study app
//
// Combined record of where the user was and what UV / air-quality / pollen
// readings Open-Meteo reported for that location at the time of capture.
// One snapshot is persisted per refresh under
// `users/{uid}/environment/{YYYY-MM-DD-HHmm}` (history) and the latest
// reading is mirrored into `users/{uid}/environment/current`.
//

import FirebaseFirestore
import Foundation


struct EnvironmentLocation: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// Horizontal accuracy reported by Core Location, in meters.
    var accuracyMeters: Double?
    /// IANA timezone identifier returned by Open-Meteo for the coordinate.
    var timezone: String?
    /// `CLLocation.timestamp` — when the device measured this position. Differs from
    /// `EnvironmentSnapshot.capturedAt` for background significant-change updates that
    /// can sit briefly in the system queue before the app processes them.
    var recordedAt: Date
}


struct EnvironmentUV: Codable, Equatable, Sendable {
    var current: Double?
    var clearSky: Double?
    var dailyMax: Double?
}


/// Ambient outdoor weather pulled from Open-Meteo's forecast endpoint at the same
/// coordinate the UV reading came from. Temperature is the dry-bulb air temperature
/// at 2 m above ground; `apparent` is the "feels like" temperature (wind chill /
/// heat index folded in).
struct EnvironmentWeather: Codable, Equatable, Sendable {
    var temperatureCelsius: Double?
    var apparentTemperatureCelsius: Double?
    var relativeHumidityPercent: Double?
    var precipitationMillimeters: Double?
}


struct EnvironmentAirQuality: Codable, Equatable, Sendable {
    var europeanAQI: Double?
    var usAQI: Double?
    var pm10: Double?
    var pm25: Double?
    var carbonMonoxide: Double?
    var nitrogenDioxide: Double?
    var sulphurDioxide: Double?
    var ozone: Double?
}


/// Open-Meteo only reports pollen counts for European stations; expect nils outside that region.
struct EnvironmentPollen: Codable, Equatable, Sendable {
    var alder: Double?
    var birch: Double?
    var grass: Double?
    var mugwort: Double?
    var olive: Double?
    var ragweed: Double?
}


struct EnvironmentSnapshot: Codable, Equatable, Sendable {
    var location: EnvironmentLocation
    var weather: EnvironmentWeather
    var uvLevels: EnvironmentUV
    var airQuality: EnvironmentAirQuality
    var pollen: EnvironmentPollen
    /// Wall-clock time the device captured the snapshot.
    var capturedAt: Date
    /// Server-applied write time, used for ordering history reads.
    @ServerTimestamp var updatedAt: Timestamp?
}


enum EnvironmentSnapshotID {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

    /// Stable UTC-based identifier used as the Firestore document ID for a captured snapshot.
    static func documentID(for date: Date = Date()) -> String {
        formatter.string(from: date)
    }
}
