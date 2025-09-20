import Foundation
import CoreLocation
import MapKit
import FirebaseFirestore
import FirebaseAuth
import SwiftUI

final class LocationMonitor: NSObject, ObservableObject {
    static let shared = LocationMonitor()

    // Public toggle (persisted)
    @AppStorage("riskAlertsEnabled_v1") var isEnabled: Bool = false {
        didSet { isEnabled ? start() : stop() }
    }

    // Pair context
    private var pairId: String?
    private var myUID: String?
    private var partnerUID: String?

    // Location
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    // Dwell tracking
    private struct VenueKey: Hashable { let id: String }
    private struct VenueState { var firstSeenAt: Date; var lastSeenAt: Date }
    private var states: [VenueKey: VenueState] = [:]

    // Search timer
    private var searchTimer: Timer?

    // Cooldown storage
    private let cooldownKeyPrefix = "venueCooldown_" // + id
    private let cooldownInterval: TimeInterval = 2 * 60 * 60 // 2 hours
    private let dwellThreshold: TimeInterval = 5 * 60 // 5 minutes

    private override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: - Public API

    func updatePairContext(pairId: String?, myUID: String?, partnerUID: String?) {
        self.pairId = pairId
        self.myUID = myUID
        self.partnerUID = partnerUID
        reevaluate()
    }

    func start() {
        guard isEnabled else { return }
        requestAuthorizationIfNeeded()
        startVisitsAndSignificantChanges()
        startSearchTimer()
    }

    func stop() {
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        stopSearchTimer()
        states.removeAll()
    }

    private func reevaluate() {
        if isEnabled && pairId != nil && partnerUID != nil { start() } else { stop() }
    }

    // MARK: - Authorization

    private func requestAuthorizationIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        case .authorizedWhenInUse, .denied, .restricted:
            // Try to upgrade to Always if possible (user may need to go to Settings)
            manager.requestAlwaysAuthorization()
        @unknown default:
            break
        }
    }

    // MARK: - Start/stop underlying services

    private func startVisitsAndSignificantChanges() {
        manager.startMonitoringVisits()
        manager.startMonitoringSignificantLocationChanges()
    }

    private func startSearchTimer() {
        stopSearchTimer()
        // Poll every 60s; rely on dwell accumulation to reach 5 minutes
        searchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.performNearbySearch()
        }
    }

    private func stopSearchTimer() {
        searchTimer?.invalidate()
        searchTimer = nil
    }

    // MARK: - Search and dwell logic

    private func performNearbySearch() {
        guard isEnabled, let location = lastLocation ?? manager.location else { return }
        guard partnerUID != nil, pairId != nil else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "bar OR casino"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 800, // ~0.5mi
            longitudinalMeters: 800
        )

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self else { return }
            guard error == nil, let items = response?.mapItems else { return }

            let now = Date()
            for item in items {
                guard let name = item.name else { continue }
                let coord = item.placemark.coordinate
                let distance = location.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                // Consider "at venue" if within 75 meters
                guard distance <= 75 else { continue }

                let id = self.venueIdentifier(name: name, coordinate: coord)
                let key = VenueKey(id: id)

                // Cooldown check
                if self.isInCooldown(id: id, now: now) { continue }

                if var st = self.states[key] {
                    st.lastSeenAt = now
                    self.states[key] = st
                    let dwell = st.lastSeenAt.timeIntervalSince(st.firstSeenAt)
                    if dwell >= self.dwellThreshold {
                        self.handleDwellReached(venueId: id, venueName: name, coordinate: coord, at: now)
                        self.setCooldown(id: id, at: now)
                        self.states.removeValue(forKey: key)
                    }
                } else {
                    self.states[key] = VenueState(firstSeenAt: now, lastSeenAt: now)
                }
            }

            // Cleanup stale states (no updates for > 10 minutes)
            self.states = self.states.filter { _, st in
                now.timeIntervalSince(st.lastSeenAt) < 10 * 60
            }
        }
    }

    private func venueIdentifier(name: String, coordinate: CLLocationCoordinate2D) -> String {
        let lat = String(format: "%.5f", coordinate.latitude)
        let lon = String(format: "%.5f", coordinate.longitude)
        return "\(name.lowercased())@\(lat),\(lon)"
    }

    private func isInCooldown(id: String, now: Date) -> Bool {
        let key = cooldownKeyPrefix + id
        if let ts = UserDefaults.standard.object(forKey: key) as? Date {
            return now.timeIntervalSince(ts) < cooldownInterval
        }
        return false
    }

    private func setCooldown(id: String, at: Date) {
        let key = cooldownKeyPrefix + id
        UserDefaults.standard.set(at, forKey: key)
    }

    // MARK: - Partner alert

    private func handleDwellReached(venueId: String, venueName: String, coordinate: CLLocationCoordinate2D, at: Date) {
        guard let pairId, let my = Auth.auth().currentUser?.uid, let partner = partnerUID else { return }
        let db = Firestore.firestore()
        let collection = db.collection("pairSpaces").document(pairId).collection("notifications")
        let payload: [String: Any] = [
            "toUid": partner,
            "fromUid": my,
            "pairId": pairId,
            "kind": "riskPlaceAlert",
            "title": "At a risky place",
            "body": "Your mate has been at \(venueName) for 5+ minutes.",
            "route": "home/alerts",
            "createdAt": FieldValue.serverTimestamp(),
            "unread": true,
            "meta": [
                "venueId": venueId,
                "venueName": venueName,
                "lat": coordinate.latitude,
                "lon": coordinate.longitude,
                "dwellMinutes": 5
            ]
        ]
        collection.addDocument(data: payload) { _ in }
    }
}

extension LocationMonitor: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            startVisitsAndSignificantChanges()
            startSearchTimer()
        default:
            stop()
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        lastLocation = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        performNearbySearch()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }
}
