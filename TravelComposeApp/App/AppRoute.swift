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
    case rateRide(rideInstanceId: String?, routeId: String?, driverId: String?, driverInitial: String, driverName: String, summary: String)
    case chatThread(threadId: String, title: String)
    case searchFilters
    // Profile-tab destinations — folded in here so all four tabs share
    // one destination vocabulary and a future deep link can route to
    // any of these from any tab.
    case wallet
    case tripHistory
    case notifications
    case receipt(id: String)
    case kyc
    case privacy
    case help
    case language
    // Long-haul (one-off inter-city). Browse is the rider entry point,
    // tripDetail is the drilldown, postTrip is the driver create form.
    case longHaulBrowse
    case longHaulTripDetail(tripId: String)
    case longHaulPostTrip
    // Recent commute features
    case favorites           // Rider's saved routes
    case routeRequestsList   // Rider's own route demand posts (manage / withdraw)
    case driverDemand        // Driver-side aggregate demand list
    // Solo-seat — rider pays 2x the seat price to claim the whole car
    // for a specific day's ride. `soloPick` is the entry list (pick a
    // route → pick a date), `soloConfirm` is the price-quote + confirm
    // sheet's destination.
    case soloPick
    case soloConfirm(rideInstanceId: String)
}

// MARK: - Shared destination builder
//
// Hosts the `.navigationDestination(for: AppRoute.self)` map so each
// tab opts in once instead of duplicating the switch. Feeds bindings
// for the search-filters state down to `SearchFiltersView`, which
// CommuteTab still owns (filters are tab-local and pinned by the tab
// because `SearchFiltersView` mutates them through `@Binding`s).

struct AppRouteDestinations: ViewModifier {
    @Environment(AppStore.self) private var store
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
                    onDriverDashboard: { path.append(.driverDashboard) },
                    // Reached via push (Home → Book a ride), so wire a
                    // real back affordance. Routes-tab root keeps onBack
                    // nil since the tab bar provides the exit there.
                    onBack: { if !path.isEmpty { path.removeLast() } }
                )
                .navigationBarHidden(true)

            case .routeDetails(let id):
                RouteDetailsView(
                    routeId: id,
                    onBack: { if !path.isEmpty { path.removeLast() } },
                    onSubscribed: { bookingId in
                        // Land on the celebratory confirmation screen.
                        let context = bookingConfirmationContext(routeId: id, subscriptionId: bookingId)
                        path.append(.bookingConfirmed(
                            bookingId: bookingId,
                            pickup: context.pickup,
                            driverName: context.driverName
                        ))
                    },
                    onBookSolo: { _ in
                        // Drop the rider into the pick-a-date screen.
                        // The cached `store.routes` already contains
                        // this route (we just rendered its details), so
                        // SoloPickRouteView will render it at the top.
                        path.append(.soloPick)
                    }
                )
                .navigationBarHidden(true)

            case .mySubscriptions:
                MySubscriptionsView(
                    onOpenRoute: { path.append(.routeDetails(routeId: $0)) },
                    onOpenCalendar: { path.append(.calendar()) },
                    onFindRoutes: { path.append(.findRides) },
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
                    onOpenPayouts:  { path.append(.driverPayouts) },
                    onCreateRoute:  { path.append(.createRoute) },
                    onOpenDemand:   { path.append(.driverDemand) }
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
                    onMessageDriver: { openTripThread(for: id) },
                    onEndTrip: { rideId, routeId, driverId, initial, name, summary in
                        // Real driver/route values from LiveTrip's
                        // store lookup — were previously hardcoded
                        // to "A / Aiman / Subang Jaya → KLCC".
                        path.append(.rateRide(
                            rideInstanceId: rideId,
                            routeId: routeId,
                            driverId: driverId,
                            driverInitial: initial,
                            driverName: name,
                            summary: summary
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
                    },
                    onDone: { path = [] }
                )
                .navigationBarHidden(true)

            case .rateRide(let rideId, let routeId, let driverId, let init_, let name, let summary):
                RateRideView(
                    driverInitial: init_,
                    driverName: name,
                    routeSummary: summary,
                    dateLabel: dateLabelToday(),
                    durationLabel: "52 min",
                    onSubmit: { rating, tags, tip in
                        Task {
                            _ = await store.submitRideReview(
                                rideInstanceId: rideId,
                                routeId: routeId,
                                driverId: driverId,
                                rating: rating,
                                tags: tags,
                                tipMyr: tip,
                                note: nil
                            )
                            path = []
                        }
                    },
                    onBack:   { if !path.isEmpty { path.removeLast() } },
                    onSkip:   { path = [] }
                )
                .navigationBarHidden(true)

            case .chatThread(let threadId, let title):
                ChatThreadView(
                    threadId: threadId,
                    title: title,
                    onBack: { if !path.isEmpty { path.removeLast() } }
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

            case .wallet:
                WalletView(
                    onBack: { if !path.isEmpty { path.removeLast() } },
                    onOpenTripHistory: { path.append(.tripHistory) }
                )
                    .navigationBarHidden(true)

            case .tripHistory:
                TripHistoryView(
                    onBack: { if !path.isEmpty { path.removeLast() } },
                    onOpenReceipt: { id in path.append(.receipt(id: id)) }
                )
                .navigationBarHidden(true)

            case .notifications:
                NotificationsView(
                    onBack: { if !path.isEmpty { path.removeLast() } },
                    onOpenRoute: { id in path.append(.routeDetails(routeId: id)) },
                    onOpenSubscriptions: { path.append(.mySubscriptions) },
                    onOpenCalendar: { path.append(.calendar()) }
                )
                .navigationBarHidden(true)

            case .receipt(let id):
                ReceiptView(
                    bookingId: id,
                    onBack: { if !path.isEmpty { path.removeLast() } }
                )
                .navigationBarHidden(true)

            case .kyc:
                KycVerificationView(onBack: { if !path.isEmpty { path.removeLast() } })
                    .navigationBarHidden(true)

            case .privacy:
                PrivacySecurityView(onBack: { if !path.isEmpty { path.removeLast() } })
                    .navigationBarHidden(true)

            case .help:
                HelpCenterView(onBack: { if !path.isEmpty { path.removeLast() } })
                    .navigationBarHidden(true)

            case .language:
                LanguageSettingsView(onBack: { if !path.isEmpty { path.removeLast() } })
                    .navigationBarHidden(true)

            case .longHaulBrowse:
                LongHaulBrowseView(
                    onBack:    { if !path.isEmpty { path.removeLast() } },
                    onOpenTrip: { tripId in path.append(.longHaulTripDetail(tripId: tripId)) },
                    onPostTrip: { path.append(.longHaulPostTrip) }
                )
                .navigationBarHidden(true)

            case .longHaulTripDetail(let tripId):
                LongHaulTripDetailView(
                    tripId: tripId,
                    onBack:    { if !path.isEmpty { path.removeLast() } },
                    onBooked:  {
                        // Pop back to the browse list once the rider
                        // returns from Billplz so they immediately see
                        // their booking confirmation in My Bookings.
                        if !path.isEmpty { path.removeLast() }
                    }
                )
                .navigationBarHidden(true)

            case .longHaulPostTrip:
                PostLongHaulTripView(
                    onBack:    { if !path.isEmpty { path.removeLast() } },
                    onCreated: { _ in
                        // After posting, return the driver to the
                        // browse list so they can verify their trip
                        // appears in the public listing.
                        if !path.isEmpty { path.removeLast() }
                    }
                )
                .navigationBarHidden(true)

            case .favorites:
                FavoritesView(
                    onBack:      { if !path.isEmpty { path.removeLast() } },
                    onOpenRoute: { path.append(.routeDetails(routeId: $0)) }
                )
                .navigationBarHidden(true)

            case .routeRequestsList:
                RouteRequestsListView(
                    onBack: { if !path.isEmpty { path.removeLast() } }
                )
                .navigationBarHidden(true)

            case .driverDemand:
                DriverDemandView(
                    onBack: { if !path.isEmpty { path.removeLast() } },
                    onCreateRoute: { path.append(.createRoute) }
                )
                .navigationBarHidden(true)

            case .soloPick:
                SoloPickRouteView(
                    onBack:    { if !path.isEmpty { path.removeLast() } },
                    onPickRide: { rideId in path.append(.soloConfirm(rideInstanceId: rideId)) },
                    onFindRoutes: {
                        // Push Search onto the same stack. Riders pick a
                        // route → drill into details → "Book solo" pushes
                        // .soloConfirm directly (Gap B), so we don't need
                        // to bounce back here.
                        path.append(.findRides)
                    }
                )
                .navigationBarHidden(true)

            case .soloConfirm(let rideInstanceId):
                SoloConfirmView(
                    rideInstanceId: rideInstanceId,
                    onBack: { if !path.isEmpty { path.removeLast() } },
                    onBooked: { _ in
                        // After a successful book, pop back to root —
                        // the rider sees the booking on Home/Calendar
                        // via the usual refresh path.
                        path.removeAll()
                    }
                )
                .navigationBarHidden(true)
            }
        }
    }

    private func bookingConfirmationContext(routeId: String, subscriptionId: String) -> (pickup: String, driverName: String) {
        if let subscription = store.subscriptions.first(where: { $0.id == subscriptionId }) {
            let route = store.routes.first { $0.id == subscription.routeId }
            return (
                pickup: subscription.selectedPickupPoint.label,
                driverName: route?.driverName ?? "your driver"
            )
        }

        if let route = store.routes.first(where: { $0.id == routeId }) {
            return (
                pickup: route.pickupPoints.first?.label ?? route.startLocation,
                driverName: route.driverName
            )
        }

        return (pickup: "your pickup", driverName: "your driver")
    }

    private func openTripThread(for tripId: String) {
        let routeId = store.rideInstances.first(where: { $0.id == tripId })?.routeId
        let thread = store.threads.first { thread in
            if thread.tripId == tripId { return true }
            if let routeId { return thread.tripId == routeId }
            return false
        }

        if let thread {
            NotificationCenter.default.post(
                name: .voygoOpenThread,
                object: nil,
                userInfo: ["threadId": thread.id, "title": thread.title]
            )
        } else {
            NotificationCenter.default.post(
                name: HomeTab.switchToInboxNotification,
                object: nil
            )
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
