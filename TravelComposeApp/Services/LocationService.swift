import CoreLocation
import Foundation

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
