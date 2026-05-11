import SwiftUI
import CoreLocation

// MARK: - Find Commute Routes (mirrors FindCommuteRoutesScreen.kt)

/// How the search results list is ordered. Stored alongside the
/// filter state in the VM so toggling between modes doesn't trigger
/// a server round-trip.
enum CommuteSortOption: String, CaseIterable, Identifiable {
    case bestMatch  = "Best match"
    case cheapest   = "Cheapest"
    case closest    = "Closest pickup"
    case reliable   = "Most reliable"
    var id: String { rawValue }
}

@MainActor
@Observable final class FindCommuteRoutesViewModel {
    var homeQuery = ""
    var officeQuery = ""
    var homeSuggestions: [PlaceSuggestion] = []
    var officeSuggestions: [PlaceSuggestion] = []
    var homeLoading = false
    var officeLoading = false
    var earliestTime = "07:00"
    var latestTime   = "09:30"
    /// Day-of-week filter, default Mon–Fri. Routes that don't run on
    /// any of the rider's chosen days are dropped server-side.
    var daysOfWeek: DaysOfWeekFlags = .weekdays
    /// Budget cap (RM/seat). `nil` means no cap.
    var maxPriceMyr: Int? = nil
    /// Sort order — applied client-side over the server's match
    /// result. Persisted in UserDefaults so a rider's last-chosen
    /// sort survives app restarts. Initialised from the stored
    /// value (or `.bestMatch` on first launch).
    var sortBy: CommuteSortOption = {
        if let raw = UserDefaults.standard.string(forKey: "voygo.commute.sortBy"),
           let v = CommuteSortOption(rawValue: raw) {
            return v
        }
        return .bestMatch
    }() {
        didSet {
            UserDefaults.standard.set(sortBy.rawValue, forKey: "voygo.commute.sortBy")
        }
    }
    var results: [CommuteRouteMatchResult] = []
    var isSearching = false
    var isLocatingHome = false
    var errorMessage: String? = nil

    /// True when the VM hydrated its query state from a saved search.
    /// View uses this to short-circuit the "first paint empty" look.
    var hasRestoredSavedSearch = false

    var selectedHomeLat: Double? = nil
    var selectedHomeLng: Double? = nil
    var selectedOfficeLat: Double? = nil
    var selectedOfficeLng: Double? = nil

    /// True when both home coords are known — drives whether the walk
    /// distance pill on each result card is shown (the backend's
    /// fallback constant when no coord is provided isn't worth
    /// surfacing).
    var hasRealHomeCoord: Bool { selectedHomeLat != nil && selectedHomeLng != nil }
    private var suppressNextHomeChange = false
    private var suppressNextOfficeChange = false

    private var homeTask: Task<Void, Never>? = nil
    private var officeTask: Task<Void, Never>? = nil

    var store: AppStore?

    func onHomeQueryChange(_ q: String) {
        if suppressNextHomeChange {
            suppressNextHomeChange = false
            return
        }
        homeQuery = q
        selectedHomeLat = nil; selectedHomeLng = nil
        homeTask?.cancel()
        guard q.count >= 2 else { homeSuggestions = []; return }
        homeLoading = true
        homeTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let bias = await VoygoLocationService.shared.lastKnownCoordinate()
            if let results = try? await VoygoAPIClient.autocompletePlaces(
                query: q,
                lat: bias?.latitude,
                lon: bias?.longitude
            ) {
                homeSuggestions = results
            }
            homeLoading = false
        }
    }

    func onOfficeQueryChange(_ q: String) {
        if suppressNextOfficeChange {
            suppressNextOfficeChange = false
            return
        }
        officeQuery = q
        selectedOfficeLat = nil; selectedOfficeLng = nil
        officeTask?.cancel()
        guard q.count >= 2 else { officeSuggestions = []; return }
        officeLoading = true
        officeTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let bias = await VoygoLocationService.shared.lastKnownCoordinate()
            if let results = try? await VoygoAPIClient.autocompletePlaces(
                query: q,
                lat: bias?.latitude,
                lon: bias?.longitude
            ) {
                officeSuggestions = results
            }
            officeLoading = false
        }
    }

    func selectHome(_ s: PlaceSuggestion) {
        suppressNextHomeChange = true
        homeQuery = s.displayName; selectedHomeLat = s.lat; selectedHomeLng = s.lon
        homeSuggestions = []
    }
    func selectOffice(_ s: PlaceSuggestion) {
        suppressNextOfficeChange = true
        officeQuery = s.displayName; selectedOfficeLat = s.lat; selectedOfficeLng = s.lon
        officeSuggestions = []
    }
    func clearHome() {
        homeTask?.cancel()
        homeQuery = ""
        selectedHomeLat = nil
        selectedHomeLng = nil
        homeSuggestions = []
        homeLoading = false
    }
    func clearOffice() {
        officeTask?.cancel()
        officeQuery = ""
        selectedOfficeLat = nil
        selectedOfficeLng = nil
        officeSuggestions = []
        officeLoading = false
    }
    func clearDropdowns() { homeSuggestions = []; officeSuggestions = [] }

    func useCurrentLocationForHome() {
        guard !isLocatingHome else { return }
        isLocatingHome = true
        errorMessage = nil
        homeTask?.cancel()
        Task {
            do {
                let coordinate = try await VoygoLocationService.shared.requestCurrentCoordinate()
                let label = await VoygoLocationService.shared.reverseGeocode(coordinate: coordinate)
                    ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
                suppressNextHomeChange = true
                homeQuery = label
                selectedHomeLat = coordinate.latitude
                selectedHomeLng = coordinate.longitude
                homeSuggestions = []
            } catch {
                errorMessage = "Unable to get your current location. Please allow precise location access in Settings and try again."
            }
            isLocatingHome = false
        }
    }

    func searchRoutes() {
        guard let store else { return }
        isSearching = true
        errorMessage = nil
        clearDropdowns()
        Task {
            let results = await store.findCommuteRoutes(
                homeLocation: homeQuery,
                officeLocation: officeQuery,
                earliestDeparture: earliestTime,
                latestDeparture: latestTime,
                homeLat: selectedHomeLat,
                homeLng: selectedHomeLng,
                officeLat: selectedOfficeLat,
                officeLng: selectedOfficeLng,
                daysOfWeek: daysOfWeek,
                maxPriceMyr: maxPriceMyr
            )
            self.results = applySort(to: results)
            self.isSearching = false
            // Persist the successful search so the next launch can
            // hydrate the form without the rider re-typing.
            await persistSavedSearch()
        }
    }

    /// Client-side sort applied over server-returned matches.
    func applySort(to source: [CommuteRouteMatchResult]) -> [CommuteRouteMatchResult] {
        switch sortBy {
        case .bestMatch:
            return source.sorted { $0.rankingScore > $1.rankingScore }
        case .cheapest:
            return source.sorted { $0.route.pricePerSeat < $1.route.pricePerSeat }
        case .closest:
            return source.sorted { $0.pickupDistanceMeters < $1.pickupDistanceMeters }
        case .reliable:
            return source.sorted { $0.route.reliability.onTimeRate > $1.route.reliability.onTimeRate }
        }
    }

    /// Re-applies the current sort to the existing result list without
    /// re-fetching. Used when the rider taps a different sort chip.
    func restortResults() {
        results = applySort(to: results)
    }

    /// Persistence — saved-search round-trip + UserDefaults mirror.
    func persistSavedSearch() async {
        guard let store else { return }
        let payload = SavedSearchPayload(
            originLabel: homeQuery,
            destinationLabel: officeQuery,
            originLat: selectedHomeLat,
            originLng: selectedHomeLng,
            destLat: selectedOfficeLat,
            destLng: selectedOfficeLng,
            earliestTime: earliestTime,
            latestTime: latestTime,
            daysOfWeek: daysOfWeek.asDictionary,
            maxPriceMyr: maxPriceMyr
        )
        await store.saveSearch(payload)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: "voygo.commute.savedSearch")
        }
    }

    /// Loads the rider's saved search — UserDefaults first for instant
    /// first-paint, server-confirm in the background to pick up
    /// cross-device updates.
    func restoreSavedSearch() async {
        if hasRestoredSavedSearch { return }
        hasRestoredSavedSearch = true
        if let data = UserDefaults.standard.data(forKey: "voygo.commute.savedSearch"),
           let payload = try? JSONDecoder().decode(SavedSearchPayload.self, from: data) {
            apply(savedSearch: payload)
        }
        if let store, let remote = await store.loadSavedSearch() {
            apply(savedSearch: remote)
        }
    }

    private func apply(savedSearch payload: SavedSearchPayload) {
        homeQuery = payload.originLabel
        officeQuery = payload.destinationLabel
        selectedHomeLat = payload.originLat
        selectedHomeLng = payload.originLng
        selectedOfficeLat = payload.destLat
        selectedOfficeLng = payload.destLng
        earliestTime = payload.earliestTime
        latestTime = payload.latestTime
        if let dict = payload.daysOfWeek {
            daysOfWeek = DaysOfWeekFlags.fromDictionary(dict)
        }
        maxPriceMyr = payload.maxPriceMyr
    }

    func applyPopularCorridor(_ corridor: PopularCorridor) {
        suppressNextHomeChange = true
        suppressNextOfficeChange = true
        homeQuery = corridor.origin
        officeQuery = corridor.destination
        selectedHomeLat = corridor.originLat
        selectedHomeLng = corridor.originLng
        selectedOfficeLat = corridor.destLat
        selectedOfficeLng = corridor.destLng
        homeSuggestions = []
        officeSuggestions = []
        searchRoutes()
    }
}

/// Pre-canned Penang commute corridors — surfaced as one-tap chips
/// above the search panel so a fresh rider gets to results in two
/// taps instead of typing.
struct PopularCorridor: Identifiable, Equatable {
    let id = UUID()
    let origin: String
    let destination: String
    let originLat: Double
    let originLng: Double
    let destLat: Double
    let destLng: Double

    static let penangPicks: [PopularCorridor] = [
        PopularCorridor(origin: "Air Itam",       destination: "Bayan Lepas FIZ",
                        originLat: 5.4036, originLng: 100.2730, destLat: 5.3267, destLng: 100.2787),
        PopularCorridor(origin: "Butterworth",    destination: "Komtar",
                        originLat: 5.4014, originLng: 100.3623, destLat: 5.4148, destLng: 100.3299),
        PopularCorridor(origin: "USM",            destination: "Bayan Lepas FIZ",
                        originLat: 5.3556, originLng: 100.3015, destLat: 5.3267, destLng: 100.2787),
        PopularCorridor(origin: "Tanjung Tokong", destination: "Bayan Lepas FIZ",
                        originLat: 5.4564, originLng: 100.3052, destLat: 5.3267, destLng: 100.2787),
        PopularCorridor(origin: "Penang Sentral", destination: "Komtar",
                        originLat: 5.4014, originLng: 100.3623, destLat: 5.4148, destLng: 100.3299),
        PopularCorridor(origin: "Gelugor",        destination: "Penang Airport",
                        originLat: 5.3556, originLng: 100.3015, destLat: 5.2974, destLng: 100.2734)
    ]
}

struct FindCommuteRoutesView: View {
    @Environment(AppStore.self) private var store
    @State private var vm = FindCommuteRoutesViewModel()
    var onOpenRoute: (String) -> Void
    var onMySubscriptions: () -> Void
    var onCreateRoute: () -> Void
    var onDriverDashboard: () -> Void
    /// Set when this screen is pushed onto a NavigationStack (e.g. from
    /// Home's "Book a ride"). Nil when used as a tab root (Routes tab),
    /// where the tab bar is the way out. Drives whether the hero shows
    /// a back chevron.
    var onBack: (() -> Void)? = nil

    @State private var showRequestSheet = false

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        Color.clear.frame(height: 0).id("top")
                        homeHero
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        modeRail
                            .padding(.horizontal, 16)

                        // Popular Penang corridors — one-tap pre-canned
                        // searches so a fresh rider can hit results in 2
                        // taps instead of typing two locations.
                        PopularCorridorsRow(corridors: PopularCorridor.penangPicks) { corridor in
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            vm.applyPopularCorridor(corridor)
                        }
                        .padding(.horizontal, 16)

                        MapsStyleCommuteSearchPanel(
                            homeQuery: $vm.homeQuery,
                            officeQuery: $vm.officeQuery,
                            earliestTime: $vm.earliestTime,
                            latestTime: $vm.latestTime,
                            homeSuggestions: vm.homeSuggestions,
                            officeSuggestions: vm.officeSuggestions,
                            homeLoading: vm.homeLoading,
                            officeLoading: vm.officeLoading,
                            isSearching: vm.isSearching,
                            isLocatingHome: vm.isLocatingHome,
                            errorMessage: vm.errorMessage,
                            onHomeChange: vm.onHomeQueryChange,
                            onOfficeChange: vm.onOfficeQueryChange,
                            onHomeSuggestionTap: vm.selectHome,
                            onOfficeSuggestionTap: vm.selectOffice,
                            onUseCurrentLocation: vm.useCurrentLocationForHome,
                            onClearHome: vm.clearHome,
                            onClearOffice: vm.clearOffice,
                            onSearch: {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                vm.searchRoutes()
                            }
                        )
                        .padding(.horizontal, 16)

                        // Day-of-week + price + sort filters. Wired so
                        // any change re-runs the server search (debounced
                        // implicitly via the search button + onChange).
                        CommuteFiltersBar(
                            days: $vm.daysOfWeek,
                            maxPriceMyr: $vm.maxPriceMyr,
                            sortBy: $vm.sortBy,
                            onChange: { changedSort in
                                if changedSort {
                                    vm.restortResults()
                                } else {
                                    vm.searchRoutes()
                                }
                            }
                        )
                        .padding(.horizontal, 16)

                        if !vm.results.isEmpty || vm.isSearching {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Best route matches")
                                        .font(.system(size: 16, weight: .black))
                                        .tracking(-0.3)
                                        .foregroundColor(VPalette.text)
                                    Text("\(vm.results.count) routes available now")
                                        .font(.system(size: 12)).foregroundColor(VPalette.textSec)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                        }

                        // Results
                        if vm.isSearching {
                            LoadingView().frame(height: 200)
                        } else if vm.results.isEmpty && (!vm.homeQuery.isEmpty || !vm.officeQuery.isEmpty) {
                            // Productive empty state — three concrete next
                            // steps instead of a dead-end "No routes found"
                            // message. Auto-expand widens the time window;
                            // Request route flags interest; Reset clears.
                            CommuteEmptyState(
                                onWiden: {
                                    vm.earliestTime = "06:00"
                                    vm.latestTime   = "10:00"
                                    vm.searchRoutes()
                                },
                                onRequest: {
                                    showRequestSheet = true
                                },
                                onReset: {
                                    vm.daysOfWeek = .weekdays
                                    vm.maxPriceMyr = nil
                                    vm.searchRoutes()
                                }
                            )
                            .padding(.horizontal, 16)
                        } else {
                            ForEach(Array(vm.results.enumerated()), id: \.element.id) { index, match in
                                PolishedRouteCard(
                                    match: match,
                                    accentSeed: index,
                                    onTap: { onOpenRoute(match.route.id) },
                                    // Hide the star on the driver's own
                                    // routes — favouriting yourself is
                                    // meaningless and surfaces in the
                                    // Favorites list as noise.
                                    onToggleFavorite: match.route.driverId == store.currentUser.id ? nil : {
                                        Task { await store.toggleFavorite(routeId: match.route.id) }
                                    },
                                    onShare: {
                                        shareRoute(match.route)
                                    },
                                    // Walk pill only shown when the rider
                                    // supplied home coords — otherwise
                                    // `pickupDistanceMeters` is the
                                    // backend fallback constant (1200m).
                                    hasRealPickupDistance: vm.hasRealHomeCoord
                                )
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.bottom, VTabBarLayout.clearance)
                }
                .refreshable {
                    await store.refreshAll()
                    vm.searchRoutes()
                }
                .onReceive(NotificationCenter.default.publisher(for: .voygoTabReselected)) { note in
                    if (note.userInfo?["index"] as? Int) == 1 {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
                }
            }
        }
        .onAppear { vm.store = store }
        .task {
            // Hydrate saved search before the initial search runs so a
            // returning rider sees their corridor in the input fields
            // and gets their personalised results, not the demo defaults.
            await vm.restoreSavedSearch()
            vm.searchRoutes()
        }
        .sheet(isPresented: $showRequestSheet) {
            RequestRouteSheet(
                initialOrigin: vm.homeQuery,
                initialDestination: vm.officeQuery,
                initialDays: vm.daysOfWeek,
                initialOriginLat: vm.selectedHomeLat,
                initialOriginLng: vm.selectedHomeLng,
                initialDestLat:   vm.selectedOfficeLat,
                initialDestLng:   vm.selectedOfficeLng,
                onSubmit: { payload in
                    let result = await store.postRouteRequest(payload)
                    if case .success = result { showRequestSheet = false }
                    return result
                }
            )
            .presentationDetents([.fraction(0.55), .large])
        }
    }

    /// Share-route handler — presents the system share sheet with a
    /// human-readable summary + a deep link the recipient can tap to
    /// open the same route in Voygo. Deep link uses the existing
    /// `voygo://` URL scheme (already registered for Billplz returns).
    private func shareRoute(_ route: RecurringRoute) {
        let deepLink = "voygo://routes/\(route.id)"
        let text = """
        \(route.startLocation) → \(route.endLocation) on Voygo
        \(route.departureTime) · RM \(route.pricePerSeat)/seat · driver \(route.driverName)
        \(deepLink)
        """
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController?
            .present(activity, animated: true)
    }

    private var homeHero: some View {
        let greetingName = store.currentUser.name.isEmpty ? "there" : store.currentUser.name.split(separator: " ").first.map(String.init) ?? "there"
        return VHeroGradient {
            VStack(alignment: .leading, spacing: 16) {
                // Back chevron — only shown when pushed (e.g. from Home).
                // When this view is a tab root, the chevron stays hidden.
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voygo")
                            .font(.system(size: 32, weight: .black))
                            .tracking(-0.8)
                            .foregroundColor(.white)
                        Text("\(timeAwareGreeting()), \(greetingName)")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.3)
                            .foregroundColor(.white.opacity(0.85))
                        Text("Find or offer recurring commute seats across Malaysia")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.95))
                            .frame(maxWidth: 240, alignment: .leading)
                            .padding(.top, 8)
                    }
                    Spacer()
                    Menu {
                        Button("My Subscriptions", action: onMySubscriptions)
                        Button("Create Route", action: onCreateRoute)
                        Button("Driver Dashboard", action: onDriverDashboard)
                    } label: {
                        VStack(spacing: 3) {
                            ForEach(0..<3) { _ in
                                Capsule().fill(.white).frame(width: 16, height: 2)
                            }
                        }
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.18))
                        .overlay(Circle().stroke(.white.opacity(0.25)))
                        .clipShape(Circle())
                    }
                }
                // Real counts (was hardcoded "12 routes / N / RM
                // local fares"). Reads `store.routes` for the catalog
                // size and the rider's active subs for the middle
                // pill. Average price comes from active routes; "—"
                // when we have nothing to average.
                HStack(spacing: 8) {
                    heroStat("\(store.routes.count)",                  label: "routes")
                    heroStat("\(activeSubscriptionsCount)",            label: "active rides")
                    heroStat(averageFareLabel,                          label: "avg fare")
                }
            }
            .padding(20)
        }
    }

    private var activeSubscriptionsCount: Int {
        store.subscriptions.filter { $0.status == .active }.count
    }

    private var averageFareLabel: String {
        let prices = store.routes.map(\.pricePerSeat).filter { $0 > 0 }
        guard !prices.isEmpty else { return "—" }
        let avg = prices.reduce(0, +) / prices.count
        return "RM \(avg)"
    }

    /// Time-of-day greeting in MYT (the device's current time zone). A
    /// rider opening the app at 9pm previously got "Good morning" which
    /// felt wrong.
    private func timeAwareGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hi"
        }
    }

    private func heroStat(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 14, weight: .black)).foregroundColor(.white)
            Text(label).font(.system(size: 10, weight: .heavy)).foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(.white.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var modeRail: some View {
        HStack(spacing: 8) {
            modeCard(icon: "mappin.circle.fill", title: "Find Ride", sub: "Match seats", color: VPalette.primary, action: {})
            modeCard(icon: "plus.circle.fill",   title: "Offer Ride", sub: "Share seats", color: VPalette.secondary, action: onCreateRoute)
            modeCard(icon: "car.fill",           title: "Driver",     sub: "Manage",     color: VPalette.accent,    action: onDriverDashboard)
        }
    }

    private func modeCard(icon: String, title: String, sub: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                VIconBubble(systemName: icon, color: color, size: 28, iconSize: 14)
                    .padding(.bottom, 4)
                Text(title).font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.text)
                Text(sub).font(.system(size: 10, weight: .semibold)).foregroundColor(VPalette.textHint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(color.opacity(0.2), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Polished route card (V-tokens; replaces the older RouteMatchCard visually)

struct PolishedRouteCard: View {
    let match: CommuteRouteMatchResult
    let accentSeed: Int
    let onTap: () -> Void
    /// Optional favorite-toggle handler. When provided, a star button
    /// appears in the corner; tapping it fires this without
    /// propagating to the card's main tap. Set to nil to hide the
    /// star (e.g. on the driver's own routes, where favouriting your
    /// own route makes no sense).
    var onToggleFavorite: (() -> Void)? = nil
    /// Optional share-this-route handler. Renders a small share icon
    /// next to the star.
    var onShare: (() -> Void)? = nil
    /// True when the rider supplied a home coordinate, so
    /// `pickupDistanceMeters` is a real measurement rather than the
    /// backend's fallback constant. When false we hide the walk pill
    /// so we don't show a fictional "1200m walk" number.
    var hasRealPickupDistance: Bool = true

    private var accent: Color {
        switch accentSeed % 3 {
        case 0: return VPalette.primary
        case 1: return VPalette.secondary
        default: return VPalette.accent
        }
    }

    /// Walk-distance band — colour-coded badge above the corridor.
    /// Green ≤500m, amber ≤1.5km, red beyond. Humans think in
    /// metres, not km, so we render as "350m" not "0.35 km".
    private var walkBand: (label: String, color: Color, accessibility: String) {
        let m = Int(match.pickupDistanceMeters)
        let label: String = m < 1000 ? "\(m)m walk" : String(format: "%.1fkm walk", Double(m)/1000.0)
        let color: Color = m <= 500 ? VPalette.success : (m <= 1500 ? VPalette.warning : VPalette.danger)
        return (label, color, "Pickup is \(m) metres from your home location")
    }

    /// "Why this route" one-liner — surfaces the strongest reason this
    /// card outranked the others. Replaces three small metric chips
    /// with one human sentence. Skips the walk distance when the
    /// rider hasn't supplied a home coord (we don't have a real
    /// number to report).
    private var whyThisRoute: String {
        let m = Int(match.pickupDistanceMeters)
        let onTime = Int(match.reliabilityScore * 100)
        let walkPart: String? = hasRealPickupDistance
            ? (m < 1000 ? "\(m)m walk" : String(format: "%.1fkm walk", Double(m)/1000.0))
            : nil
        let parts = [walkPart, "\(onTime)% on-time", "departs \(match.route.departureTime)"]
            .compactMap { $0 }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Walk-distance + favourite/share top strip. Walk-distance
                // is the headline metric the rider actually decides on —
                // but only show it when we actually have a real distance
                // (rider supplied a home coord). Without that, the
                // backend's fallback constant would lie to the user.
                HStack {
                    if hasRealPickupDistance {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.walk")
                                .font(.caption.weight(.bold))
                            Text(walkBand.label)
                                .font(.caption.weight(.heavy))
                        }
                        .foregroundColor(walkBand.color)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(walkBand.color.opacity(0.14))
                        .clipShape(Capsule())
                        .accessibilityLabel(walkBand.accessibility)
                    }
                    Spacer()
                    if let onShare {
                        Button(action: onShare) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundColor(VPalette.textSec)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if let onToggleFavorite {
                        Button(action: onToggleFavorite) {
                            Image(systemName: match.route.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundColor(match.route.isFavorite ? VPalette.starGold : VPalette.textHint)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .accessibilityLabel(match.route.isFavorite ? "Remove from favourites" : "Save to favourites")
                    }
                }

                HStack(spacing: 12) {
                    VAvatar(initial: String(match.route.driverName.prefix(1)), size: 42, accent: accent)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(match.route.driverName)
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(VPalette.text)
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill").font(.system(size: 11)).foregroundColor(VPalette.starGold)
                                Text("4.\(min(9, max(0, Int(match.reliabilityScore * 10))))")
                                    .font(.system(size: 11, weight: .bold)).foregroundColor(VPalette.text)
                            }
                        }
                        // Plate + colour when known so the rider can
                        // identify the vehicle at the pickup.
                        let plate = match.route.plateNumber
                        let colour = match.route.carColor
                        let carLine: String = {
                            var parts: [String] = [match.route.carType.label]
                            if let c = colour, !c.isEmpty { parts.append(c) }
                            if let p = plate,  !p.isEmpty { parts.append(p.uppercased()) }
                            return parts.joined(separator: " · ")
                        }()
                        Text(carLine)
                            .font(.system(size: 11)).foregroundColor(VPalette.textHint)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("RM \(match.route.pricePerSeat)")
                            .font(.system(size: 16, weight: .black)).tracking(-0.3)
                            .foregroundColor(VPalette.primary)
                        VKicker(text: "per ride", size: 9)
                    }
                }

                HStack(spacing: 10) {
                    VRouteGlyph(squareColor: accent).frame(width: 10)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(match.route.startLocation)
                            .font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                        Text(match.route.endLocation)
                            .font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(match.route.departureTime)
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(VPalette.text)
                        Text("\(Int(match.estimatedDetourMinutes)) min")
                            .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                    }
                }

                Rectangle().fill(VPalette.border).frame(height: 1)

                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill").font(.system(size: 12)).foregroundColor(VPalette.textSec)
                        let warning = match.availableSeats <= 1
                        (Text("\(match.availableSeats)").fontWeight(.heavy).foregroundColor(warning ? VPalette.warning : VPalette.success)
                         + Text(" of \(match.route.seatCount) seats left").foregroundColor(VPalette.textSec))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("View details").font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.primary)
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .heavy)).foregroundColor(VPalette.primary)
                    }
                }

                // "Why this route" rationale — one sentence summarising
                // the strongest signals the matcher picked up. Easier
                // to read than the three small metric chips this
                // replaced.
                Text(whyThisRoute)
                    .font(.system(size: 11))
                    .foregroundColor(VPalette.textHint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private enum CommuteSearchField: Hashable {
    case home
    case office
}

private struct MapsStyleCommuteSearchPanel: View {
    @Binding var homeQuery: String
    @Binding var officeQuery: String
    @Binding var earliestTime: String
    @Binding var latestTime: String
    let homeSuggestions: [PlaceSuggestion]
    let officeSuggestions: [PlaceSuggestion]
    let homeLoading: Bool
    let officeLoading: Bool
    let isSearching: Bool
    let isLocatingHome: Bool
    let errorMessage: String?
    let onHomeChange: (String) -> Void
    let onOfficeChange: (String) -> Void
    let onHomeSuggestionTap: (PlaceSuggestion) -> Void
    let onOfficeSuggestionTap: (PlaceSuggestion) -> Void
    let onUseCurrentLocation: () -> Void
    let onClearHome: () -> Void
    let onClearOffice: () -> Void
    let onSearch: () -> Void
    @FocusState private var focusedField: CommuteSearchField?

    private var activeSuggestions: [PlaceSuggestion] {
        focusedField == .office ? officeSuggestions : homeSuggestions
    }

    private var isActiveLoading: Bool {
        focusedField == .office ? officeLoading : homeLoading
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(VoygoTheme.cardBorder.opacity(0.75))
                .frame(width: 42, height: 5)

            HStack(alignment: .top, spacing: 12) {
                routeGlyph
                    .padding(.top, 19)

                VStack(spacing: 10) {
                    mapsSearchRow(
                        field: .home,
                        title: "From",
                        placeholder: "Home, current location, or pickup",
                        text: $homeQuery,
                        icon: "location.fill",
                        canClear: !homeQuery.isEmpty,
                        onClear: onClearHome
                    )
                    .onChange(of: homeQuery) { _, value in onHomeChange(value) }

                    mapsSearchRow(
                        field: .office,
                        title: "To",
                        placeholder: "Office or destination",
                        text: $officeQuery,
                        icon: "magnifyingglass",
                        canClear: !officeQuery.isEmpty,
                        onClear: onClearOffice
                    )
                    .onChange(of: officeQuery) { _, value in onOfficeChange(value) }
                }
            }

            if focusedField == .home {
                Button(action: onUseCurrentLocation) {
                    HStack(spacing: 10) {
                        if isLocatingHome {
                            ProgressView().tint(VoygoTheme.primary)
                        } else {
                            Image(systemName: "location.circle.fill")
                                .font(.title3)
                                .foregroundColor(VoygoTheme.primary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Current Location")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(VoygoTheme.textPrimary)
                            Text("Set your starting point from GPS")
                                .font(.caption)
                                .foregroundColor(VoygoTheme.textHint)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(VoygoTheme.primaryContainer.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(isLocatingHome)
            }

            suggestionContent

            HStack(spacing: 10) {
                CompactTimeField(title: "Earliest", text: $earliestTime, placeholder: "07:00")
                CompactTimeField(title: "Latest", text: $latestTime, placeholder: "09:30")
            }

            PrimaryButton("Search Routes", isLoading: isSearching, action: onSearch)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(VoygoTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(VoygoTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(VoygoTheme.cardBorder.opacity(0.55), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)
        )
    }

    private var routeGlyph: some View {
        VStack(spacing: 5) {
            Circle()
                .fill(VoygoTheme.success)
                .frame(width: 10, height: 10)
            Rectangle()
                .fill(VoygoTheme.cardBorder)
                .frame(width: 2, height: 42)
            RoundedRectangle(cornerRadius: 3)
                .fill(VoygoTheme.primary)
                .frame(width: 11, height: 11)
        }
        .frame(width: 18)
    }

    @ViewBuilder
    private var suggestionContent: some View {
        if isActiveLoading {
            HStack(spacing: 10) {
                ProgressView().tint(VoygoTheme.primary)
                Text("Searching nearby places")
                    .font(.subheadline)
                    .foregroundColor(VoygoTheme.textSecondary)
                Spacer()
            }
            .padding(14)
            .background(VoygoTheme.surfaceHigh.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if !activeSuggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(activeSuggestions) { suggestion in
                    Button {
                        if focusedField == .office {
                            onOfficeSuggestionTap(suggestion)
                        } else {
                            onHomeSuggestionTap(suggestion)
                        }
                        focusedField = nil
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundColor(VoygoTheme.primary)
                            Text(suggestion.displayName)
                                .font(.subheadline)
                                .foregroundColor(VoygoTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if suggestion.id != activeSuggestions.last?.id {
                        Divider().background(VoygoTheme.cardBorder).padding(.leading, 48)
                    }
                }
            }
            .background(VoygoTheme.surfaceHigh.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func mapsSearchRow(
        field: CommuteSearchField,
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        canClear: Bool,
        onClear: @escaping () -> Void
    ) -> some View {
        let isFocused = focusedField == field

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(isFocused ? VoygoTheme.primary : VoygoTheme.textHint)
                TextField(placeholder, text: text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(VoygoTheme.textPrimary)
                    .focused($focusedField, equals: field)
                    .submitLabel(field == .home ? .next : .search)
                    .onSubmit {
                        if field == .home {
                            focusedField = .office
                        } else {
                            focusedField = nil
                            onSearch()
                        }
                    }
                    .tint(VoygoTheme.primary)
            }

            if canClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(VoygoTheme.textHint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title)")
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(VoygoTheme.textHint)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .background(isFocused ? VoygoTheme.primaryContainer.opacity(0.75) : VoygoTheme.surfaceHigh.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(
            RoundedRectangle(cornerRadius: 17)
                .stroke(isFocused ? VoygoTheme.primary.opacity(0.65) : Color.clear, lineWidth: 1.5)
        )
    }
}

private struct CompactTimeField: View {
    let title: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(VoygoTheme.textHint)
            TextField(placeholder, text: $text)
                .font(.subheadline.weight(.semibold))
                .keyboardType(.numbersAndPunctuation)
                .foregroundColor(VoygoTheme.textPrimary)
                .tint(VoygoTheme.primary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(VoygoTheme.surfaceHigh.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct RouteMatchCard: View {
    let match: CommuteRouteMatchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VoygoCard {
                VStack(spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(match.route.startLocation) → \(match.route.endLocation)")
                                .font(.headline).foregroundColor(VoygoTheme.textPrimary)
                            Text("Driver: \(match.route.driverName)")
                                .font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("RM \(match.route.pricePerSeat)")
                                .font(.title3.bold()).foregroundColor(VoygoTheme.primary)
                            Text("per seat").font(.caption2).foregroundColor(VoygoTheme.textHint)
                        }
                    }

                    Divider().background(VoygoTheme.cardBorder)

                    HStack(spacing: 0) {
                        MetricChip(icon: "clock.fill", value: match.route.departureTime, label: "Departure")
                        Spacer()
                        MetricChip(icon: "location.fill", value: "\(Int(match.pickupDistanceMeters)) m", label: "Pickup dist")
                        Spacer()
                        MetricChip(icon: "person.2.fill", value: "\(match.availableSeats)", label: "Seats left")
                        Spacer()
                        MetricChip(icon: "star.fill", value: "\(Int(match.reliabilityScore * 100))%", label: "Reliability")
                    }

                    // Reliability bar
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Route overlap").font(.caption2).foregroundColor(VoygoTheme.textHint)
                            Spacer()
                            Text("\(Int(match.routeOverlapScore * 100))%").font(.caption2.bold()).foregroundColor(VoygoTheme.primary)
                        }
                        ReliabilityBar(value: match.routeOverlapScore)
                    }

                    HStack {
                        Image(systemName: match.route.carType.icon).foregroundColor(VoygoTheme.accent).font(.caption)
                        Text(match.route.carType.label).font(.caption).foregroundColor(VoygoTheme.textSecondary)
                        Spacer()
                        Text(match.route.daysOfWeek.shortLabel).font(.caption2).foregroundColor(VoygoTheme.textHint)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MetricChip: View {
    let icon: String; let value: String; let label: String
    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundColor(VoygoTheme.primary)
            Text(value).font(.caption.bold()).foregroundColor(VoygoTheme.textPrimary)
            Text(label).font(.caption2).foregroundColor(VoygoTheme.textHint)
        }
    }
}

// MARK: - Popular corridors row

struct PopularCorridorsRow: View {
    let corridors: [PopularCorridor]
    let onTap: (PopularCorridor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundColor(VPalette.primary)
                Text("Popular Penang corridors")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(VPalette.textSec)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(corridors) { corridor in
                        Button { onTap(corridor) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "location.north.fill")
                                    .font(.caption2.weight(.heavy))
                                Text("\(corridor.origin) → \(corridor.destination)")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(VPalette.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(VPalette.primaryContainer)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Filters bar (day-of-week + price cap + sort)

struct CommuteFiltersBar: View {
    @Binding var days: DaysOfWeekFlags
    @Binding var maxPriceMyr: Int?
    @Binding var sortBy: CommuteSortOption
    /// `changedSort = true` means the rider tapped a sort chip and we
    /// can re-sort locally; otherwise we need a fresh server search.
    let onChange: (_ changedSort: Bool) -> Void

    @State private var priceCapEnabled: Bool = false
    @State private var priceCap: Double = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("RUN ON")
            HStack(spacing: 6) {
                dayChip("M", binding: $days.monday)
                dayChip("T", binding: $days.tuesday)
                dayChip("W", binding: $days.wednesday)
                dayChip("T", binding: $days.thursday)
                dayChip("F", binding: $days.friday)
                dayChip("S", binding: $days.saturday)
                dayChip("S", binding: $days.sunday)
            }

            sectionLabel("BUDGET")
            HStack(spacing: 8) {
                Toggle(isOn: $priceCapEnabled) { Text("Cap").font(.caption.weight(.semibold)) }
                    .toggleStyle(.switch).tint(VPalette.primary)
                    .fixedSize()
                if priceCapEnabled {
                    Slider(value: $priceCap, in: 5...50, step: 1)
                        .tint(VPalette.primary)
                    Text("RM \(Int(priceCap))")
                        .font(.caption.weight(.heavy)).foregroundColor(VPalette.primary)
                        .frame(width: 50, alignment: .trailing)
                } else {
                    Text("Any price")
                        .font(.caption).foregroundColor(VPalette.textHint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onChange(of: priceCapEnabled) { _, on in
                maxPriceMyr = on ? Int(priceCap) : nil
                onChange(false)
            }
            .onChange(of: priceCap) { _, value in
                if priceCapEnabled {
                    maxPriceMyr = Int(value)
                    onChange(false)
                }
            }

            sectionLabel("SORT BY")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CommuteSortOption.allCases) { option in
                        Button { sortBy = option; onChange(true) } label: {
                            Text(option.rawValue)
                                .font(.caption.weight(.heavy))
                                .foregroundColor(sortBy == option ? .white : VPalette.text)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(sortBy == option ? VPalette.primary : VPalette.surfaceHigh)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.2)
            .foregroundColor(VPalette.textHint)
    }

    private func dayChip(_ label: String, binding: Binding<Bool>) -> some View {
        Button {
            binding.wrappedValue.toggle()
            onChange(false)
        } label: {
            Text(label)
                .font(.caption.weight(.heavy))
                .foregroundColor(binding.wrappedValue ? .white : VPalette.text)
                .frame(width: 32, height: 32)
                .background(binding.wrappedValue ? VPalette.primary : VPalette.surfaceHigh)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state with three productive next steps

struct CommuteEmptyState: View {
    let onWiden: () -> Void
    let onRequest: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "map")
                .font(.system(size: 40, weight: .semibold))
                .foregroundColor(VPalette.textHint)
            Text("No routes for that exact corridor — yet")
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(VPalette.text)
                .multilineTextAlignment(.center)
            Text("Penang's pilot still has gaps. Try one of these:")
                .font(.caption)
                .foregroundColor(VPalette.textSec)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                VPrimaryButton("Tell drivers I want this corridor",
                               icon: "hand.raised.fill",
                               action: onRequest)
                Button(action: onWiden) {
                    Text("Try a wider time window (06:00–10:00)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(VPalette.primary)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(VPalette.primaryContainer)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                Button(action: onReset) {
                    Text("Reset filters")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(VPalette.textSec)
                }.buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(VPalette.border))
    }
}

// MARK: - Request a route sheet

struct RequestRouteSheet: View {
    let initialOrigin: String
    let initialDestination: String
    let initialDays: DaysOfWeekFlags
    /// Initial coords from the rider's current search — when present
    /// we pass them through to the backend so corridor matching can
    /// use coord distance later instead of relying on substring on
    /// labels alone. Optional — labels still work.
    var initialOriginLat: Double? = nil
    var initialOriginLng: Double? = nil
    var initialDestLat: Double? = nil
    var initialDestLng: Double? = nil
    let onSubmit: (RouteRequestPayload) async -> Result<String, AppError>

    @Environment(\.dismiss) private var dismiss
    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var preferredTime: String = "07:30"
    @State private var days: DaysOfWeekFlags = .weekdays
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var error: String? = nil

    private var canSubmit: Bool {
        !origin.trimmingCharacters(in: .whitespaces).isEmpty &&
        !destination.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Request a route")
                    .font(.system(size: 20, weight: .black))
                    .tracking(-0.4)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(VPalette.textSec)
                        .frame(width: 32, height: 32)
                        .background(VPalette.surfaceHigh)
                        .clipShape(Circle())
                }.buttonStyle(.plain)
            }
            Text("Tell drivers about this corridor. We'll notify you the moment one of them adds a matching route.")
                .font(.caption).foregroundColor(VPalette.textSec)

            field(label: "FROM", text: $origin)
            field(label: "TO",   text: $destination)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREFERRED TIME").font(.system(size: 10, weight: .heavy))
                        .tracking(1.2).foregroundColor(VPalette.textHint)
                    TextField("07:30", text: $preferredTime)
                        .padding(10).background(VPalette.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAYS").font(.system(size: 10, weight: .heavy))
                        .tracking(1.2).foregroundColor(VPalette.textHint)
                    Text(days.shortLabel).font(.caption.weight(.semibold))
                        .padding(10).background(VPalette.surfaceHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(1...3)
                .padding(10).background(VPalette.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if let error {
                Text(error).font(.caption.weight(.semibold)).foregroundColor(VPalette.danger)
            }

            VPrimaryButton("Send request",
                           icon: "paperplane.fill",
                           isLoading: isSubmitting,
                           isEnabled: canSubmit) {
                Task { await submit() }
            }
        }
        .padding(20)
        .onAppear {
            origin = initialOrigin
            destination = initialDestination
            days = initialDays
        }
    }

    private func field(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .heavy))
                .tracking(1.2).foregroundColor(VPalette.textHint)
            TextField("", text: text)
                .padding(10).background(VPalette.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .textInputAutocapitalization(.words)
        }
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        let payload = RouteRequestPayload(
            origin: origin.trimmingCharacters(in: .whitespaces),
            destination: destination.trimmingCharacters(in: .whitespaces),
            originLat: initialOriginLat,
            originLng: initialOriginLng,
            destLat:   initialDestLat,
            destLng:   initialDestLng,
            preferredTime: preferredTime,
            daysOfWeek: days.asDictionary,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let result = await onSubmit(payload)
        isSubmitting = false
        if case .failure(let err) = result { error = err.localizedDescription }
    }
}
