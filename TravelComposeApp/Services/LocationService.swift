import CoreLocation
import Foundation
// `@preconcurrency` because `MKLocalSearch.Response` is only marked
// `Sendable` in the iOS 26 SDK; on older SDKs (e.g. the Xcode 16 GitHub
// runner) the strict-concurrency checker rejects `await … .start()`.
@preconcurrency import MapKit

struct ResolvedCoordinate {
    let lat: Double
    let lng: Double
    let clusterId: String
}

@MainActor
final class VoygoLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = VoygoLocationService()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var locationTimeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func requestPermissionIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func lastKnownCoordinate() async -> CLLocationCoordinate2D? {
        requestPermissionIfNeeded()
        if let location = manager.location {
            return location.coordinate
        }
        return nil
    }

    func requestCurrentCoordinate(timeout: TimeInterval = 12) async throws -> CLLocationCoordinate2D {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            throw CLError(.denied)
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }

        if let location = manager.location,
           location.horizontalAccuracy > 0,
           location.horizontalAccuracy <= 80,
           abs(location.timestamp.timeIntervalSinceNow) < 90 {
            return location.coordinate
        }

        locationContinuation?.resume(throwing: CLError(.locationUnknown))
        locationTimeoutTask?.cancel()

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
            locationTimeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    guard let self, let continuation = self.locationContinuation else { return }
                    self.locationContinuation = nil
                    continuation.resume(throwing: CLError(.locationUnknown))
                }
            }
        }
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String? {
        guard let placemark = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        ).first else {
            return nil
        }

        let parts = [
            placemark.name,
            placemark.subLocality,
            placemark.locality
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        var uniqueParts: [String] = []
        for part in parts where !uniqueParts.contains(part) {
            uniqueParts.append(part)
        }

        return uniqueParts.isEmpty ? nil : uniqueParts.joined(separator: ", ")
    }

    /// Searches places by free-text query. Tries the backend autocomplete
    /// first (Nominatim under the hood — has good street-address coverage
    /// once auth is real), and falls back to MKLocalSearch when the backend
    /// returns empty or fails. The fallback is what makes search work in the
    /// dev shortcut (no auth) and on a fresh install before the rider has
    /// signed in.
    func searchPlaces(query: String, near coordinate: CLLocationCoordinate2D? = nil, limit: Int = 8) async throws -> [PlaceSuggestion] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else { return [] }

        // 1) API first
        if let api = try? await VoygoAPIClient.autocompletePlaces(
            query: cleaned,
            lat: coordinate?.latitude,
            lon: coordinate?.longitude
        ), !api.isEmpty {
            return Array(api.prefix(limit))
        }

        // 2) MKLocalSearch fallback. Bias the search region to the caller's
        // anchor coordinate when present; otherwise default to Komtar
        // (central Penang) — the pilot region — so first-launch
        // autocomplete returns sensible Penang results.
        return try await mapKitSearch(query: cleaned, near: coordinate, limit: limit)
    }

    /// Pickup vs drop suggestion intent. Drives query selection
    /// (transit/malls for pickups, offices/hospitals/schools for
    /// drops) AND anchor sampling (drops never sample the corridor
    /// midpoint — a rider going to KLCC wants to be dropped at
    /// KLCC, not at a mall halfway there).
    enum SuggestionPurpose {
        case pickup
        case drop
    }

    /// Penang commute hubs — Voygo's pilot region is Penang, so these
    /// are the meet-points drivers and riders actually use day-to-day.
    /// Mix of the central Georgetown transit hubs, the Bayan Lepas
    /// industrial cluster (where the bulk of the commute flow goes),
    /// and the two big mainland-side gateways (Penang Sentral,
    /// Sunway Carnival).
    static let popularLocalHubs: [PlaceSuggestion] = [
        PlaceSuggestion(displayName: "Komtar",                 lat: 5.4148, lon: 100.3299),
        PlaceSuggestion(displayName: "Gurney Plaza",           lat: 5.4382, lon: 100.3094),
        PlaceSuggestion(displayName: "Queensbay Mall",         lat: 5.3318, lon: 100.3068),
        PlaceSuggestion(displayName: "Penang Sentral",         lat: 5.4014, lon: 100.3623),
        PlaceSuggestion(displayName: "USM",                    lat: 5.3556, lon: 100.3015),
        PlaceSuggestion(displayName: "Penang International Airport", lat: 5.2974, lon: 100.2734),
        PlaceSuggestion(displayName: "Bayan Lepas FIZ",        lat: 5.3267, lon: 100.2787),
        PlaceSuggestion(displayName: "Sunway Carnival Mall",   lat: 5.3925, lon: 100.4017)
    ]

    /// Penang commute DESTINATIONS — where riders are heading to,
    /// not where they wait. Skewed toward workplaces, schools and
    /// healthcare — the actual reasons people commute. Hubs that
    /// double as destinations (Komtar, Penang Sentral) stay; ones
    /// that are mainly meeting points (Gurney Plaza shop-front,
    /// Sunway Carnival Mall) come out.
    static let popularLocalDestinations: [PlaceSuggestion] = [
        PlaceSuggestion(displayName: "Bayan Lepas FIZ",        lat: 5.3267, lon: 100.2787),
        PlaceSuggestion(displayName: "Komtar",                 lat: 5.4148, lon: 100.3299),
        PlaceSuggestion(displayName: "USM",                    lat: 5.3556, lon: 100.3015),
        PlaceSuggestion(displayName: "Penang General Hospital", lat: 5.4197, lon: 100.3083),
        PlaceSuggestion(displayName: "Island Hospital",        lat: 5.4216, lon: 100.3138),
        PlaceSuggestion(displayName: "Penang International Airport", lat: 5.2974, lon: 100.2734),
        PlaceSuggestion(displayName: "Penang Sentral",         lat: 5.4014, lon: 100.3623),
        PlaceSuggestion(displayName: "Queensbay Mall",         lat: 5.3318, lon: 100.3068)
    ]

    /// Suggests pickup OR drop candidates near a coordinate. The
    /// `purpose` parameter determines:
    ///   - which MapKit query categories to search (pickup = transit
    ///     hubs + malls; drop = offices, hospitals, schools, malls)
    ///   - whether to sample the corridor midpoint (pickups yes —
    ///     "join along the way"; drops no — riders want to be dropped
    ///     AT their destination, not halfway there)
    ///
    /// Drives the "Suggested pickups" / "Suggested drops" pill rows
    /// on Create Route. Previously a single shared query set produced
    /// transit-hub results for both rails — meaning a driver creating
    /// a Subang→KLCC route saw "LRT Sentul" suggested as a drop point
    /// instead of "Petronas Tower". This split fixes that.
    func searchNearbyHubs(near coordinate: CLLocationCoordinate2D,
                          purpose: SuggestionPurpose = .pickup,
                          corridorAnchor: CLLocationCoordinate2D? = nil,
                          radiusMeters: Double = 5_000,
                          limit: Int = 8) async throws -> [PlaceSuggestion] {
        // Per-purpose query lists. Each phrase pulls a distinct
        // category MapKit indexes well in Malaysia.
        let queries: [String]
        switch purpose {
        case .pickup:
            // Where riders gather + wait. Transit nodes lead because
            // they're the most common pre-booked meeting point;
            // shopping malls double as casual landmarks
            // ("see you at AEON").
            queries = [
                "LRT station",
                "MRT station",
                "bus station",
                "KTM station",
                "shopping mall"
            ]
        case .drop:
            // Where riders ACTUALLY GO. Offices first (the dominant
            // commute drop), then schools/universities (school run),
            // hospitals (medical), business/industrial parks (the
            // Bayan Lepas / Cyberjaya pattern), then malls as a
            // fallback category for retail-cluster drops.
            queries = [
                "office",
                "office tower",
                "business park",
                "industrial park",
                "university",
                "hospital",
                "school",
                "shopping mall"
            ]
        }

        // Anchor sampling rule:
        //   - Pickups SHOULD sample the corridor midpoint so a rider
        //     halfway along the route can be picked up at a hub
        //     between the driver's start and destination.
        //   - Drops should NOT — the destination is the whole point;
        //     a "drop at the midpoint" mall is a worse suggestion
        //     than just the destination's nearby office tower.
        var anchors: [CLLocationCoordinate2D] = [coordinate]
        if purpose == .pickup, let other = corridorAnchor {
            let mid = CLLocationCoordinate2D(
                latitude:  (coordinate.latitude  + other.latitude)  / 2.0,
                longitude: (coordinate.longitude + other.longitude) / 2.0
            )
            anchors.append(mid)
        }
        // Tighter radius for drops — workplaces clustered around a
        // destination are usually within 2-3km. Wider radius for
        // pickups (catch transit hubs that feed into the corridor).
        let perAnchorRadius: Double
        switch purpose {
        case .pickup: perAnchorRadius = corridorAnchor == nil ? radiusMeters : max(radiusMeters, 7_000)
        case .drop:   perAnchorRadius = min(radiusMeters, 3_500)
        }

        var seen: Set<String> = []
        var results: [PlaceSuggestion] = []
        outer: for anchor in anchors {
            for q in queries {
                let chunk = (try? await mapKitSearch(
                    query: q,
                    near: anchor,
                    limit: 3,
                    radiusMeters: perAnchorRadius
                )) ?? []
                for item in chunk {
                    let key = item.displayName.lowercased()
                    if seen.insert(key).inserted {
                        results.append(item)
                    }
                    if results.count >= limit { break outer }
                }
            }
        }
        return results
    }

    private func mapKitSearch(
        query: String,
        near coordinate: CLLocationCoordinate2D?,
        limit: Int,
        radiusMeters: Double = 12_000
    ) async throws -> [PlaceSuggestion] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        // Penang-centred default — Komtar in central Georgetown. Replaces
        // the previous KL Sentral anchor so first-launch MapKit search
        // (before the user has picked a Start coord) returns Penang POIs.
        let anchor = coordinate ?? CLLocationCoordinate2D(latitude: 5.4148, longitude: 100.3299)
        request.region = MKCoordinateRegion(
            center: anchor,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.prefix(limit).compactMap { item -> PlaceSuggestion? in
            let coord = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coord) else { return nil }
            // The mapItem name is what the user expects to see ("USJ 9 LRT")
            // but for plain addresses it's nil — fall back to the placemark's
            // formatted street address.
            let label = item.name ?? formatPlacemark(item.placemark)
            return PlaceSuggestion(displayName: label, lat: coord.latitude, lon: coord.longitude)
        }
    }

    private func formatPlacemark(_ placemark: MKPlacemark) -> String {
        let parts = [placemark.thoroughfare, placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Unnamed place" : parts.joined(separator: ", ")
    }

    func resolveCoordinate(label: String) async throws -> ResolvedCoordinate {
        let query = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw CLError(.geocodeFoundNoResult) }

        do {
            if let placemark = try await geocoder.geocodeAddressString(query).first,
               let location = placemark.location {
                let coordinate = location.coordinate
                return ResolvedCoordinate(
                    lat: coordinate.latitude,
                    lng: coordinate.longitude,
                    clusterId: clusterId(latitude: coordinate.latitude, longitude: coordinate.longitude)
                )
            }
        } catch {
            return fallbackPoint(label: query)
        }

        return fallbackPoint(label: query)
    }

    func clusterId(latitude: Double, longitude: Double) -> String {
        let latBucket = (latitude * 50.0).rounded() / 50.0
        let lngBucket = (longitude * 50.0).rounded() / 50.0
        return "cluster-\(token(latBucket))-\(token(lngBucket))"
    }

    private func fallbackPoint(label: String) -> ResolvedCoordinate {
        let hash = abs(label.lowercased().hashValue)
        let latPart = Double(hash & 0xffff) / 65_535.0
        let lngPart = Double((hash >> 16) & 0xffff) / 65_535.0
        let latitude = 3.02 + latPart * 0.35
        let longitude = 101.55 + lngPart * 0.35
        return ResolvedCoordinate(lat: latitude, lng: longitude, clusterId: clusterId(latitude: latitude, longitude: longitude))
    }

    private func token(_ value: Double) -> String {
        String(format: "%.2f", value).replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "-", with: "m")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let best = locations
                .filter({ $0.horizontalAccuracy > 0 })
                .min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }),
                  let continuation = locationContinuation else { return }

            locationContinuation = nil
            locationTimeoutTask?.cancel()
            continuation.resume(returning: best.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            locationTimeoutTask?.cancel()
            continuation.resume(throwing: error)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .restricted, .denied:
                guard let continuation = locationContinuation else { return }
                locationContinuation = nil
                locationTimeoutTask?.cancel()
                continuation.resume(throwing: CLError(.denied))
            case .authorizedAlways, .authorizedWhenInUse:
                if locationContinuation != nil {
                    self.manager.requestLocation()
                }
            default:
                break
            }
        }
    }
}
