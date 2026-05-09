import SwiftUI
import CoreLocation

// MARK: - Find Commute Routes (mirrors FindCommuteRoutesScreen.kt)

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
    var results: [CommuteRouteMatchResult] = []
    var isSearching = false
    var isLocatingHome = false
    var errorMessage: String? = nil

    private var selectedHomeLat: Double? = nil
    private var selectedHomeLng: Double? = nil
    private var selectedOfficeLat: Double? = nil
    private var selectedOfficeLng: Double? = nil
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
                officeLng: selectedOfficeLng
            )
            self.results = results
            self.isSearching = false
        }
    }

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
                            EmptyStateView(icon: "map.fill", title: "No routes found",
                                           subtitle: "Try adjusting your locations or departure window")
                                .frame(height: 220)
                        } else {
                            ForEach(Array(vm.results.enumerated()), id: \.element.id) { index, match in
                                PolishedRouteCard(match: match, accentSeed: index, onTap: { onOpenRoute(match.route.id) })
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
        .onAppear { vm.store = store; vm.searchRoutes() }
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

    private var accent: Color {
        switch accentSeed % 3 {
        case 0: return VPalette.primary
        case 1: return VPalette.secondary
        default: return VPalette.accent
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
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
                        Text("\(match.route.carType.label) · \(Int(match.reliabilityScore * 100))% on-time")
                            .font(.system(size: 11)).foregroundColor(VPalette.textHint)
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
