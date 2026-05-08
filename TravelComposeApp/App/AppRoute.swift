import SwiftUI

// MARK: - AppRoute (single source of truth for in-app navigation)
//
// Previously each tab (Home, Commute, Trips) defined its own `Route`
// enum, which meant Home couldn't push `.routeDetails(id)` without
// duplicating CommuteTab's enum. One shared enum here lets any tab
// route to any destination, and is the foundation for deep linking
// (`voygo://routes/<id>`) — that work simply parses a URL into an
// `AppRoute` and appends it to the active tab's path.
//
// Each `NavigationStack` still owns its own `[AppRoute]` path; the
// tabs aren't merging state, just sharing a destination vocabulary.
//
// The matching destination switch lives in `AppRouteDestinations` so
// every tab can opt into the full surface with one modifier.

enum AppRoute: Hashable {
    case findRides
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

// MARK: - Shared destination builder
//
// Hosts the `.navigationDestination(for: AppRoute.self)` map so each
// tab opts in once instead of duplicating the switch. Feeds bindings
// for the search-filters state down to `SearchFiltersView`, which
// CommuteTab still owns (filters are tab-local and pinned by the tab
// because `SearchFiltersView` mutates them through `@Binding`s).

struct AppRouteDestinations: ViewModifier {
    @Binding var path: [AppRoute]
    @Binding var filtersQuery: String
    @Binding var filtersEarliest: String
    @Binding var filtersLatest: String
    @Binding var filtersDays: DaysOfWeekFlags

    func body(content: Content) -> some View {
        content.navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .findRides:
                FindCommuteRoutesView(
                    onOpenRoute:       { path.append(.routeDetails(routeId: $0)) },
                    onMySubscriptions: { path.append(.mySubscriptions) },
                    onCreateRoute:     { path.append(.createRoute) },
                    onDriverDashboard: { path.append(.driverDashboard) }
                )
                .navigationBarHidden(true)

            case .routeDetails(let id):
                RouteDetailsView(
                    routeId: id,
                    onBack: { if !path.isEmpty { path.removeLast() } },
                    onSubscribed: { bookingId in
                        // Land on the celebratory confirmation screen.
                        let routeName = "USJ 9 LRT"
                        let driverName = "your driver"
                        path.append(.bookingConfirmed(
                            bookingId: bookingId,
                            pickup: routeName,
                            driverName: driverName
                        ))
                    }
                )
                .navigationBarHidden(true)

            case .mySubscriptions:
                MySubscriptionsView(
                    onOpenRoute: { path.append(.routeDetails(routeId: $0)) },
                    onOpenCalendar: { path.append(.calendar()) },
                    onBack: { if !path.isEmpty { path.removeLast() } }
                )
                .navigationBarHidden(true)

            case .calendar(let routeId):
                UpcomingCalendarView(
                    routeId: routeId,
                    onBack: { if !path.isEmpty { path.removeLast() } }
                )
                .navigationBarHidden(true)

            case .createRoute:
                CreateRouteView(
                    onBack: { if !path.isEmpty { path.removeLast() } },
                    onCreated: { id in
                        // Pop to root and open the freshly-created route.
                        path = [.routeDetails(routeId: id)]
                    }
                )
                .navigationBarHidden(true)

            case .driverDashboard:
                DriverDashboardView(
                    onBack:         { if !path.isEmpty { path.removeLast() } },
                    onOpenCalendar: { path.append(.driverCalendar(routeId: $0)) },
                    onOpenPayouts:  { path.append(.driverPayouts) }
                )
                .navigationBarHidden(true)

            case .driverCalendar(let routeId):
                UpcomingCalendarView(
                    routeId: routeId,
                    onBack: { if !path.isEmpty { path.removeLast() } }
                )
                .navigationBarHidden(true)

            case .driverPayouts:
                DriverPayoutsView(
                    onBack: { if !path.isEmpty { path.removeLast() } }
                )
                .navigationBarHidden(true)

            case .liveTrip(let id, let isDriver):
                LiveTripView(
                    tripId: id,
                    isDriver: isDriver,
                    onBack: { if !path.isEmpty { path.removeLast() } },
                    onMessageDriver: nil,
                    onEndTrip: {
                        path.append(.rateRide(
                            driverInitial: "A",
                            driverName: "Aiman",
                            summary: "Subang Jaya → KLCC"
                        ))
                    }
                )
                .navigationBarHidden(true)

            case .bookingConfirmed(let bookingId, let pickup, let driverName):
                BookingConfirmedView(
                    bookingId: bookingId,
                    pickup: pickup,
                    driverName: driverName,
                    onViewReceipt: {
                        // Receipt lives under Profile's nav stack; bounce
                        // back to root for now.
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
                    onApply: { if !path.isEmpty { path.removeLast() } },
                    onBack:  { if !path.isEmpty { path.removeLast() } }
                )
                .navigationBarHidden(true)
            }
        }
    }
}

extension View {
    /// Convenience: opt this NavigationStack into the full AppRoute map.
    /// All four filter bindings come along even when a tab doesn't host
    /// SearchFilters — the cost is one stored binding, not a re-render.
    func appRouteDestinations(
        path: Binding<[AppRoute]>,
        filtersQuery: Binding<String>,
        filtersEarliest: Binding<String>,
        filtersLatest: Binding<String>,
        filtersDays: Binding<DaysOfWeekFlags>
    ) -> some View {
        modifier(AppRouteDestinations(
            path: path,
            filtersQuery: filtersQuery,
            filtersEarliest: filtersEarliest,
            filtersLatest: filtersLatest,
            filtersDays: filtersDays
        ))
    }
}

private func dateLabelToday() -> String {
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    return f.string(from: Date())
}
