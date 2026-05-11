import SwiftUI
import MapKit

// MARK: - Abstract Route Diagram
//
// SwiftUI port of the `RouteDiagram` SVG component from
// `car-pool/project/tokens.jsx`. A stylised, non-map "route" visual
// for use on Ride Detail and Live Tracking. The codebase already has
// `MapPlaceholder` (Polished.swift) for the picker/preview surfaces;
// this component is the *narrative* version — a curving polyline
// through 4 anchor points over a faint city grid + abstract land/water
// shapes — meant for hero cards, not for picking a location.
//
// Renders the same visual whether 2 or N stops are passed; intermediate
// stops snap to the nearest anchor. Callers pass `dark: true` for the
// tracking screen's full-bleed dark variant.

struct RouteStop: Hashable {
    let label: String
    let kind: Kind
    enum Kind { case origin, stop, dest }
}

// MARK: - Real MapKit route preview
//
// Uses Apple Maps tiles + real route point coordinates. It requests
// MKDirections automobile legs between every pickup/drop stop, sums the
// road distance + ETA, and falls back to direct-line estimates when Apple
// Maps cannot resolve a leg.

struct VRouteMapPreview: View {
    var route: RecurringRoute
    var height: CGFloat = 200
    var accent: Color = VPalette.primary
    var liveCoordinate: CLLocationCoordinate2D? = nil
    var cornerRadius: CGFloat = 18

    @State private var camera: MapCameraPosition = .automatic
    @State private var routeSegments: [MapRouteSegment] = []
    @State private var routeSummary: MapRouteSummary? = nil
    @State private var isResolvingRoute = false
    @State private var routeResolutionFailed = false
    @State private var isMapsPickerPresented = false

    private var stops: [MapStop] {
        let pickups = route.pickupPoints.enumerated().compactMap { index, point in
            MapStop(point: point, title: point.label, kind: index == 0 ? .pickup : .waypoint)
        }
        let drops = route.dropPoints.enumerated().compactMap { index, point in
            MapStop(point: point, title: point.label, kind: index == route.dropPoints.count - 1 ? .drop : .waypoint)
        }
        return pickups + drops
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        stops.map(\.coordinate).filter(CLLocationCoordinate2DIsValid)
    }

    private var routeSignature: String {
        routeCoordinates
            .map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }
            .joined(separator: "|")
    }

    var body: some View {
        ZStack(alignment: .top) {
            if routeCoordinates.count >= 2 {
                Map(position: $camera, interactionModes: [.pan, .zoom]) {
                    if routeSegments.isEmpty {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(accent.opacity(0.75), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [7, 5]))
                    }

                    ForEach(routeSegments) { segment in
                        MapPolyline(segment.polyline)
                            .stroke(
                                accent.opacity(segment.isEstimated ? 0.72 : 1),
                                style: StrokeStyle(
                                    lineWidth: segment.isEstimated ? 4 : 5,
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: segment.isEstimated ? [7, 5] : []
                                )
                            )
                    }

                    ForEach(stops) { stop in
                        Annotation(stop.title, coordinate: stop.coordinate, anchor: .bottom) {
                            mapPin(for: stop)
                        }
                    }

                    if let liveCoordinate, CLLocationCoordinate2DIsValid(liveCoordinate) {
                        Annotation("Driver", coordinate: liveCoordinate, anchor: .center) {
                            ZStack {
                                Circle()
                                    .fill(VPalette.primary)
                                    .frame(width: 30, height: 30)
                                Circle()
                                    .stroke(.white, lineWidth: 3)
                                    .frame(width: 30, height: 30)
                                Image(systemName: "car.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: VPalette.primary.opacity(0.45), radius: 10, y: 4)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
            } else {
                unavailableMapPlaceholder
            }

            mapControlsOverlay
                .padding(10)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .confirmationDialog("Open route with",
                            isPresented: $isMapsPickerPresented,
                            titleVisibility: .visible) {
            Button("Apple Maps") {
                openRouteExternally(with: .appleMaps)
            }
            Button("Google Maps") {
                openRouteExternally(with: .googleMaps)
            }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: routeSignature) {
            await refreshRoute()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var unavailableMapPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [VPalette.surfaceHigh, VPalette.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.slash")
                        .font(.title3.weight(.black))
                        .foregroundColor(VPalette.warning)
                        .frame(width: 38, height: 38)
                        .background(VPalette.warning.opacity(0.14))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Map unavailable")
                            .font(.subheadline.weight(.black))
                            .foregroundColor(VPalette.text)
                        Text("This route needs saved pickup and drop coordinates.")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(VPalette.textSec)
                            .lineLimit(2)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    VRouteGlyph(squareColor: accent)
                        .frame(width: 10)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(route.startLocation.isEmpty ? "Start location missing" : route.startLocation)
                            .font(.caption.weight(.heavy))
                            .foregroundColor(VPalette.text)
                            .lineLimit(2)
                        Text(route.endLocation.isEmpty ? "Destination missing" : route.endLocation)
                            .font(.caption.weight(.heavy))
                            .foregroundColor(VPalette.text)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var mapControlsOverlay: some View {
        HStack(alignment: .top, spacing: 8) {
            routeBadge
                .layoutPriority(1)

            Spacer(minLength: 8)

            if routeCoordinates.count >= 2 {
                Button {
                    isMapsPickerPresented = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "location.north.line.fill")
                            .font(.caption2.weight(.black))
                        Text("Open")
                            .font(.caption2.weight(.black))
                    }
                    .foregroundColor(VPalette.text)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Open route in maps"))
            }
        }
    }

    @ViewBuilder
    private var routeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: routeSummary?.symbol ?? routeBadgeFallbackSymbol)
                .font(.caption2.weight(.black))
            Text(routeBadgeText)
                .font(.caption2.weight(.black))
                .lineLimit(1)
        }
        .foregroundColor(VPalette.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private var routeBadgeText: String {
        if routeCoordinates.count < 2 { return "Missing coordinates" }
        if isResolvingRoute { return "Calculating route" }
        if let routeSummary { return routeSummary.badgeText }
        return routeResolutionFailed ? "Direct route estimate" : "Loading route"
    }

    private var routeBadgeFallbackSymbol: String {
        routeResolutionFailed ? "point.topleft.down.curvedto.point.bottomright.up" : "map.fill"
    }

    private var accessibilityLabel: String {
        let origin = stops.first?.title ?? route.startLocation
        let destination = stops.last?.title ?? route.endLocation
        if let routeSummary {
            return "Map route from \(origin) to \(destination), \(routeSummary.accessibilityText)"
        }
        return "Map route from \(origin) to \(destination)"
    }

    @ViewBuilder
    private func mapPin(for stop: MapStop) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                Image(systemName: stop.symbol)
                    .font(.caption.weight(.black))
                    .foregroundColor(stop.color)
            }
            Text(stop.shortTitle)
                .font(.caption2.weight(.heavy))
                .foregroundColor(VPalette.text)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }

    @MainActor
    private func refreshRoute() async {
        camera = .region(mapRegion(for: routeCoordinates, liveCoordinate: liveCoordinate))
        routeSegments = []
        routeSummary = nil
        isResolvingRoute = false
        routeResolutionFailed = false

        guard routeCoordinates.count >= 2 else {
            return
        }

        isResolvingRoute = true

        var segments: [MapRouteSegment] = []
        var totalDistance: CLLocationDistance = 0
        var totalDuration: TimeInterval = 0
        var resolvedLegs = 0
        var estimatedLegs = 0

        for (index, pair) in zip(routeCoordinates, routeCoordinates.dropFirst()).enumerated() {
            if Task.isCancelled { return }
            let start = pair.0
            let end = pair.1

            do {
                let route = try await drivingRoute(from: start, to: end)
                if Task.isCancelled { return }
                segments.append(MapRouteSegment(index: index, polyline: route.polyline, isEstimated: false))
                totalDistance += route.distance
                totalDuration += route.expectedTravelTime
                resolvedLegs += 1
            } catch {
                if Task.isCancelled { return }
                segments.append(MapRouteSegment(index: index, polyline: directPolyline(from: start, to: end), isEstimated: true))
                totalDistance += directDistance(from: start, to: end)
                estimatedLegs += 1
            }
        }

        if Task.isCancelled { return }
        routeSegments = segments
        routeResolutionFailed = resolvedLegs == 0
        isResolvingRoute = false

        if !segments.isEmpty {
            routeSummary = MapRouteSummary(
                distanceMeters: totalDistance,
                expectedTravelTime: estimatedLegs == 0 ? totalDuration : nil,
                status: resolvedLegs == 0 ? .directEstimate : (estimatedLegs == 0 ? .appleRoute : .partialEstimate)
            )
        }
    }

    private func drivingRoute(from start: CLLocationCoordinate2D,
                              to end: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .automobile

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.min(by: { lhs, rhs in
            lhs.expectedTravelTime < rhs.expectedTravelTime
        }) else {
            throw MapRouteResolutionError.noRoute
        }
        return route
    }

    private func directPolyline(from start: CLLocationCoordinate2D,
                                to end: CLLocationCoordinate2D) -> MKPolyline {
        var coordinates = [start, end]
        return MKPolyline(coordinates: &coordinates, count: coordinates.count)
    }

    private func directDistance(from start: CLLocationCoordinate2D,
                                to end: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    private func openRouteExternally(with provider: ExternalRouteProvider) {
        guard let url = externalRouteURL(for: provider) else { return }
        UIApplication.shared.open(url)
    }

    private func externalRouteURL(for provider: ExternalRouteProvider) -> URL? {
        guard let origin = routeCoordinates.first,
              let destination = routeCoordinates.last else {
            return nil
        }

        switch provider {
        case .appleMaps:
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "saddr", value: Self.coordinateString(origin)),
                URLQueryItem(name: "daddr", value: Self.coordinateString(destination)),
                URLQueryItem(name: "dirflg", value: "d")
            ]
            return components?.url

        case .googleMaps:
            if let nativeURL = googleMapsNativeURL(origin: origin, destination: destination),
               UIApplication.shared.canOpenURL(nativeURL) {
                return nativeURL
            }
            return googleMapsWebURL(origin: origin, destination: destination)
        }
    }

    private func googleMapsNativeURL(origin: CLLocationCoordinate2D,
                                     destination: CLLocationCoordinate2D) -> URL? {
        var components = URLComponents()
        components.scheme = "comgooglemaps"
        components.host = ""
        components.queryItems = [
            URLQueryItem(name: "saddr", value: Self.coordinateString(origin)),
            URLQueryItem(name: "daddr", value: Self.coordinateString(destination)),
            URLQueryItem(name: "directionsmode", value: "driving")
        ]
        return components.url
    }

    private func googleMapsWebURL(origin: CLLocationCoordinate2D,
                                  destination: CLLocationCoordinate2D) -> URL? {
        let waypoints = routeCoordinates.dropFirst().dropLast().map(Self.coordinateString)
        var queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: Self.coordinateString(origin)),
            URLQueryItem(name: "destination", value: Self.coordinateString(destination)),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        if !waypoints.isEmpty {
            queryItems.append(URLQueryItem(name: "waypoints", value: waypoints.joined(separator: "|")))
        }

        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = queryItems
        return components?.url
    }

    private static func coordinateString(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
    }

    private func mapRegion(for coordinates: [CLLocationCoordinate2D],
                           liveCoordinate: CLLocationCoordinate2D?) -> MKCoordinateRegion {
        var all = coordinates
        if let liveCoordinate, CLLocationCoordinate2DIsValid(liveCoordinate) {
            all.append(liveCoordinate)
        }

        guard let first = all.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 3.1390, longitude: 101.6869),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLng = first.longitude
        var maxLng = first.longitude

        for coord in all.dropFirst() {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLng = min(minLng, coord.longitude)
            maxLng = max(maxLng, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let latDelta = max(0.012, (maxLat - minLat) * 1.7)
        let lngDelta = max(0.012, (maxLng - minLng) * 1.7)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
        )
    }
}

private struct MapRouteSegment: Identifiable {
    let id: String
    let polyline: MKPolyline
    let isEstimated: Bool

    init(index: Int, polyline: MKPolyline, isEstimated: Bool) {
        self.id = "route-leg-\(index)-\(isEstimated ? "direct" : "road")"
        self.polyline = polyline
        self.isEstimated = isEstimated
    }
}

private struct MapRouteSummary: Equatable {
    enum Status {
        case appleRoute
        case partialEstimate
        case directEstimate
    }

    let distanceMeters: CLLocationDistance
    let expectedTravelTime: TimeInterval?
    let status: Status

    var symbol: String {
        switch status {
        case .appleRoute:       return "map.fill"
        case .partialEstimate:  return "exclamationmark.triangle.fill"
        case .directEstimate:   return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    var badgeText: String {
        let distance = Self.formattedDistance(distanceMeters)
        switch status {
        case .appleRoute:
            if let expectedTravelTime {
                return "\(distance) · \(Self.formattedDuration(expectedTravelTime))"
            }
            return distance
        case .partialEstimate:
            if let expectedTravelTime, expectedTravelTime > 0 {
                return "Partial · \(distance) · \(Self.formattedDuration(expectedTravelTime))"
            }
            return "Partial · \(distance)"
        case .directEstimate:
            return "Direct · \(distance)"
        }
    }

    var accessibilityText: String {
        switch status {
        case .appleRoute:
            if let expectedTravelTime {
                return "\(Self.formattedDistance(distanceMeters)), estimated drive time \(Self.formattedDuration(expectedTravelTime))"
            }
            return Self.formattedDistance(distanceMeters)
        case .partialEstimate:
            return "partially estimated distance \(Self.formattedDistance(distanceMeters))"
        case .directEstimate:
            return "direct distance estimate \(Self.formattedDistance(distanceMeters))"
        }
    }

    private static func formattedDistance(_ meters: CLLocationDistance) -> String {
        if meters < 950 {
            let rounded = Int((meters / 10).rounded() * 10)
            return "\(max(rounded, 10)) m"
        }
        return String(format: "%.1f km", meters / 1_000)
    }

    private static func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        guard minutes >= 60 else { return "\(minutes) min" }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(remainingMinutes) min"
    }
}

private enum MapRouteResolutionError: Error {
    case noRoute
}

private enum ExternalRouteProvider {
    case appleMaps
    case googleMaps
}

private struct MapStop: Identifiable {
    enum Kind { case pickup, waypoint, drop }

    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let kind: Kind

    init?(point: RoutePoint, title: String, kind: Kind) {
        let coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
        guard CLLocationCoordinate2DIsValid(coordinate),
              !(abs(point.lat) < 0.0001 && abs(point.lng) < 0.0001) else { return nil }
        self.id = point.id
        self.title = title
        self.coordinate = coordinate
        self.kind = kind
    }

    var shortTitle: String {
        let first = title.split(separator: ",").first.map(String.init) ?? title
        return first.isEmpty ? "Stop" : first
    }

    var symbol: String {
        switch kind {
        case .pickup:   return "figure.wave"
        case .drop:     return "flag.checkered"
        case .waypoint: return "mappin"
        }
    }

    var color: Color {
        switch kind {
        case .pickup:   return VPalette.success
        case .drop:     return VPalette.primary
        case .waypoint: return VPalette.warning
        }
    }
}

struct VRouteDiagram: View {
    var stops: [RouteStop]
    var height: CGFloat = 200
    var accent: Color = VPalette.success
    var dark: Bool = false

    private var landColor: Color {
        dark ? Color(hex: 0x0B2238) : Color(hex: 0xEEF2F1)
    }
    private var waterColor: Color {
        dark ? Color(hex: 0x0F2A45) : Color(hex: 0xDCE8EE)
    }
    private var gridColor: Color {
        dark ? Color.white.opacity(0.06) : VPalette.text.opacity(0.05)
    }
    private var blockColor: Color {
        dark ? Color(hex: 0x143654) : Color(hex: 0xE2E8E2)
    }
    private var pinFill: Color {
        dark ? Color(hex: 0x0E1B2C) : .white
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = height
            let pts: [CGPoint] = [
                CGPoint(x: 40,         y: h - 36),
                CGPoint(x: w * 0.32,   y: h * 0.36),
                CGPoint(x: w * 0.66,   y: h * 0.66),
                CGPoint(x: w - 40,     y: 36)
            ]

            ZStack {
                landColor

                // Land/water blobs
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.6))
                    p.addQuadCurve(to: CGPoint(x: w * 0.55, y: h * 0.62),
                                   control: CGPoint(x: w * 0.3, y: h * 0.5))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.55),
                                   control: CGPoint(x: w * 0.78, y: h * 0.7))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                .fill(waterColor.opacity(dark ? 0.4 : 0.55))

                Path { p in
                    p.move(to: CGPoint(x: w * 0.05, y: h * 0.18))
                    p.addQuadCurve(to: CGPoint(x: w * 0.35, y: h * 0.2),
                                   control: CGPoint(x: w * 0.2, y: h * 0.1))
                    p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.32))
                    p.addQuadCurve(to: CGPoint(x: w * 0.05, y: h * 0.3),
                                   control: CGPoint(x: w * 0.18, y: h * 0.28))
                    p.closeSubpath()
                }
                .fill(waterColor.opacity(dark ? 0.3 : 0.4))

                // Grid
                Path { p in
                    let cols = 8, rows = 5
                    for i in 0...cols {
                        let x = w * CGFloat(i) / CGFloat(cols)
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: h))
                    }
                    for i in 0...rows {
                        let y = h * CGFloat(i) / CGFloat(rows)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(gridColor, lineWidth: 1)

                // Block buildings
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(blockColor)
                    .frame(width: 40, height: 28)
                    .position(x: w * 0.1 + 20, y: h * 0.7 + 14)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(blockColor)
                    .frame(width: 28, height: 44)
                    .position(x: w * 0.46 + 14, y: h * 0.18 + 22)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(blockColor)
                    .frame(width: 36, height: 22)
                    .position(x: w * 0.76 + 18, y: h * 0.55 + 11)

                // Route shadow + path
                routePath(points: pts)
                    .stroke(
                        dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .offset(y: 2)
                routePath(points: pts)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

                // Stop dots
                ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                    let denom = max(1, stops.count - 1)
                    let idx = Int((Double(i) / Double(denom)) * Double(pts.count - 1) + 0.5)
                    let center = pts[min(idx, pts.count - 1)]
                    stopDot(stop: stop)
                        .position(center)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func stopDot(stop: RouteStop) -> some View {
        let outline: Color = {
            switch stop.kind {
            case .origin: return VPalette.primary
            case .dest:   return accent
            case .stop:   return VPalette.textHint
            }
        }()
        let inner: Color = {
            switch stop.kind {
            case .origin: return VPalette.primary
            case .dest:   return accent
            case .stop:   return VPalette.textHint
            }
        }()
        ZStack {
            Circle().fill(pinFill)
            Circle().stroke(outline, lineWidth: 2.5)
            Circle().fill(inner).frame(width: stop.kind == .stop ? 6 : 8, height: stop.kind == .stop ? 6 : 8)
        }
        .frame(width: 22, height: 22)
    }

    /// Smooth cubic curve through the 4 anchor points. Mirrors the JS
    /// path string `M… C…  S… S…` from the source component, which
    /// gives the diagram its characteristic gentle "S" sweep.
    private func routePath(points pts: [CGPoint]) -> Path {
        var p = Path()
        guard pts.count >= 4 else {
            if let first = pts.first { p.move(to: first) }
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            return p
        }
        p.move(to: pts[0])
        p.addCurve(
            to: pts[1],
            control1: CGPoint(x: pts[0].x + 60, y: pts[0].y - 80),
            control2: CGPoint(x: pts[1].x - 50, y: pts[1].y + 40)
        )
        // Reflect the last control around pts[1] for a smooth "S" join.
        let r1 = reflect(CGPoint(x: pts[1].x - 50, y: pts[1].y + 40), through: pts[1])
        p.addCurve(
            to: pts[2],
            control1: r1,
            control2: CGPoint(x: pts[2].x + 10, y: pts[2].y - 40)
        )
        let r2 = reflect(CGPoint(x: pts[2].x + 10, y: pts[2].y - 40), through: pts[2])
        p.addCurve(
            to: pts[3],
            control1: r2,
            control2: CGPoint(x: pts[3].x - 30, y: pts[3].y + 60)
        )
        return p
    }

    private func reflect(_ pt: CGPoint, through pivot: CGPoint) -> CGPoint {
        CGPoint(x: 2 * pivot.x - pt.x, y: 2 * pivot.y - pt.y)
    }
}

#Preview("Route diagram — light") {
    VRouteDiagram(
        stops: [
            .init(label: "Subang Jaya", kind: .origin),
            .init(label: "USJ 9 LRT",   kind: .stop),
            .init(label: "Bangsar",     kind: .stop),
            .init(label: "KLCC",        kind: .dest)
        ]
    )
    .padding()
    .background(VPalette.bg)
}

#Preview("Route diagram — dark") {
    VRouteDiagram(
        stops: [
            .init(label: "Subang Jaya", kind: .origin),
            .init(label: "KLCC",        kind: .dest)
        ],
        dark: true
    )
    .padding()
    .background(Color.black)
}
