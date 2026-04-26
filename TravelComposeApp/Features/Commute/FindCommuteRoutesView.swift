import SwiftUI
import Combine
import CoreLocation

// MARK: - Find Commute Routes (mirrors FindCommuteRoutesScreen.kt)

@MainActor
final class FindCommuteRoutesViewModel: ObservableObject {
    @Published var homeQuery = ""
    @Published var officeQuery = ""
    @Published var homeSuggestions: [PlaceSuggestion] = []
    @Published var officeSuggestions: [PlaceSuggestion] = []
    @Published var homeLoading = false
    @Published var officeLoading = false
    @Published var earliestTime = "07:00"
    @Published var latestTime   = "09:30"
    @Published var results: [CommuteRouteMatchResult] = []
    @Published var isSearching = false
    @Published var isLocatingHome = false
    @Published var errorMessage: String? = nil

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
    @EnvironmentObject var store: AppStore
    @StateObject private var vm = FindCommuteRoutesViewModel()
    var onOpenRoute: (String) -> Void
    var onMySubscriptions: () -> Void
    var onCreateRoute: () -> Void
    var onDriverDashboard: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                VoygoNavBar(
                    title: "Find Commute Routes",
                    trailingContent: AnyView(
                        Menu {
                            Button("My Subscriptions", action: onMySubscriptions)
                            Button("Create Route", action: onCreateRoute)
                            Button("Driver Dashboard", action: onDriverDashboard)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(VoygoTheme.textPrimary)
                                .frame(width: 44, height: 44)
                        }
                    )
                )

                ScrollView {
                    VStack(spacing: 14) {
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
                        .padding(.horizontal, 16).padding(.top, 16)

                        // Results
                        if vm.isSearching {
                            LoadingView().frame(height: 200)
                        } else if vm.results.isEmpty && (!vm.homeQuery.isEmpty || !vm.officeQuery.isEmpty) {
                            EmptyStateView(icon: "map.fill", title: "No routes found",
                                           subtitle: "Try adjusting your locations or departure window")
                                .frame(height: 220)
                        } else {
                            ForEach(vm.results) { match in
                                RouteMatchCard(match: match, onTap: { onOpenRoute(match.route.id) })
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.bottom, 108)
                }
                .refreshable {
                    await store.refreshAll()
                    vm.searchRoutes()
                }
            }
        }
        .onAppear { vm.store = store; vm.searchRoutes() }
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
