//
// Flavia study app
//
// Wraps CLLocationManager so the rest of the app can `await provider.requestLocation()`
// without dealing with the delegate callback dance. Also drives the iOS
// significant-location-change service: once "Always" authorization is granted,
// the provider asks the system to wake the app whenever the user moves enough
// for environment readings to plausibly differ (~500m / ~5min) — including
// after the app has been force-quit. Foreground-only one-shot requests and
// background-driven significant updates share the same delegate, so the
// provider routes one-shot results to the awaiting continuation and unsolicited
// updates to `onSignificantChange` (set by `EnvironmentRefresh`).
//

import CoreLocation
import OSLog
import Spezi
import SwiftUI


@MainActor
@Observable
final class LocationProvider: NSObject, Module, EnvironmentAccessible, DefaultInitializable, CLLocationManagerDelegate {
    enum LocationError: Error {
        case authorizationDenied
        case underlying(Error)
        case timeout
        case unavailable
    }

    @ObservationIgnored private let logger = Logger(subsystem: "com.flavia.app", category: "LocationProvider")
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var pending: [CheckedContinuation<CLLocation, Error>] = []
    @ObservationIgnored private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    @ObservationIgnored private var monitoringSignificantChanges = false

    /// Invoked when the system delivers a location update that wasn't requested by `requestLocation()` —
    /// i.e., a background significant-change update. `EnvironmentRefresh` wires this in `configure()`.
    @ObservationIgnored var onSignificantChange: (@MainActor (CLLocation) -> Void)?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastLocation: CLLocation?

    nonisolated override init() {
        super.init()
    }

    func configure() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
        // If the app was relaunched in the background after a significant change, monitoring
        // is already implicitly active on the system side — but re-asserting it is cheap and
        // ensures we keep receiving updates after foreground restarts too.
        if authorizationStatus == .authorizedAlways {
            startSignificantLocationMonitoring()
        }
    }

    /// Triggers the system "While In Use" permission prompt and awaits the user's decision.
    @discardableResult
    func requestAuthorization() async -> CLAuthorizationStatus {
        if authorizationStatus != .notDetermined {
            return authorizationStatus
        }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Triggers the system "Always" permission prompt and awaits the user's decision. iOS will
    /// either show the initial three-option prompt (Allow Always / While Using / Don't Allow)
    /// when status is `.notDetermined`, or the upgrade prompt when status is `.authorizedWhenInUse`.
    @discardableResult
    func requestAlwaysAuthorization() async -> CLAuthorizationStatus {
        if authorizationStatus == .authorizedAlways {
            return .authorizedAlways
        }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            manager.requestAlwaysAuthorization()
        }
    }

    /// Returns the current device location. Throws if the user has denied permission.
    func requestLocation() async throws -> CLLocation {
        switch authorizationStatus {
        case .notDetermined:
            _ = await requestAuthorization()
            return try await requestLocation()
        case .denied, .restricted:
            throw LocationError.authorizationDenied
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            throw LocationError.unavailable
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            pending.append(continuation)
            manager.requestLocation()
        }
    }

    /// Subscribes to iOS significant-change notifications. Idempotent. Requires "Always" auth —
    /// iOS silently ignores the call otherwise. Once active, the system will relaunch the app in
    /// the background to deliver updates even after force-quit.
    func startSignificantLocationMonitoring() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            logger.notice("Significant-change monitoring not available on this device")
            return
        }
        guard !monitoringSignificantChanges else {
            return
        }
        manager.startMonitoringSignificantLocationChanges()
        monitoringSignificantChanges = true
        logger.info("Started significant-change location monitoring")
    }

    func stopSignificantLocationMonitoring() {
        guard monitoringSignificantChanges else {
            return
        }
        manager.stopMonitoringSignificantLocationChanges()
        monitoringSignificantChanges = false
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            let waiters = self.authorizationContinuations
            self.authorizationContinuations.removeAll()
            for waiter in waiters {
                waiter.resume(returning: status)
            }
            switch status {
            case .authorizedAlways:
                self.startSignificantLocationMonitoring()
            case .denied, .restricted:
                self.stopSignificantLocationMonitoring()
                let pending = self.pending
                self.pending.removeAll()
                for continuation in pending {
                    continuation.resume(throwing: LocationError.authorizationDenied)
                }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }
        Task { @MainActor in
            self.lastLocation = location
            let waiters = self.pending
            self.pending.removeAll()
            if waiters.isEmpty {
                // Unsolicited update — must be from significant-change monitoring.
                self.onSignificantChange?(location)
            } else {
                for continuation in waiters {
                    continuation.resume(returning: location)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.logger.error("CLLocationManager failed: \(error.localizedDescription)")
            let waiters = self.pending
            self.pending.removeAll()
            for continuation in waiters {
                continuation.resume(throwing: LocationError.underlying(error))
            }
        }
    }
}
