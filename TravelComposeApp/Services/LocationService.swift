import CoreLocation
import Foundation
import MapKit

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

    /// Suggests transit hubs and major waypoints close to a coordinate.
    /// Drives the "Suggested pickups" / "Suggested drops" pill rows on
    /// Create Route — once a driver has picked Start/Destination, this
    /// returns the obvious LRT/MRT/bus stops within ~5km so they don't
    /// have to type each one out.
    func searchNearbyHubs(near coordinate: CLLocationCoordinate2D, radiusMeters: Double = 5_000, limit: Int = 5) async throws -> [PlaceSuggestion] {
        // MKLocalSearch's "natural language" query handles synonyms surprisingly
        // well: "LRT" returns Klang Valley LRT stations, "MRT" returns MRT
        // ones, "transit" widens to bus + rail. Combining a few queries gives
        // a richer pool than any single phrasing.
        let queries = ["LRT station", "MRT station", "bus station"]
        var seen: Set<String> = []
        var results: [PlaceSuggestion] = []
        for q in queries {
            let chunk = (try? await mapKitSearch(query: q, near: coordinate, limit: limit, radiusMeters: radiusMeters)) ?? []
            for item in chunk {
                let key = item.displayName.lowercased()
                if seen.insert(key).inserted {
                    results.append(item)
                }
                if results.count >= limit { return results }
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
        Task { @MainActor in
            switch manager.authorizationStatus {
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
