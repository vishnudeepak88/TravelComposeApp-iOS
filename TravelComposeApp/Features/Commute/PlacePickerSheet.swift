import SwiftUI
import CoreLocation

// MARK: - Grab/Uber-style place picker.
//
// Tap a Start/Destination row → this sheet slides up. Search bar at the top
// is auto-focused so a known destination is one tap + a few keystrokes.
// Below the search, when the query is empty:
//   - "Use current location" (GPS one-tap)
//   - SAVED — Home / Work (set once, two taps forever)
//   - RECENT — last 8 picks, auto-recorded
//   - "Pick on map" footer link → escape hatch to the existing map picker
//
// The whole thing runs inside a NavigationStack so "Set Home" / "Set Work"
// can push a child picker without nested sheets.

// MARK: - Persistent storage for recents + saved slots

enum PlacesStorage {
    private static let recentsLimit = 8

    /// Scope every key by `userId` so two riders sharing a device don't see
    /// each other's recents or saved Home/Work. Empty userId falls back to
    /// the legacy unscoped key so existing dev-shortcut data still loads.
    private static func recentsKey(for userId: String) -> String {
        userId.isEmpty ? "voygo.places.recents" : "voygo.places.recents.\(userId)"
    }
    private static func savedKey(_ slot: SavedSlot, for userId: String) -> String {
        let suffix = userId.isEmpty ? "" : ".\(userId)"
        switch slot {
        case .home: return "voygo.places.home\(suffix)"
        case .work: return "voygo.places.work\(suffix)"
        }
    }

    static func loadRecents(for userId: String) -> [PlaceSuggestion] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey(for: userId)),
              let items = try? JSONDecoder().decode([PlaceSuggestion].self, from: data)
        else { return [] }
        return items
    }

    /// Records a pick. Dedupes by display name (case-insensitive) and caps
    /// the list at `recentsLimit`. Newest first.
    static func recordRecent(_ place: PlaceSuggestion, for userId: String) {
        var items = loadRecents(for: userId)
        items.removeAll {
            $0.displayName.caseInsensitiveCompare(place.displayName) == .orderedSame
        }
        items.insert(place, at: 0)
        if items.count > recentsLimit {
            items = Array(items.prefix(recentsLimit))
        }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: recentsKey(for: userId))
        }
    }

    static func clearRecents(for userId: String) {
        UserDefaults.standard.removeObject(forKey: recentsKey(for: userId))
    }

    static func loadSaved(_ slot: SavedSlot, for userId: String) -> PlaceSuggestion? {
        guard let data = UserDefaults.standard.data(forKey: savedKey(slot, for: userId)),
              let item = try? JSONDecoder().decode(PlaceSuggestion.self, from: data)
        else { return nil }
        return item
    }

    static func setSaved(_ slot: SavedSlot, to place: PlaceSuggestion?, for userId: String) {
        let key = savedKey(slot, for: userId)
        if let place, let data = try? JSONEncoder().encode(place) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    enum SavedSlot {
        case home, work
        var label: String {
            switch self {
            case .home: return "Home"
            case .work: return "Work"
            }
        }
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .work: return "briefcase.fill"
            }
        }
    }
}

// MARK: - Picker mode (drives nested "Set Home / Set Work" flow)

enum PlacePickerMode {
    /// Normal flow — pick a place and return it to the caller.
    case pick
    /// User is configuring a saved slot. Tapping a place saves it to the
    /// slot and pops back to the parent picker without returning anything.
    case setSaved(PlacesStorage.SavedSlot)
}

// MARK: - Sheet entry point

struct PlacePickerSheet: View {
    let title: String
    var onPick: (PlaceSuggestion) -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            PlacePickerView(
                title: title,
                mode: .pick,
                onPick: onPick,
                onCancel: onCancel
            )
        }
    }
}

// MARK: - The screen

struct PlacePickerView: View {
    let title: String
    let mode: PlacePickerMode
    /// Called when `mode == .pick` and the user accepts a place.
    var onPick: (PlaceSuggestion) -> Void
    /// Called when the user dismisses the whole sheet (root only).
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store

    private var userId: String { store.riderId }

    @State private var query = ""
    @State private var suggestions: [PlaceSuggestion] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil

    @State private var recents: [PlaceSuggestion] = []
    @State private var savedHome: PlaceSuggestion? = nil
    @State private var savedWork: PlaceSuggestion? = nil

    @State private var locating = false
    @State private var locationError: String? = nil
    @State private var locationErrorTask: Task<Void, Never>? = nil

    @State private var presentMapPicker = false
    /// First-appear flag so we don't grab focus on every state-driven
    /// re-render (which steals VoiceOver focus from the header).
    @State private var didInitialFocus = false

    @FocusState private var searchFocused: Bool

    private var isRootPicker: Bool {
        if case .pick = mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                searchBar

                ScrollView {
                    VStack(spacing: 18) {
                        if !suggestions.isEmpty || (!query.isEmpty && isSearching) {
                            suggestionList
                        } else if query.isEmpty {
                            currentLocationButton
                            if let error = locationError {
                                errorBanner(error)
                            }
                            savedSection
                            recentsSection
                            mapPickerLink
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Snapshot the userId now and only render its data — if a
            // sign-out/sign-in happens during this appear cycle, the
            // change-of-identity is caught by the .onChange below.
            let id = userId
            recents = PlacesStorage.loadRecents(for: id)
            savedHome = PlacesStorage.loadSaved(.home, for: id)
            savedWork = PlacesStorage.loadSaved(.work, for: id)
            // Auto-focus the search bar on the first appear only — cheaper
            // path for known destinations. Skip when VoiceOver is running
            // so the focus doesn't steal the screen reader's reading.
            if !didInitialFocus && !UIAccessibility.isVoiceOverRunning {
                searchFocused = true
                didInitialFocus = true
            }
        }
        .onDisappear {
            // Cancel in-flight tasks so they don't update @State on a
            // dismissed view (and don't burn API credits in the
            // background).
            searchTask?.cancel()
            locationErrorTask?.cancel()
        }
        .onChange(of: userId) { oldId, newId in
            // Only reload when the *signed-in user actually changed* —
            // not when an internal store update reseats `riderId` to the
            // same value (dev-mode sample reseed, refresh churn). The
            // previous version reloaded on any oldId→newId edge, which
            // included no-op transitions when riderId churned within the
            // same session.
            guard oldId != newId, !newId.isEmpty else { return }
            recents = PlacesStorage.loadRecents(for: newId)
            savedHome = PlacesStorage.loadSaved(.home, for: newId)
            savedWork = PlacesStorage.loadSaved(.work, for: newId)
        }
        .sheet(isPresented: $presentMapPicker) {
            MapLocationPickerView(
                title: title,
                initialCoordinate: nil,
                onPick: { suggestion in
                    presentMapPicker = false
                    accept(suggestion)
                },
                onCancel: { presentMapPicker = false }
            )
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if isRootPicker { onCancel() } else { dismiss() }
            } label: {
                Image(systemName: isRootPicker ? "xmark" : "chevron.left")
                    .font(.callout.weight(.bold))
                    .foregroundColor(VPalette.text)
                    .frame(width: 40, height: 40)
                    .background(VPalette.surface)
                    .overlay(Circle().stroke(VPalette.border, lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if case .setSaved(let slot) = mode {
                    VKicker(text: "Setting \(slot.label.lowercased())", size: 10)
                } else {
                    VKicker(text: "Where to?", size: 10)
                }
                Text(title)
                    .font(.title3.weight(.black))
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

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.bold))
                .foregroundColor(VPalette.textHint)
            TextField("Search places, LRT, area…", text: $query)
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
                    query = ""; suggestions = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
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
                .stroke(searchFocused ? VPalette.primary : VPalette.border,
                        lineWidth: searchFocused ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: Sections

    private var currentLocationButton: some View {
        Button {
            Task { await pickCurrentLocation() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(VPalette.primary.opacity(0.12)).frame(width: 38, height: 38)
                    if locating {
                        ProgressView().tint(VPalette.primary).controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.subheadline.weight(.heavy))
                            .foregroundColor(VPalette.primary)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Use current location")
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(VPalette.text)
                    Text(locating ? "Looking up your address…" : "Pin to where you are right now")
                        .font(.caption2)
                        .foregroundColor(VPalette.textSec)
                }
                Spacer()
                if !locating {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(VPalette.textHint)
                }
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(VPalette.primary.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(locating)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(VPalette.danger)
            Text(message)
                .font(.caption)
                .foregroundColor(VPalette.text)
            Spacer()
        }
        .padding(12)
        .background(VPalette.danger.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VKicker(text: "Saved").padding(.leading, 4)
            VStack(spacing: 0) {
                savedRow(slot: .home, place: savedHome)
                Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 60)
                savedRow(slot: .work, place: savedWork)
            }
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func savedRow(slot: PlacesStorage.SavedSlot, place: PlaceSuggestion?) -> some View {
        if let place {
            // Configured — tap picks; long-press to clear.
            Button { accept(place) } label: {
                savedRowBody(slot: slot, primary: place.displayName, isSet: true)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    PlacesStorage.setSaved(slot, to: nil, for: userId)
                    if slot == .home { savedHome = nil } else { savedWork = nil }
                } label: {
                    Label("Clear \(slot.label)", systemImage: "trash")
                }
                NavigationLink {
                    PlacePickerView(
                        title: "Set \(slot.label)",
                        mode: .setSaved(slot),
                        onPick: { _ in },
                        onCancel: {}
                    )
                    .onDisappear { reloadSaved() }
                } label: {
                    Label("Change \(slot.label)", systemImage: "pencil")
                }
            }
        } else {
            // Empty — tap to set up.
            NavigationLink {
                PlacePickerView(
                    title: "Set \(slot.label)",
                    mode: .setSaved(slot),
                    onPick: { _ in },
                    onCancel: {}
                )
                .onDisappear { reloadSaved() }
            } label: {
                savedRowBody(
                    slot: slot,
                    primary: "Set \(slot.label)",
                    isSet: false
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func savedRowBody(slot: PlacesStorage.SavedSlot, primary: String, isSet: Bool) -> some View {
        HStack(spacing: 12) {
            VIconBubble(
                systemName: slot.icon,
                color: isSet ? VPalette.primary : VPalette.textHint,
                size: 38, iconSize: 16
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.label)
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.text)
                Text(primary)
                    .font(.caption2)
                    .foregroundColor(isSet ? VPalette.textSec : VPalette.textHint)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: isSet ? "chevron.right" : "plus")
                .font(.footnote.weight(.bold))
                .foregroundColor(VPalette.textHint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var recentsSection: some View {
        Group {
            if recents.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VKicker(text: "Recent")
                        Spacer()
                        Button {
                            PlacesStorage.clearRecents(for: userId)
                            recents = []
                        } label: {
                            Text("Clear")
                                .font(.caption2.weight(.heavy))
                                .foregroundColor(VPalette.textHint)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(recents.enumerated()), id: \.element.id) { idx, place in
                            Button { accept(place) } label: {
                                recentRow(place)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    PlacesStorage.setSaved(.home, to: place, for: userId)
                                    savedHome = place
                                } label: {
                                    Label("Save as Home", systemImage: "house.fill")
                                }
                                Button {
                                    PlacesStorage.setSaved(.work, to: place, for: userId)
                                    savedWork = place
                                } label: {
                                    Label("Save as Work", systemImage: "briefcase.fill")
                                }
                            }
                            if idx < recents.count - 1 {
                                Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 60)
                            }
                        }
                    }
                    .background(VPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func recentRow(_ place: PlaceSuggestion) -> some View {
        HStack(spacing: 12) {
            VIconBubble(systemName: "clock.fill", color: VPalette.accent, size: 38, iconSize: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(place.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(VPalette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(coordinatesString(for: place))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VPalette.textHint)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundColor(VPalette.textHint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var mapPickerLink: some View {
        Button { presentMapPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "map.fill").font(.footnote).accessibilityHidden(true)
                Text("Pick on map")
                    .font(.footnote.weight(.heavy))
            }
            .foregroundColor(VPalette.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(VPalette.primaryContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Search results list

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { idx, place in
                Button { accept(place) } label: {
                    HStack(spacing: 12) {
                        VIconBubble(systemName: "mappin.circle.fill", color: VPalette.primary, size: 32, iconSize: 14)
                        Text(place.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(VPalette.text)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < suggestions.count - 1 {
                    Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 56)
                }
            }
        }
        .background(VPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Actions

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
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let bias = await VoygoLocationService.shared.lastKnownCoordinate()
            let results = (try? await VoygoLocationService.shared.searchPlaces(query: cleaned, near: bias)) ?? []
            if Task.isCancelled { return }
            await MainActor.run {
                self.suggestions = Array(results.prefix(8))
                self.isSearching = false
            }
        }
    }

    private func pickCurrentLocation() async {
        locating = true
        locationError = nil
        locationErrorTask?.cancel()
        defer { locating = false }
        do {
            let coord = try await VoygoLocationService.shared.requestCurrentCoordinate()
            let label = await VoygoLocationService.shared.reverseGeocode(coordinate: coord)
                ?? String(format: "%.5f, %.5f", coord.latitude, coord.longitude)
            let suggestion = PlaceSuggestion(displayName: label, lat: coord.latitude, lon: coord.longitude)
            accept(suggestion)
        } catch {
            locationError = "Couldn't read your location. Allow precise location in Settings → Privacy."
            // Auto-clear the banner after 5 seconds — the previous banner
            // had no dismiss control and stayed up indefinitely.
            locationErrorTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { locationError = nil }
            }
        }
    }

    /// Single accept path — handles both .pick and .setSaved modes plus
    /// auto-recording the choice into recents.
    private func accept(_ place: PlaceSuggestion) {
        PlacesStorage.recordRecent(place, for: userId)
        switch mode {
        case .pick:
            onPick(place)
        case .setSaved(let slot):
            PlacesStorage.setSaved(slot, to: place, for: userId)
            dismiss()  // pop back to the parent picker
        }
    }

    private func reloadSaved() {
        savedHome = PlacesStorage.loadSaved(.home, for: userId)
        savedWork = PlacesStorage.loadSaved(.work, for: userId)
    }

    private func coordinatesString(for place: PlaceSuggestion) -> String {
        String(format: "%.4f, %.4f", place.lat, place.lon)
    }
}
