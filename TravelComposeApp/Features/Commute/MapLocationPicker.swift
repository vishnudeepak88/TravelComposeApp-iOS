import SwiftUI
import MapKit
import CoreLocation

// MARK: - Map-based location picker.
//
// Replaces the plain text fields for Start Location / Destination on the
// Create Route screen. Pattern is "drop pin on the map's center" — the user
// pans the map, the crosshair stays put, and when they tap "Use this
// location" we capture the camera's center coordinate plus the reverse-
// geocoded label.
//
// A search bar above the map lets the user jump to a known place (LRT
// station, mall, neighbourhood) instead of having to scroll there. Search
// results delegate to `VoygoLocationService.searchPlaces` so we share the
// same suggestion source as the rest of the app.

struct MapLocationPickerView: View {
    /// Header label — "Pick start location" vs "Pick destination" so the
    /// user knows which field they're filling.
    let title: String
    /// Initial coordinate the camera should focus on. nil falls back to KL.
    var initialCoordinate: CLLocationCoordinate2D? = nil

    /// Called with the user's selection. Lat/lng come from the map camera
    /// center at confirmation time; displayName is the reverse-geocoded
    /// label (or the search result's display name when one was tapped).
    var onPick: (PlaceSuggestion) -> Void
    var onCancel: () -> Void

    @State private var camera: MapCameraPosition
    @State private var centerCoordinate: CLLocationCoordinate2D
    @State private var centerLabel: String = "Drop pin here"
    @State private var isResolvingLabel = false
    @State private var query: String = ""
    @State private var suggestions: [PlaceSuggestion] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var labelTask: Task<Void, Never>? = nil
    @FocusState private var searchFocused: Bool

    /// Sentinel used in `init` to fall back to a sensible Klang Valley
    /// view when the caller has no anchor (first time, no prior selection).
    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 3.1390, longitude: 101.6869)

    init(
        title: String,
        initialCoordinate: CLLocationCoordinate2D? = nil,
        onPick: @escaping (PlaceSuggestion) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.initialCoordinate = initialCoordinate
        self.onPick = onPick
        self.onCancel = onCancel
        let start = initialCoordinate ?? Self.fallbackCenter
        _centerCoordinate = State(initialValue: start)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: start,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )))
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                searchBar
                if !suggestions.isEmpty {
                    suggestionList
                } else {
                    mapWithCrosshair
                }
                bottomBar
            }
        }
        .task {
            await refreshLabel(for: centerCoordinate)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(VPalette.text)
                    .frame(width: 40, height: 40)
                    .background(VPalette.surface)
                    .overlay(Circle().stroke(VPalette.border, lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                VKicker(text: "Map picker", size: 10)
                Text(title)
                    .font(.system(size: 22, weight: .black))
                    .tracking(-0.4)
                    .foregroundColor(VPalette.text)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(VPalette.textHint)
            TextField("Search a place, LRT, area…", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .foregroundColor(VPalette.text)
                .tint(VPalette.primary)
                .onChange(of: query) { _, newValue in
                    scheduleSearch(for: newValue)
                }
            if isSearching {
                ProgressView().tint(VPalette.primary).controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    suggestions = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(VPalette.textHint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(VPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(searchFocused ? VPalette.primary : VPalette.border, lineWidth: searchFocused ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, suggestion in
                    Button {
                        accept(suggestion: suggestion)
                    } label: {
                        HStack(spacing: 12) {
                            VIconBubble(systemName: "mappin.circle.fill", color: VPalette.primary, size: 32, iconSize: 14)
                            Text(suggestion.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(VPalette.text)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx < suggestions.count - 1 {
                        Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 60)
                    }
                }
            }
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var mapWithCrosshair: some View {
        ZStack {
            // The actual map. `onMapCameraChange` lets us track the pan in
            // near-real-time so the bottom card reflects whatever's
            // currently under the crosshair.
            MapReader { _ in
                Map(position: $camera, interactionModes: [.pan, .zoom]) {
                    Marker("", coordinate: centerCoordinate)
                        .tint(.clear)
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    centerCoordinate = context.region.center
                    // Reverse-geocode debounced so we don't fire CoreLocation
                    // on every pan tick.
                    scheduleLabelRefresh(for: context.region.center)
                }
                .mapStyle(.standard(elevation: .realistic))
            }

            // Fixed crosshair pin — sits in the screen center, always at
            // `centerCoordinate` because the map moves under it. The shadow
            // makes it pop on busy roadway tiles.
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    Circle()
                        .fill(VPalette.primary)
                        .frame(width: 12, height: 12)
                }
                Rectangle()
                    .fill(VPalette.primary)
                    .frame(width: 2, height: 24)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                Triangle()
                    .fill(VPalette.primary)
                    .frame(width: 12, height: 8)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            }
            .offset(y: -20) // centers the tip on the actual coordinate
            .allowsHitTesting(false)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VIconBubble(systemName: "mappin.and.ellipse", color: VPalette.primary, size: 38, iconSize: 16)
                VStack(alignment: .leading, spacing: 2) {
                    VKicker(text: "Selected location", size: 10)
                    Text(centerLabel)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(VPalette.text)
                        .lineLimit(2)
                    if isResolvingLabel {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Looking up address…")
                                .font(.system(size: 11))
                                .foregroundColor(VPalette.textSec)
                        }
                    } else {
                        Text(coordinatesString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(VPalette.textHint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VPrimaryButton("Use this location") {
                let pick = PlaceSuggestion(
                    displayName: centerLabel.isEmpty ? coordinatesString : centerLabel,
                    lat: centerCoordinate.latitude,
                    lon: centerCoordinate.longitude
                )
                onPick(pick)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
        .padding(.top, 12)
        .background(.ultraThinMaterial)
        .background(VPalette.bg.opacity(0.6))
        .overlay(Rectangle().fill(VPalette.border).frame(height: 1), alignment: .top)
    }

    // MARK: - Helpers

    private var coordinatesString: String {
        String(format: "%.5f, %.5f", centerCoordinate.latitude, centerCoordinate.longitude)
    }

    /// Reverse geocode after a 350ms idle to keep CoreLocation calls cheap.
    private func scheduleLabelRefresh(for coordinate: CLLocationCoordinate2D) {
        labelTask?.cancel()
        labelTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            await refreshLabel(for: coordinate)
        }
    }

    private func refreshLabel(for coordinate: CLLocationCoordinate2D) async {
        await MainActor.run { isResolvingLabel = true }
        let label = await VoygoLocationService.shared.reverseGeocode(coordinate: coordinate)
        await MainActor.run {
            centerLabel = label ?? "Drop pin here"
            isResolvingLabel = false
        }
    }

    /// Debounced search — same 400ms window as the rest of the app's
    /// place-autocomplete experience.
    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else {
            suggestions = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            let results = (try? await VoygoLocationService.shared.searchPlaces(query: cleaned, near: centerCoordinate)) ?? []
            if Task.isCancelled { return }
            await MainActor.run {
                self.suggestions = Array(results.prefix(8))
                self.isSearching = false
            }
        }
    }

    /// Accept a suggestion: jump the camera there, close the search list,
    /// and let the user adjust the pin if they want before confirming.
    private func accept(suggestion: PlaceSuggestion) {
        let coord = CLLocationCoordinate2D(latitude: suggestion.lat, longitude: suggestion.lon)
        centerCoordinate = coord
        centerLabel = suggestion.displayName
        camera = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        suggestions = []
        query = ""
        searchFocused = false
    }
}

// MARK: - Crosshair pin shape (small filled triangle pointing down).

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
