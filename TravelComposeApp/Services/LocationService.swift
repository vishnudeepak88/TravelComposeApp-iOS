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
        // anchor coordinate when present; otherwise default to a Klang Valley
        // box so the demo and Malaysian users get reasonable results.
        return try await mapKitSearch(query: cleaned, near: coordinate, limit: limit)
    }

    /// Suggests pickup / drop candidates near a coordinate AND along
    /// the corridor between two coordinates when both are given.
    /// Combines transit hubs, malls, shopping centres, and well-known
    /// landmarks — the places Malaysian commuters actually meet
    /// drivers ("see you at Sunway Pyramid"). Drives the "Suggested
    /// pickups" / "Suggested drops" pill rows on Create Route.
    ///
    /// When `corridorAnchor` is provided, we also sample a query at
    /// the midpoint between `coordinate` and `corridorAnchor` so the
    /// rail surfaces waypoints riders along the route can join from,
    /// not just hubs clustered around the endpoints.
    func searchNearbyHubs(near coordinate: CLLocationCoordinate2D,
                          corridorAnchor: CLLocationCoordinate2D? = nil,
                          radiusMeters: Double = 5_000,
                          limit: Int = 8) async throws -> [PlaceSuggestion] {
        // Each query phrase pulls a distinct category MapKit indexes well.
        // Transit first (the most common meeting point), then high-traffic
        // landmarks riders use as casual reference ("pick me up at AEON").
        let queries = [
            "LRT station",
            "MRT station",
            "bus station",
            "shopping mall",
            "university"
        ]

        // Sample anchors: the start coord, the corridor midpoint when we
        // have both endpoints, and the corridor anchor itself. Midpoint
        // surfaces "places along the way" rather than only at endpoints.
        var anchors: [CLLocationCoordinate2D] = [coordinate]
        if let other = corridorAnchor {
            let mid = CLLocationCoordinate2D(
                latitude:  (coordinate.latitude  + other.latitude)  / 2.0,
                longitude: (coordinate.longitude + other.longitude) / 2.0
            )
            anchors.append(mid)
        }
        // Per-anchor search radius — widen slightly when corridor is
        // active so the midpoint catches a bigger slice.
        let perAnchorRadius = corridorAnchor == nil ? radiusMeters : max(radiusMeters, 7_000)

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
        let anchor = coordinate ?? CLLocationCoordinate2D(latitude: 3.139, longitude: 101.6869)
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
