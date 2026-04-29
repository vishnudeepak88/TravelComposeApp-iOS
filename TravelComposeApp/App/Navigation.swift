import SwiftUI

// MARK: - Root Navigation

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var authStep: AuthStep = .phone

    enum AuthStep: Equatable { case phone, otp(phone: String) }

    var body: some View {
        if store.isAuthenticated {
            MainTabView()
        } else {
            switch authStep {
            case .phone:
                AuthPhoneView { _ in
                    authStep = .otp(phone: store.phoneNumber)
                }
            case .otp(let phone):
                AuthOtpView(phoneNumber: phone, onBack: {
                    authStep = .phone
                })
            }
        }
    }
}

// MARK: - Main Tab Bar

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: CommuteTab()
                case 1: TripsTab()
                case 2: InboxView()
                case 3: ProfileView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            VoygoTabBar(selectedIndex: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            if let message = store.connectionState.bannerText {
                SyncStatusBanner(message: message, isOffline: store.connectionState.isOffline)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.connectionState)
        .task {
            await store.refreshAll()
        }
    }
}

private struct SyncStatusBanner: View {
    let message: String
    let isOffline: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isOffline {
                Image(systemName: "wifi.slash")
                    .font(.caption.weight(.bold))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(VoygoTheme.primary)
            }
            Text(message)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundColor(isOffline ? VoygoTheme.warning : VoygoTheme.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(VoygoTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((isOffline ? VoygoTheme.warning : VoygoTheme.primary).opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

struct VoygoTabBar: View {
    @Binding var selectedIndex: Int

    private let items: [(icon: String, selectedIcon: String, label: String)] = [
        ("car",          "car.fill",           "Routes"),
        ("calendar",     "calendar",           "Calendar"),
        ("bubble.left",  "bubble.left.fill",   "Inbox"),
        ("person",       "person.fill",        "Profile")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedIndex = i } }) {
                    VStack(spacing: 5) {
                        Image(systemName: selectedIndex == i ? item.selectedIcon : item.icon)
                            .font(.system(size: 20, weight: selectedIndex == i ? .semibold : .regular))
                            .foregroundColor(selectedIndex == i ? VoygoTheme.onPrimaryContainer : VoygoTheme.textHint)
                            .frame(width: 56, height: 32)
                            .background(
                                Capsule()
                                    .fill(selectedIndex == i ? VoygoTheme.primaryContainer : .clear)
                            )
                        Text(item.label)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(selectedIndex == i ? VoygoTheme.textPrimary : VoygoTheme.textHint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 24)
        .background(
            VoygoTheme.surface
                .overlay(Rectangle().fill(VoygoTheme.cardBorder.opacity(0.5)).frame(height: 1), alignment: .top)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
    }
}

// MARK: - Commute Tab Navigator

struct CommuteTab: View {
    @State private var path: [CommuteRoute] = []
    /// Persistent filter state owned by the tab so SearchFilters can
    /// actually write back. Previously each presentation created throw-
    /// away `Binding(get: { … }, set: { _ in })` placeholders that
    /// silently discarded edits.
    @State private var filtersQuery: String = "Subang Jaya → KLCC"
    @State private var filtersEarliest: String = "06:30"
    @State private var filtersLatest: String = "09:00"
    @State private var filtersDays: DaysOfWeekFlags = .weekdays

    enum CommuteRoute: Hashable {
        case routeDetails(routeId: String)
        case mySubscriptions
        case calendar(routeId: String? = nil)
        case createRoute
        case driverDashboard
        case driverCalendar(routeId: String)
        case driverPayouts
        case liveTrip(tripId: String, isDriver: Bool)
        case bookingConfirmed(bookingId: String, pickup: String, driverName: String)
        case rateRide(driverInitial: String, driverName: String, summary: String)
        case searchFilters
    }

    var body: some View {
        NavigationStack(path: $path) {
            FindCommuteRoutesView(
                onOpenRoute:       { path.append(.routeDetails(routeId: $0)) },
                onMySubscriptions: { path.append(.mySubscriptions) },
                onCreateRoute:     { path.append(.createRoute) },
                onDriverDashboard: { path.append(.driverDashboard) }
            )
            .navigationDestination(for: CommuteRoute.self) { route in
                switch route {
                case .routeDetails(let id):
                    RouteDetailsView(
                        routeId: id,
                        onBack: { path.removeLast() },
                        onSubscribed: { bookingId in
                            // Push the celebratory confirmation screen on success.
                            let routeName = "USJ 9 LRT"
                            let driverName = "your driver"
                            path.append(.bookingConfirmed(bookingId: bookingId, pickup: routeName, driverName: driverName))
                        }
                    )
                    .navigationBarHidden(true)

                case .mySubscriptions:
                    MySubscriptionsView(
                        onOpenRoute: { path.append(.routeDetails(routeId: $0)) },
                        onOpenCalendar: { path.append(.calendar()) },
                        onBack: { path.removeLast() }
                    )
                    .navigationBarHidden(true)

                case .calendar(let routeId):
                    UpcomingCalendarView(routeId: routeId, onBack: { path.removeLast() })
                        .navigationBarHidden(true)

                case .createRoute:
                    CreateRouteView(
                        onBack: { path.removeLast() },
                        onCreated: { id in
                            // pop back to root and open created route
                            path = [.routeDetails(routeId: id)]
                        }
                    )
                    .navigationBarHidden(true)

                case .driverDashboard:
                    DriverDashboardView(
                        onBack:         { path.removeLast() },
                        onOpenCalendar: { path.append(.driverCalendar(routeId: $0)) },
                        onOpenPayouts:  { path.append(.driverPayouts) }
                    )
                    .navigationBarHidden(true)

                case .driverCalendar(let routeId):
                    UpcomingCalendarView(routeId: routeId, onBack: { path.removeLast() })
                        .navigationBarHidden(true)

                case .driverPayouts:
                    DriverPayoutsView(onBack: { path.removeLast() })
                        .navigationBarHidden(true)

                case .liveTrip(let id, let isDriver):
                    LiveTripView(
                        tripId: id,
                        isDriver: isDriver,
                        onBack: { path.removeLast() },
                        onMessageDriver: nil,
                        onEndTrip: {
                            path.append(.rateRide(driverInitial: "A", driverName: "Aiman", summary: "Subang Jaya → KLCC"))
                        }
                    )
                    .navigationBarHidden(true)

                case .bookingConfirmed(let bookingId, let pickup, let driverName):
                    BookingConfirmedView(
                        bookingId: bookingId,
                        pickup: pickup,
                        driverName: driverName,
                        onViewReceipt: {
                            // Receipt lives under Profile's nav stack; clear back to root for now.
                            path = []
                        },
                        onSeeSubscription: {
                            path = [.mySubscriptions]
                        }
                    )
                    .navigationBarHidden(true)

                case .rateRide(let init_, let name, let summary):
                    RateRideView(
                        driverInitial: init_,
                        driverName: name,
                        routeSummary: summary,
                        dateLabel: dateLabelToday(),
                        durationLabel: "52 min",
                        onSubmit: { _, _, _ in path = [] },
                        onSkip: { path = [] }
                    )
                    .navigationBarHidden(true)

                case .searchFilters:
                    SearchFiltersView(
                        routeQuery: $filtersQuery,
                        earliest:   $filtersEarliest,
                        latest:     $filtersLatest,
                        days:       $filtersDays,
                        onApply: { path.removeLast() },
                        onBack:  { path.removeLast() }
                    )
                    .navigationBarHidden(true)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

private func dateLabelToday() -> String {
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    return f.string(from: Date())
}

// MARK: - Commutes Tab Navigator

struct TripsTab: View {
    @State private var path: [TripsRoute] = []

    enum TripsRoute: Hashable {
        case routeDetails(routeId: String)
        case calendar(routeId: String? = nil)
    }

    var body: some View {
        NavigationStack(path: $path) {
            MySubscriptionsView(
                onOpenRoute: { path.append(.routeDetails(routeId: $0)) },
                onOpenCalendar: { path.append(.calendar()) },
                onBack: nil
            )
            .navigationDestination(for: TripsRoute.self) { route in
                switch route {
                case .routeDetails(let id):
                    RouteDetailsView(routeId: id, onBack: { path.removeLast() })
                        .navigationBarHidden(true)
                case .calendar(let routeId):
                    UpcomingCalendarView(routeId: routeId, onBack: { path.removeLast() })
                        .navigationBarHidden(true)
                }
            }
            .navigationBarHidden(true)
        }
    }
}
