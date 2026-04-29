//
// Flavia study app
//
// Coordinates the location → Open-Meteo → Firestore pipeline. Two entry
// points feed it:
//   - foreground sign-in / view appearance (`refresh()`), throttled by a
//     10-minute cooldown so cold launches don't double-up;
//   - background significant-change events from `LocationProvider`,
//     wired in `configure()`. iOS relaunches the app silently when the
//     device moves enough for env readings to plausibly change, the
//     callback fires, and we capture a fresh snapshot — even if the
//     user never opened the app.
//
// The Standard is resolved via `@StandardActor` (`EnvironmentSnapshotConstraint`)
// so background-triggered refreshes don't depend on a view scope being alive.
//

import CoreLocation
import OSLog
import Spezi
import SwiftUI


@MainActor
@Observable
final class EnvironmentRefresh: Module, EnvironmentAccessible, DefaultInitializable {
    @ObservationIgnored @Dependency(LocationProvider.self) private var locationProvider
    @ObservationIgnored @StandardActor private var standard: any EnvironmentSnapshotConstraint

    @ObservationIgnored private let client = OpenMeteoClient()
    @ObservationIgnored private let logger = Logger(subsystem: "com.flavia.app", category: "EnvironmentRefresh")

    /// Don't refresh more than once every 10 minutes within an app process.
    /// Background-driven refreshes from significant-change events bypass this only
    /// when iOS itself decided the move was significant — see `respondToSignificantChange`.
    private static let cooldown: TimeInterval = 10 * 60

    /// Significant-change updates closer together than this are dropped — a guard against
    /// CLLocationManager occasionally delivering rapid duplicates after an app relaunch.
    private static let significantChangeMinInterval: TimeInterval = 60

    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var lastError: Error?
    private(set) var lastSnapshot: EnvironmentSnapshot?

    nonisolated init() {}

    func configure() {
        locationProvider.onSignificantChange = { [weak self] location in
            guard let self else {
                return
            }
            Task { [weak self] in
                await self?.respondToSignificantChange(location)
            }
        }
    }

    /// Foreground entry point — captures location, fetches Open-Meteo, persists a snapshot.
    /// Throttled by ``cooldown`` unless `force` is true (e.g. immediately after the user
    /// granted location permission during onboarding).
    func refresh(force: Bool = false) async {
        if FeatureFlags.disableFirebase {
            logger.debug("Firebase disabled — skipping environment refresh")
            return
        }
        if isRefreshing {
            return
        }
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < Self.cooldown {
            return
        }

        do {
            let location = try await locationProvider.requestLocation()
            try await capture(at: location)
        } catch LocationProvider.LocationError.authorizationDenied {
            lastError = LocationProvider.LocationError.authorizationDenied
            logger.notice("Location permission denied — skipping environment refresh")
        } catch {
            lastError = error
            logger.error("Environment refresh failed: \(error.localizedDescription)")
        }
    }

    /// Background entry point — invoked by `LocationProvider` when iOS delivers a
    /// significant-change update. The 10-minute cooldown does *not* apply here because
    /// the system already decided the user moved enough to matter; we use a much
    /// shorter floor just to drop accidental duplicates.
    private func respondToSignificantChange(_ location: CLLocation) async {
        if FeatureFlags.disableFirebase {
            return
        }
        if isRefreshing {
            return
        }
        if let last = lastRefresh, Date().timeIntervalSince(last) < Self.significantChangeMinInterval {
            return
        }
        logger.info("Handling significant location change at (\(location.coordinate.latitude), \(location.coordinate.longitude))")
        do {
            try await capture(at: location)
        } catch LocationProvider.LocationError.authorizationDenied {
            lastError = LocationProvider.LocationError.authorizationDenied
        } catch {
            lastError = error
            logger.error("Background environment refresh failed: \(error.localizedDescription)")
        }
    }

    private func capture(at location: CLLocation) async throws {
        isRefreshing = true
        defer { isRefreshing = false }

        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let accuracy = location.horizontalAccuracy
        let recordedAt = location.timestamp

        let snapshot = try await client.fetchSnapshot(
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracy,
            recordedAt: recordedAt
        )
        try await standard.storeEnvironmentSnapshot(snapshot)
        lastSnapshot = snapshot
        lastRefresh = Date()
        lastError = nil
        logger.info("Stored environment snapshot for (\(latitude), \(longitude))")
    }
}
