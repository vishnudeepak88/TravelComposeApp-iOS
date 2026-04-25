import SwiftUI
import Combine

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
    @Published var errorMessage: String? = nil

    private var selectedHomeLat: Double? = nil
    private var selectedHomeLng: Double? = nil
    private var selectedOfficeLat: Double? = nil
    private var selectedOfficeLng: Double? = nil

    private var homeTask: Task<Void, Never>? = nil
    private var officeTask: Task<Void, Never>? = nil

    var store: AppStore?

    func onHomeQueryChange(_ q: String) {
        homeQuery = q
        selectedHomeLat = nil; selectedHomeLng = nil
        homeTask?.cancel()
        guard q.count >= 2 else { homeSuggestions = []; return }
        homeLoading = true
        homeTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            if let results = try? await VoygoAPIClient.autocompletePlaces(query: q, lat: nil, lon: nil) {
                homeSuggestions = results
            }
            homeLoading = false
        }
    }

    func onOfficeQueryChange(_ q: String) {
        officeQuery = q
        selectedOfficeLat = nil; selectedOfficeLng = nil
        officeTask?.cancel()
        guard q.count >= 2 else { officeSuggestions = []; return }
        officeLoading = true
        officeTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            if let results = try? await VoygoAPIClient.autocompletePlaces(query: q, lat: nil, lon: nil) {
                officeSuggestions = results
            }
            officeLoading = false
        }
    }

    func selectHome(_ s: PlaceSuggestion) {
        homeQuery = s.displayName; selectedHomeLat = s.lat; selectedHomeLng = s.lon
        homeSuggestions = []
    }
    func selectOffice(_ s: PlaceSuggestion) {
        officeQuery = s.displayName; selectedOfficeLat = s.lat; selectedOfficeLng = s.lon
        officeSuggestions = []
    }
    func clearDropdowns() { homeSuggestions = []; officeSuggestions = [] }

    func searchRoutes() {
        guard let store else { return }
        isSearching = true
        errorMessage = nil
        clearDropdowns()
        let earliest = parseMinutes(earliestTime) ?? 7*60
        let latest   = parseMinutes(latestTime)   ?? 9*60+30
        let results  = CommuteMatchingEngine.matchRoutes(
            riderId: store.riderId, homeLocation: homeQuery, officeLocation: officeQuery,
            homeLat: selectedHomeLat, homeLng: selectedHomeLng,
            officeLat: selectedOfficeLat, officeLng: selectedOfficeLng,
            earliestMinutes: earliest, latestMinutes: latest,
            routes: store.routes, subscriptions: store.subscriptions, rideInstances: store.rideInstances
        )
        self.results = results
        isSearching = false
    }

    private func parseMinutes(_ t: String) -> Int? {
        let p = t.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }
}

struct FindCommuteRoutesView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var vm = FindCommuteRoutesViewModel()
    var onOpenRoute: (String) -> Void
    var onMySubscriptions: () -> Void
    var onCreateRoute: () -> Void
    var onDriverDashboard: () -> Void

    @State private var showMenu = false

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
                        // Search form
                        VoygoCard {
                            VStack(spacing: 14) {
                                PlaceAutocompleteField(label: "Home Location", text: $vm.homeQuery,
                                                       suggestions: vm.homeSuggestions, isLoading: vm.homeLoading,
                                                       onSuggestionTap: vm.selectHome)
                                    .onChange(of: vm.homeQuery) { _, v in vm.onHomeQueryChange(v) }

                                Divider().background(VoygoTheme.cardBorder)

                                PlaceAutocompleteField(label: "Office / Destination", text: $vm.officeQuery,
                                                       suggestions: vm.officeSuggestions, isLoading: vm.officeLoading,
                                                       onSuggestionTap: vm.selectOffice)
                                    .onChange(of: vm.officeQuery) { _, v in vm.onOfficeQueryChange(v) }

                                HStack(spacing: 12) {
                                    VoygoTextField(label: "Earliest", text: $vm.earliestTime, placeholder: "07:00")
                                    VoygoTextField(label: "Latest",   text: $vm.latestTime,   placeholder: "09:30")
                                }
                                PrimaryButton("Search Recurring Routes", isLoading: vm.isSearching) {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    vm.searchRoutes()
                                }
                            }
                            .padding(16)
                        }
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
            }
        }
        .onAppear { vm.store = store; vm.searchRoutes() }
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
