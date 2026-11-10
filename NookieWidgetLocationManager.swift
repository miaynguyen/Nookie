import Foundation
import CoreLocation
import WidgetKit
import Combine
import FirebaseFirestore
import UserNotifications

/// Foreground proximity gate. This does not claim to provide background geofencing.
final class NookieWidgetLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NookieWidgetLocationManager()
    private let manager = CLLocationManager()
    private let appGroup = "group.nookie"
    private let maximumFixAge: TimeInterval = 30
    // Foreground voting always requires a recent accurate fix.
    // The widget display does not have an arbitrary five-minute timeout.
    private let maximumAccuracy: CLLocationAccuracy = 25
    private let votingRadius: CLLocationDistance = 60.96 // 200 feet

    @Published private(set) var nearbySpotID: String?
    @Published private(set) var locationStatus = "Checking your location…"
    private var spots: [CommunitySpot] = []
    private var lastFix: CLLocation?
    private var isActive = false
    private var regionListener: ListenerRegistration?
    private var allCommunitySpots: [CommunitySpot] = []
    private var backgroundEnabled = false
    private let regionRadius: CLLocationDistance = 200 // meters: early-warning geofence, NOT voting radius
    private let maximumRegions = 18
    private var lastNotifiedSpotID: String?
    @Published private(set) var lastLocationTime: Date?
    @Published private(set) var lastLocationAccuracy: Double?
    @Published private(set) var nearestDistanceFeet: Double?
    @Published private(set) var monitoredCafeCount = 0
    @Published private(set) var lastArrivalEvent = "No arrival event yet"
    @Published private(set) var lastLocationError = "None"
    var permissionDescription: String {
        switch manager.authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While Using"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        default: return "Not determined"
        }
    }
    var accuracyDescription: String {
        manager.accuracyAuthorization == .fullAccuracy ? "Precise" : "Approximate"
    }



    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = true
    }

    func start(spots: [CommunitySpot]) {
        self.spots = spots
        isActive = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedAlways ||
                    manager.authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        } else {
            locationStatus = "Enable location access to vote at nearby cafes."
            clearPrompt()
        }
        evaluate()
        configureRegions()
    }

    func updateSpots(_ spots: [CommunitySpot]) {
        self.spots = spots
        evaluate()
        configureRegions()
    }

    // Leaving the Map tab stops high-accuracy foreground updates, but does
    // not disable user-enabled background region monitoring.
    func stop() {
        isActive = false
        manager.stopUpdatingLocation()
        if !backgroundEnabled {
            lastFix = nil
            clearPrompt()
        }
    }

    /// Explicit opt-in. iOS may not grant Always authorization; no prompt is
    /// shown unless the user enables arrival alerts in their profile.
    func enableArrivalMonitoring() {
        backgroundEnabled = true
        UserDefaults.standard.set(true, forKey: "nookie.arrivalMonitoringEnabled")
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        beginCommunitySpotListener()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        requestFreshLocation()
    }

    func disableArrivalMonitoring() {
        backgroundEnabled = false
        UserDefaults.standard.set(false, forKey: "nookie.arrivalMonitoringEnabled")
        regionListener?.remove()
        regionListener = nil
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        lastNotifiedSpotID = nil
        manager.stopUpdatingLocation()
        clearPrompt()
    }

    func resumeArrivalMonitoringIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "nookie.arrivalMonitoringEnabled") else { return }
        backgroundEnabled = true
        beginCommunitySpotListener()
        // Recover when reopened or relaunched inside an existing monitored region.
        requestFreshLocation()
        for region in manager.monitoredRegions where region.identifier.hasPrefix("nookie.cafe.") {
            manager.requestState(for: region)
        }
        monitoredCafeCount = manager.monitoredRegions.filter { $0.identifier.hasPrefix("nookie.cafe.") }.count
    }

    /// Re-check a signed-in account even if the user was already inside a region.
    /// A fresh GPS fix is required; stale data from the prior account is never reused.
    func handleAccountLogin(uid: String?) {
        lastNotifiedSpotID = nil
        lastFix = nil
        nearbySpotID = nil
        guard let uid, !uid.isEmpty else {
            clearPrompt()
            return
        }
        guard UserDefaults.standard.bool(forKey: "nookie.arrivalMonitoringEnabled") else { return }
        backgroundEnabled = true
        beginCommunitySpotListener()
        requestFreshLocation()
        for region in manager.monitoredRegions where region.identifier.hasPrefix("nookie.cafe.") {
            manager.requestState(for: region)
        }
    }

    /// Called when Nookie becomes active; avoids waiting for a new boundary crossing.
    func recoverArrivalOnForeground() {
        guard backgroundEnabled else { return }
        requestFreshLocation()
        configureRegions()
    }

    private func beginCommunitySpotListener() {
        guard backgroundEnabled, regionListener == nil else { return }
        regionListener = Firestore.firestore().collection("spots")
            .limit(to: 250).addSnapshotListener { [weak self] snapshot, error in
                guard let self, error == nil else { return }
                let candidates = (snapshot?.documents ?? []).compactMap {
                    CommunitySpot.from(documentID: $0.documentID, data: $0.data())
                }
                DispatchQueue.main.async {
                    self.allCommunitySpots = candidates
                    self.configureRegions()
                    self.evaluate()
                }
            }
    }

    private func configureRegions() {
        guard backgroundEnabled,
              manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let origin = manager.location ?? lastFix
        guard let origin, origin.horizontalAccuracy >= 0 else { return }
        let closest = allCommunitySpots.sorted {
            origin.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) <
            origin.distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
        }.prefix(maximumRegions)
        let identifiers = Set(closest.map { "nookie.cafe.\($0.id)" })
        for region in manager.monitoredRegions where region.identifier.hasPrefix("nookie.cafe.") && !identifiers.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        monitoredCafeCount = manager.monitoredRegions.filter { $0.identifier.hasPrefix("nookie.cafe.") }.count
        let existing = Set(manager.monitoredRegions.map(\.identifier))
        for spot in closest where !existing.contains("nookie.cafe.\(spot.id)") {
            let region = CLCircularRegion(center: spot.coordinate,
                radius: min(regionRadius, manager.maximumRegionMonitoringDistance),
                identifier: "nookie.cafe.\(spot.id)")
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
            manager.requestState(for: region)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard backgroundEnabled, region.identifier.hasPrefix("nookie.cafe.") else { return }
        // Region entry is a coarse hint, never proof of voting eligibility.
        // Ask for an accurate fix and update the widget only if verification succeeds.
        lastArrivalEvent = "Entered region at \(Date().formatted(date: .abbreviated, time: .standard))"
        requestFreshLocation()
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard backgroundEnabled, region.identifier.hasPrefix("nookie.cafe.") else { return }
        if state == .inside {
            lastArrivalEvent = "Inside monitored region at \(Date().formatted(date: .abbreviated, time: .standard))"
            requestFreshLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier.hasPrefix("nookie.cafe.") else { return }
        // Do not dismiss a different nearby cafe's prompt.
        let exitingSpotID = String(region.identifier.dropFirst("nookie.cafe.".count))
        if nearbySpotID == exitingSpotID {
            clearPrompt()
        }
        lastArrivalEvent = "Exited region at \(Date().formatted(date: .abbreviated, time: .standard))"
        requestFreshLocation()
    }


    /// Checks a recent accurate fix, not merely the last widget state.
    func isEligible(for spotID: String) -> Bool {
        guard isActive, let fix = lastFix,
              fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= maximumAccuracy,
              abs(fix.timestamp.timeIntervalSinceNow) <= maximumFixAge,
              let spot = spots.first(where: { $0.id == spotID }) else { return false }
        let target = CLLocation(latitude: spot.coordinate.latitude,
                                longitude: spot.coordinate.longitude)
        // Conservative: accuracy circle must fit within the requested radius.
        return fix.distance(from: target) + fix.horizontalAccuracy <= votingRadius
    }

    func refreshEligibility() {
        evaluate()
    }

    func requestFreshLocation() {
        guard manager.authorizationStatus == .authorizedAlways ||
              manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestLocation()
    }

    private func evaluate() {
        guard (isActive || backgroundEnabled), let fix = lastFix,
              fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= maximumAccuracy,
              abs(fix.timestamp.timeIntervalSinceNow) <= maximumFixAge else {
            locationStatus = "Waiting for a recent, accurate location fix."
            // Background location updates are intermittent. Preserve the last
            // verified arrival display until a departure or newer location
            // observation; do not treat a 30-second-old fix as departure.
            // This does NOT authorize voting: isEligible(for:) still requires
            // a fresh, accurate fix before the main app submits anything.
            if !backgroundEnabled || lastFix == nil { clearPrompt() }
            return
        }
        let candidates = backgroundEnabled ? allCommunitySpots : spots
        nearestDistanceFeet = candidates.map {
            fix.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) * 3.28084
        }.min()
        let nearest = candidates.filter { spot in
            let target = CLLocation(latitude: spot.coordinate.latitude,
                                    longitude: spot.coordinate.longitude)
            return fix.distance(from: target) + fix.horizontalAccuracy <= votingRadius
        }.min { lhs, rhs in
            fix.distance(from: CLLocation(latitude: lhs.coordinate.latitude, longitude: lhs.coordinate.longitude)) <
            fix.distance(from: CLLocation(latitude: rhs.coordinate.latitude, longitude: rhs.coordinate.longitude))
        }
        nearbySpotID = nearest?.id
        locationStatus = nearest == nil ? "Move within 200 ft of a cafe to vote." : "Nearby cafe verified."
        guard let shared = UserDefaults(suiteName: appGroup) else { return }
        // The widget must use the verified nearby cafe, not whichever cafe
        // happened to be opened most recently in the Map screen.
        guard let nearest else { clearPrompt(); return }
        let changed = shared.string(forKey: "widget.lastViewedSpotID") != nearest.id
        shared.set(nearest.id, forKey: "widget.lastViewedSpotID")
        shared.set(nearest.name, forKey: "widget.lastViewedCafe")
        if changed {
            shared.set(Array(repeating: 0, count: 24), forKey: "widget.hourlyLevels")
            loadWidgetReports(for: nearest.id)
        }
        let now = Date()
        let cooldownActive = shared.string(forKey: "widget.cooldownSpotID") == nearest.id &&
            ((shared.object(forKey: "widget.cooldownUntil") as? Date) ?? .distantPast) > now
        let show = !cooldownActive
        let previousShow = shared.bool(forKey: "widget.showCrowdPrompt")
        shared.removeObject(forKey: "widget.proximityExpiresAt")
        shared.set(now, forKey: "widget.lastProximityVerifiedAt")
        shared.set(show, forKey: "widget.showCrowdPrompt")
        if show && (changed || !previousShow) && lastNotifiedSpotID != nearest.id {
            lastNotifiedSpotID = nearest.id
            notifyArrival(at: nearest.name)
        }
        // Avoid excessive refresh requests on every GPS update.
        if changed || previousShow != show {
            WidgetCenter.shared.reloadTimelines(ofKind: "NookieWidget")
        }
    }


    private func notifyArrival(at cafeName: String) {
        guard backgroundEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "You're near \(cafeName)!"
        content.body = "How crowded is it? Share seat availability and earn 5 coins."
        content.sound = .default
        content.userInfo = ["nookieArrival": true]
        let request = UNNotificationRequest(identifier: "nookie.arrival.\(cafeName)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // One-time refresh: no fabricated crowd levels. The existing map listener
    // remains the authoritative source while the map card is open.
    private func loadWidgetReports(for spotID: String) {
        Firestore.firestore().collection("spots").document(spotID)
            .collection("busyReports")
            .order(by: "createdAt", descending: true).limit(to: 200)
            .getDocuments { snapshot, error in
                guard error == nil, let snapshot,
                      let shared = UserDefaults(suiteName: self.appGroup),
                      shared.string(forKey: "widget.lastViewedSpotID") == spotID else { return }
                let now = Date()
                let calendar = Calendar.current
                let records: [(Int, Date)] = snapshot.documents.compactMap { doc in
                    guard let level = doc.data()["value"] as? Int,
                          (1...5).contains(level),
                          let timestamp = doc.data()["createdAt"] as? FirebaseFirestore.Timestamp
                    else { return nil }
                    return (level, timestamp.dateValue())
                }
                let levels = (0..<24).map { hour -> Int in
                    let values = records.filter {
                        calendar.isDate($0.1, inSameDayAs: now) &&
                        calendar.component(.hour, from: $0.1) == hour
                    }.map { $0.0 }
                    guard !values.isEmpty else { return 0 }
                    return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
                }
                shared.set(levels, forKey: "widget.hourlyLevels")
                WidgetCenter.shared.reloadTimelines(ofKind: "NookieWidget")
            }
    }

    private func clearPrompt() {
        nearbySpotID = nil
        lastNotifiedSpotID = nil
        if let shared = UserDefaults(suiteName: appGroup),
           shared.bool(forKey: "widget.showCrowdPrompt") {
            shared.set(false, forKey: "widget.showCrowdPrompt")
            shared.removeObject(forKey: "widget.proximityExpiresAt")
            shared.removeObject(forKey: "widget.lastProximityVerifiedAt")
            shared.removeObject(forKey: "widget.pendingVote")
            WidgetCenter.shared.reloadTimelines(ofKind: "NookieWidget")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if backgroundEnabled {
            if manager.authorizationStatus == .authorizedWhenInUse {
                // Ask only after the user explicitly enabled the feature.
                manager.requestAlwaysAuthorization()
            }
            configureRegions()
        }
        guard isActive || backgroundEnabled else { return }
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            if isActive { manager.startUpdatingLocation() }
            else { requestFreshLocation() }
        } else {
            lastFix = nil
            clearPrompt()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        // Background region events only request a one-shot fix; don't run GPS continuously.
        if !isActive { manager.stopUpdatingLocation() }
        DispatchQueue.main.async {
            self.lastFix = latest
            self.lastLocationTime = latest.timestamp
            self.lastLocationAccuracy = latest.horizontalAccuracy
            self.lastLocationError = "None"
            if self.isActive || self.backgroundEnabled { self.evaluate() }
            self.configureRegions()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.locationStatus = "Location unavailable: \(error.localizedDescription)"
            self.lastLocationError = error.localizedDescription
            self.lastFix = nil
            self.clearPrompt()
        }
    }
}
