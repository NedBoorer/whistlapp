import Foundation
import CoreLocation
import MapKit
import FirebaseFirestore
import FirebaseAuth
import SwiftUI
import Observation

@MainActor
@Observable
final class LocationMonitor: NSObject {
    static let shared = LocationMonitor()

    // Public toggle (persisted)
    private let isEnabledDefaultsKey = "riskAlertsEnabled_v1"
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: isEnabledDefaultsKey) }
        set {
            let oldValue = UserDefaults.standard.bool(forKey: isEnabledDefaultsKey)
            guard oldValue != newValue else { return }
            UserDefaults.standard.set(newValue, forKey: isEnabledDefaultsKey)
            // Start/stop services based on the new value
            if newValue {
                start()
            } else {
                stop()
            }
        }
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
        // Ensure services reflect persisted toggle on init
        reevaluate()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 50 // Update when moved 50 meters
        
        // Only set background updates if we have permission
        if Bundle.main.object(forInfoDictionaryKey: "NSLocationAlwaysAndWhenInUseUsageDescription") != nil {
            if #available(iOS 9.0, *) {
                manager.allowsBackgroundLocationUpdates = true
            }
        }
        manager.pausesLocationUpdatesAutomatically = false // Keep active for monitoring
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
        guard pairId != nil && partnerUID != nil else {
            print("LocationMonitor: Cannot start - missing pair context")
            return
        }
        requestAuthorizationIfNeeded()
    }

    func stop() {
        manager.stopMonitoringVisits()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopUpdatingLocation()
        stopSearchTimer()
        states.removeAll()
    }

    private func reevaluate() {
        if isEnabled && pairId != nil && partnerUID != nil {
            start()
        } else {
            stop()
        }
    }

    // MARK: - Authorization

    private func requestAuthorizationIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startLocationServices()
        case .authorizedWhenInUse:
            // Try to upgrade to Always
            manager.requestAlwaysAuthorization()
        case .denied, .restricted:
            print("LocationMonitor: Location access denied or restricted")
            stop()
        @unknown default:
            print("LocationMonitor: Unknown authorization status")
        }
    }

    // MARK: - Start/stop underlying services

    private func startLocationServices() {
        guard manager.authorizationStatus == .authorizedAlways else { return }
        
        startVisitsAndSignificantChanges()
        startSearchTimer()
    }

    private func startVisitsAndSignificantChanges() {
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
        
        if CLLocationManager.isMonitoringAvailable(for: CLVisit.self) {
            manager.startMonitoringVisits()
        }
        
        // Also start regular location updates for more frequent checks
        manager.startUpdatingLocation()
    }

    private func startSearchTimer() {
        stopSearchTimer()
        // Poll every 60s; rely on dwell accumulation to reach 5 minutes
        searchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performNearbySearch()
            }
        }
    }

    private func stopSearchTimer() {
        searchTimer?.invalidate()
        searchTimer = nil
    }

    // MARK: - Search and dwell logic

    private func performNearbySearch() async {
        guard isEnabled, let location = lastLocation ?? manager.location else { return }
        guard partnerUID != nil, pairId != nil else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "bar OR casino OR pub OR nightclub OR gambling"
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 800, // ~0.5mi
            longitudinalMeters: 800
        )
        request.resultTypes = [.pointOfInterest]

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            await processSearchResults(items: response.mapItems, userLocation: location)
        } catch {
            print("LocationMonitor: Search failed - \(error.localizedDescription)")
        }
    }

    @MainActor
    private func processSearchResults(items: [MKMapItem], userLocation: CLLocation) {
        let now = Date()
        
        for item in items {
            guard let name = item.name else { continue }
            let coord = item.placemark.coordinate
            let venueLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = userLocation.distance(from: venueLocation)
            
            // Consider "at venue" if within 75 meters
            guard distance <= 75 else { continue }

            let id = venueIdentifier(name: name, coordinate: coord)
            let key = VenueKey(id: id)

            // Cooldown check
            if isInCooldown(id: id, now: now) { continue }

            if var existingState = states[key] {
                existingState.lastSeenAt = now
                states[key] = existingState
                let dwellTime = existingState.lastSeenAt.timeIntervalSince(existingState.firstSeenAt)
                
                if dwellTime >= dwellThreshold {
                    handleDwellReached(venueId: id, venueName: name, coordinate: coord, at: now)
                    setCooldown(id: id, at: now)
                    states.removeValue(forKey: key)
                }
            } else {
                states[key] = VenueState(firstSeenAt: now, lastSeenAt: now)
            }
        }

        // Cleanup stale states (no updates for > 10 minutes)
        states = states.compactMapValues { state in
            now.timeIntervalSince(state.lastSeenAt) < 10 * 60 ? state : nil
        }
    }

    private func venueIdentifier(name: String, coordinate: CLLocationCoordinate2D) -> String {
        let lat = String(format: "%.5f", coordinate.latitude)
        let lon = String(format: "%.5f", coordinate.longitude)
        return "\(name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))@\(lat),\(lon)"
    }

    private func isInCooldown(id: String, now: Date) -> Bool {
        let key = cooldownKeyPrefix + id
        guard let cooldownDate = UserDefaults.standard.object(forKey: key) as? Date else {
            return false
        }
        return now.timeIntervalSince(cooldownDate) < cooldownInterval
    }

    private func setCooldown(id: String, at: Date) {
        let key = cooldownKeyPrefix + id
        UserDefaults.standard.set(at, forKey: key)
    }

    // MARK: - Partner alert

    private func handleDwellReached(venueId: String, venueName: String, coordinate: CLLocationCoordinate2D, at: Date) {
        guard let pairId, let myUID = Auth.auth().currentUser?.uid, let partnerUID else {
            print("LocationMonitor: Missing required IDs for notification")
            return
        }
        
        Task {
            do {
                let db = Firestore.firestore()
                let collection = db.collection("pairSpaces").document(pairId).collection("notifications")
                let payload: [String: Any] = [
                    "toUid": partnerUID,
                    "fromUid": myUID,
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
                
                try await collection.addDocument(data: payload)
                print("LocationMonitor: Risk alert sent for \(venueName)")
            } catch {
                print("LocationMonitor: Failed to send notification - \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationMonitor: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            switch manager.authorizationStatus {
            case .authorizedAlways:
                self?.startLocationServices()
            case .authorizedWhenInUse:
                // Request Always authorization for background monitoring
                manager.requestAlwaysAuthorization()
            case .denied, .restricted:
                print("LocationMonitor: Authorization denied/restricted")
                self?.stop()
            case .notDetermined:
                manager.requestAlwaysAuthorization()
            @unknown default:
                print("LocationMonitor: Unknown authorization status")
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard visit.departureDate == Date.distantFuture else { return } // Only process arrivals
        
        lastLocation = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        
        Task { @MainActor in
            await performNearbySearch()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        
        // Only update if location is recent and accurate enough
        guard newLocation.timestamp.timeIntervalSinceNow > -30, // Within last 30 seconds
              newLocation.horizontalAccuracy < 100 else { return } // Accurate to within 100 meters
        
        lastLocation = newLocation
        
        // Trigger search if we don't have recent venue data
        if states.isEmpty {
            Task { @MainActor in
                await performNearbySearch()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationMonitor: Location manager failed with error: \(error.localizedDescription)")
    }
}
