import Foundation
import CoreLocation

/// Keeps Skylog awake in the background on travel days (coarse location) and wakes it at airports (geofences),
/// so flight data is refreshed regularly without a server.
@MainActor
final class TravelMode: NSObject, CLLocationManagerDelegate {
    static let shared = TravelMode()

    private let manager = CLLocationManager()
    private(set) var active = false
    private var loop: Task<Void, Never>?

    static var enabled: Bool { UserDefaults.standard.object(forKey: "travelMode") as? Bool ?? true }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 1000
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .otherNavigation
    }

    /// Flights whose travel window is now: 3 h before departure until 1 h after arrival.
    private func flightsInWindow(_ store: FlightStore, now: Date = Date()) -> [Flight] {
        store.upcoming.filter { f in
            guard !f.normalizedStatus.isFinal || f.normalizedStatus == .arrived, let dep = f.departure.best else { return false }
            let arr = f.arrival.best ?? dep.addingTimeInterval(4 * 3600)
            return now > dep.addingTimeInterval(-3 * 3600) && now < arr.addingTimeInterval(3600)
        }
    }

    /// Call on app start, when coming to the foreground and after flight changes.
    func evaluate(_ store: FlightStore) {
        guard Self.enabled else { stop(); return }
        updateGeofences(store)
        let inWindow = !flightsInWindow(store).isEmpty
        // Ask for permission in good time (the day before / on the travel day)
        let soon = store.upcoming.contains { ($0.departure.best ?? .distantFuture).timeIntervalSinceNow < 30 * 3600 }
        if soon && manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        if soon && manager.authorizationStatus == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
        inWindow ? start(store) : stop()
    }

    private func start(_ store: FlightStore) {
        guard !active else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        active = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await store.refreshActive(notify: true)
                await store.updateLivePositions()
                guard let self, !self.flightsInWindow(store).isEmpty else { break }
                try? await Task.sleep(for: .seconds(180))
            }
            self?.stop()
        }
    }

    func stop() {
        guard active else { return }
        active = false
        loop?.cancel()
        loop = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: Airport geofences

    private func updateGeofences(_ store: FlightStore) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              manager.authorizationStatus == .authorizedAlways else { return }
        for region in manager.monitoredRegions where region.identifier.hasPrefix("airport-") { manager.stopMonitoring(for: region) }
        let next = store.upcoming.filter { ($0.departure.best ?? .distantFuture).timeIntervalSinceNow < 48 * 3600 }.prefix(5)
        var codes: [String: CLLocationCoordinate2D] = [:]
        for f in next {
            if let c = f.departure.coordinate { codes[f.departure.code] = c }
            if let c = f.arrival.coordinate { codes[f.arrival.code] = c }
        }
        for (code, coord) in codes.prefix(18) {
            let region = CLCircularRegion(center: coord, radius: 3000, identifier: "airport-\(code)")
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    // MARK: Delegate

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            let store = FlightStore.shared
            await store.refreshActive(force: true, notify: true)
            await store.updateLivePositions()
            self.evaluate(store)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.evaluate(FlightStore.shared) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
