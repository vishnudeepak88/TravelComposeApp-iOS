import SwiftUI

// MARK: - Home Tab (super-app hero)
//
// New top-level landing screen ported from the design handoff bundle
// (`car-pool/project/screens-c.jsx`). Replaces "Routes" as the default
// tab so the first thing the rider sees is a vibrant green gradient,
// a tappable search card, and the "Heading your way" feed — not a list.
//
// Drilling into the search card pushes onto the same FindCommute flow
// the Routes tab already owns. The service grid is a marketing surface
// for now: Carpool routes the user to Find, the others surface a
// "Coming soon" sheet via the same `showComingSoonFor` pattern Wallet
// uses, so the tile is honest about what's wired up vs. on the roadmap.

struct HomeTab: View {
    @Environment(AppStore.self) private var store
    @State private var path: [AppRoute] = []
    /// Filter state pinned at the tab level — Home doesn't host
    /// SearchFilters today, but the shared destination map needs the
    /// bindings so a future "filter pill" on the hero card can flow
    /// straight into the same SearchFiltersView the Routes tab owns.
    @State private var filtersQuery: String = ""
    @State private var filtersEarliest: String = "06:30"
    @State private var filtersLatest: String = "09:00"
    @State private var filtersDays: DaysOfWeekFlags = .weekdays
    /// Tab-bar selectedIndex would let us deep-link "Inbox" from
    /// Home's Message-driver action, but that lives one level up
    /// (`MainTabView`). We surface a notification instead and let
    /// MainTabView map the request to a tab switch.
    static let switchToInboxNotification = Notification.Name("voygo.switchToInbox")

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onSearchTapped:       {
                    Telemetry.track(TelemetryEvents.homeBookARideTapped)
                    path.append(.findRides)
                },
                onCarpoolTapped:      { path.append(.findRides) },
                onOpenRoute:          { id in path.append(.routeDetails(routeId: id)) },
                onOpenNotifications:  { path.append(.notifications) },
                onOpenCalendar:       { path.append(.calendar()) },
                onMessageDriver:      { routeId in
                    // Cross-tab deep-link: if we know the thread for this
                    // route, switch to Inbox AND open it. Otherwise just
                    // switch to the Inbox root.
                    if let thread = store.threads.first(where: { $0.tripId == routeId }) {
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
            )
            .appRouteDestinations(
                path: $path,
                filtersQuery: $filtersQuery,
                filtersEarliest: $filtersEarliest,
                filtersLatest: $filtersLatest,
                filtersDays: $filtersDays
            )
            .navigationBarHidden(true)
            .enableSwipeBack()
        }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    var onSearchTapped: () -> Void = {}
    var onCarpoolTapped: () -> Void = {}
    /// Callback when a "Heading your way" card is tapped. Closures the
    /// route id rather than the row so HomeTab can drill straight into
    /// the shared `AppRoute.routeDetails(...)` without HomeView needing
    /// to know what comes next.
    var onOpenRoute: (String) -> Void = { _ in }
    /// Bell button → push notifications. Wired now that NotificationsView
    /// lives in `AppRoute`; previously this fell through to the
    /// "Coming soon" alert because there was no path to push.
    var onOpenNotifications: () -> Void = {}
    /// "Open calendar" action on the Next-commute card.
    var onOpenCalendar: () -> Void = {}
    /// "Message driver" action on the Next-commute card. The argument
    /// is the route id so the parent can decide whether to open an
    /// existing chat thread or fall back to the Inbox root.
    var onMessageDriver: (_ routeId: String) -> Void = { _ in }

    @State private var showComingSoonFor: String? = nil

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hi there"
        }
    }

    private var firstName: String {
        let full = store.currentUser.name
        guard !full.isEmpty else { return "there" }
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    /// Adaptive home: when the user has at least one active
    /// subscription with a real next ride, the "Next commute" card
    /// becomes the first major content under the hero — Voygo reads
    /// as a daily commute dashboard, not a search app. Without an
    /// active subscription we keep the original search-first layout.
    private var hasActiveCommute: Bool {
        nextCommute != nil
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        hero

                        if hasActiveCommute {
                            // Subscribed user — lead with the next
                            // commute. Search drops below as a
                            // secondary affordance ("looking for a
                            // different route?").
                            nextCommuteSection
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                            searchCard
                                .padding(.top, 16)
                        } else {
                            // No active subscription — keep the
                            // original search-first layout so first-
                            // time users can find a ride.
                            searchCard
                                .padding(.top, 16)
                        }

                        serviceGrid
                            .padding(.top, 16)
                        promoBanner
                        suggestedRides
                        Spacer().frame(height: VTabBarLayout.clearance)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                // iOS convention: tap the active tab again to scroll
                // to top. Wave 4 wired the notification but no root
                // subscribed; Home is now the first opt-in.
                .onReceive(NotificationCenter.default.publisher(for: .voygoTabReselected)) { note in
                    if (note.userInfo?["index"] as? Int) == 0 {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            }
        }
        .alert(
            "Coming soon",
            isPresented: Binding(
                get: { showComingSoonFor != nil },
                set: { if !$0 { showComingSoonFor = nil } }
            ),
            presenting: showComingSoonFor
        ) { _ in
            Button("OK", role: .cancel) { showComingSoonFor = nil }
        } message: { feature in
            Text("\(feature) is on the roadmap. We'll let you know when it lands.")
        }
    }

    // MARK: - Next-commute derivation
    //
    // A "next commute" is the soonest upcoming ride on a route the
    // signed-in rider is actively subscribed to. We resolve via
    // `store.mySubscriptions()` (which already filters cancelled subs
    // out and joins the route). Falling back to the subscription's
    // start date when no future ride instance exists yet keeps the
    // card useful right after Subscribe & pay completes — before the
    // first ride instance has been generated server-side.

    private struct NextCommute {
        let subscription: RouteSubscription
        let route: RecurringRoute
        /// The actual ride instance, when one exists in the next 30 days.
        let ride: CommuteRideInstance?
        /// The ride's date when present, otherwise the subscription's
        /// start-of-window so the card always has a real timestamp.
        let displayDate: Date
    }

    private var nextCommute: NextCommute? {
        let subs = store.mySubscriptions()
            .filter { $0.subscription.status == .active }
        guard !subs.isEmpty else { return nil }

        let now = Calendar.current.startOfDay(for: Date())

        // Each subscription with route gets ranked by its soonest
        // upcoming ride; the rider's whole list is then ranked by
        // those soonest dates so we pick the truly-next commute even
        // across multiple active subs.
        let ranked: [(NextCommute, Date)] = subs.compactMap { item in
            let upcoming = store.upcomingRides(routeId: item.route.id)
                .first { $0.confirmedPassengers.contains(store.riderId) || item.subscription.status == .active }
            let displayDate: Date = upcoming?.date
                ?? item.nextRideDate
                ?? max(item.subscription.startDate, now)
            // Skip subscriptions whose window has already ended.
            if item.subscription.endDate < now { return nil }
            return (
                NextCommute(
                    subscription: item.subscription,
                    route:        item.route,
                    ride:         upcoming,
                    displayDate:  displayDate
                ),
                displayDate
            )
        }
        return ranked.sorted { $0.1 < $1.1 }.first?.0
    }

    // MARK: - Next commute section

    @ViewBuilder
    private var nextCommuteSection: some View {
        if let nc = nextCommute {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Next commute")
                        .font(.system(size: 16, weight: .black))
                        .tracking(-0.2)
                        .foregroundColor(VPalette.text)
                    Spacer()
                    VBadge(text: statusLabel(nc), color: statusColor(nc), container: statusColor(nc).opacity(0.15))
                }

                Button {
                    onOpenRoute(nc.route.id)
                } label: {
                    nextCommuteCard(nc)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open route details for next commute")

                nextCommuteActions(nc)
            }
        }
    }

    private func nextCommuteCard(_ nc: NextCommute) -> some View {
        // Single rounded surface — no card-inside-card. Internal rows
        // use hairline dividers to delineate sections.
        VStack(alignment: .leading, spacing: 0) {
            // Top row — When (date + departure time)
            HStack(alignment: .center, spacing: 12) {
                VIconBubble(systemName: "clock.fill", color: VPalette.primary, size: 36, iconSize: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(whenLabel(nc))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(VPalette.text)
                    Text("Departs \(nc.route.departureTime)")
                        .font(.system(size: 11))
                        .foregroundColor(VPalette.textSec)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(VPalette.textHint)
            }
            .padding(14)

            Rectangle().fill(VPalette.border).frame(height: 1)

            // Route — start → end
            HStack(alignment: .center, spacing: 12) {
                VIconBubble(systemName: "arrow.right.circle.fill", color: VPalette.success, size: 36, iconSize: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(shortStop(nc.route.startLocation)) → \(shortStop(nc.route.endLocation))")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(VPalette.text)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(VPalette.textHint)
                        Text(pickupDropLabel(nc))
                            .font(.system(size: 11))
                            .foregroundColor(VPalette.textSec)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            Rectangle().fill(VPalette.border).frame(height: 1)

            // Driver row — name only; verified tick when the route
            // exists, no fake ratings or photos here.
            HStack(alignment: .center, spacing: 12) {
                HueAvatar(name: nc.route.driverName.isEmpty ? "Driver" : nc.route.driverName,
                          hue: 200, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(nc.route.driverName.isEmpty ? "Driver" : nc.route.driverName)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(VPalette.text)
                        VVerifiedTick(size: 10)
                    }
                    Text(nc.route.carType.label)
                        .font(.system(size: 11))
                        .foregroundColor(VPalette.textSec)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VPalette.border, lineWidth: 1)
        )
    }

    private func nextCommuteActions(_ nc: NextCommute) -> some View {
        HStack(spacing: 8) {
            actionPill(icon: "calendar", label: "Calendar", action: onOpenCalendar)
            actionPill(icon: "bubble.left.fill", label: messageLabel(nc),
                       action: { onMessageDriver(nc.route.id) })
            actionPill(icon: "info.circle.fill", label: "Details",
                       action: { onOpenRoute(nc.route.id) })
        }
    }

    private func actionPill(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .heavy))
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
                    .lineLimit(1)
            }
            .foregroundColor(VPalette.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(VPalette.primaryContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Next commute helpers

    private func shortStop(_ raw: String) -> String {
        let trimmed = raw.split(separator: ",").first.map(String.init) ?? raw
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    private func whenLabel(_ nc: NextCommute) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(nc.displayDate) { return "Today" }
        if cal.isDateInTomorrow(nc.displayDate) { return "Tomorrow" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_MY")
        // `EEE, d MMM` reads "Mon, 12 May"
        f.dateFormat = "EEE, d MMM"
        return f.string(from: nc.displayDate)
    }

    private func pickupDropLabel(_ nc: NextCommute) -> String {
        // Prefer the rider's selected pickup/drop on the subscription;
        // fall back to the route's first pickup/drop point label so
        // we never render an empty subtitle.
        let pickup = nc.subscription.selectedPickupPoint.label.isEmpty
            ? (nc.route.pickupPoints.first?.label ?? "Pickup")
            : nc.subscription.selectedPickupPoint.label
        let drop = nc.subscription.selectedDropPoint.label.isEmpty
            ? (nc.route.dropPoints.first?.label ?? "Drop")
            : nc.subscription.selectedDropPoint.label
        return "\(pickup) → \(drop)"
    }

    private func statusLabel(_ nc: NextCommute) -> String {
        switch nc.subscription.status {
        case .active:    return "Confirmed"
        case .paused:    return "Paused"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    private func statusColor(_ nc: NextCommute) -> Color {
        switch nc.subscription.status {
        case .active:    return VPalette.success
        case .paused:    return VPalette.warning
        case .completed: return VPalette.accent
        case .cancelled: return VPalette.danger
        }
    }

    private func messageLabel(_ nc: NextCommute) -> String {
        // Short-circuit on whether a real chat thread already exists
        // for this route. The thread DTO uses `tripId` (which the
        // backend populates from `chat_threads.route_id`).
        let hasThread = store.threads.contains { $0.tripId == nc.route.id }
        return hasThread ? "Message" : "Inbox"
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            VPalette.primaryGradient
                .ignoresSafeArea(edges: .top)

            // Decorative blobs — soft white + amber
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 200, height: 200)
                .offset(x: 200, y: -20)
            Circle()
                .fill(VPalette.accentAmber.opacity(0.18))
                .frame(width: 120, height: 120)
                .offset(x: 240, y: 80)

            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    HueAvatar(name: firstName, hue: 140, size: 40)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.5), lineWidth: 2)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        HStack(spacing: 4) {
                            Text(firstName).font(.system(size: 17, weight: .heavy))
                            Text("👋")
                        }
                        .foregroundColor(.white)
                    }
                    Spacer(minLength: 0)
                    Button(action: onOpenNotifications) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Circle())
                            // Unread badge — coral dot when there's
                            // anything new in `store.notifications`.
                            // Reads from the derived counter so we
                            // don't keep a separate flag in sync.
                            if store.unreadNotificationsCount > 0 {
                                Circle()
                                    .fill(VPalette.accentCoral)
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                    .offset(x: 2, y: -2)
                                    .accessibilityLabel("\(store.unreadNotificationsCount) unread notifications")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Text(S.homeWhereTo)
                    .font(.system(size: 26, weight: .black))
                    .tracking(-0.5)
                    .foregroundColor(.white)
                    .lineSpacing(1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 24)
        }
    }

    // MARK: Lifted search card

    private var searchCard: some View {
        Button(action: onSearchTapped) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(VPalette.primaryContainer)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(VPalette.primary)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("To")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(VPalette.textHint)
                    Text("Where are you heading?")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(VPalette.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // Localized via `Strings.swift` → `Localizable.strings`.
                // English "Book a ride" / Malay "Tempah perjalanan".
                Text(S.homeBookARide)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(VPalette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(14)
            .background(VPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: VPalette.text.opacity(0.12), radius: 20, x: 0, y: 12)
            // Force the entire rendered shape (including padding) to
            // be the hit area; without this, SwiftUI sometimes keeps
            // the implicit shape limited to non-transparent pixels
            // and parts of the card stop responding to taps.
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.findRide")
    }

    // MARK: Service grid

    private var serviceGrid: some View {
        let tiles: [ServiceTile] = [
            .init(icon: "car.fill",            label: "Carpool",   fg: VPalette.primary,      bg: VPalette.primaryContainer,      isPrimary: true,  badge: "NEW"),
            .init(icon: "person.fill",         label: "Ride solo", fg: VPalette.accentCoral,  bg: VPalette.accentCoralContainer),
            .init(icon: "calendar",            label: "Schedule",  fg: VPalette.accentPurple, bg: VPalette.accentPurpleContainer),
            .init(icon: "location.north.fill", label: "Long-haul", fg: VPalette.accentAmber,  bg: VPalette.accentAmberContainer)
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
            ForEach(tiles) { tile in
                Button {
                    if tile.isPrimary { onCarpoolTapped() }
                    else { showComingSoonFor = tile.label }
                } label: {
                    serviceTileBody(tile)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func serviceTileBody(_ tile: ServiceTile) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                tile.bg
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(
                        color: tile.isPrimary ? VPalette.primary.opacity(0.25) : .clear,
                        radius: 16, x: 0, y: 6
                    )
                Image(systemName: tile.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(tile.fg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let badge = tile.badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.4)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(VPalette.accentCoral)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(6)
                }
            }
            Text(tile.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(VPalette.text)
        }
    }

    // MARK: Promo banner

    private var promoBanner: some View {
        ZStack {
            LinearGradient(
                colors: [VPalette.accentAmber, Color(hex: 0xFF8A2A)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 100, height: 100)
                .offset(x: 130, y: 40)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(S.homePromoKicker)
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.4)
                        .foregroundColor(.white.opacity(0.92))
                    Text(S.homePromoTitle)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(.white)
                }
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.95))
                    Image(systemName: "car.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(hex: 0xFF8A2A))
                }
                .frame(width: 52, height: 52)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    // MARK: Suggested rides

    private var suggestedRides: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(S.homeHeadingYourWay)
                    .font(.system(size: 16, weight: .black))
                    .tracking(-0.2)
                    .foregroundColor(VPalette.text)
                Spacer()
                Button(action: onSearchTapped) {
                    Text(S.homeSeeAll)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(VPalette.primary)
                }
                .buttonStyle(.plain)
            }
            ForEach(suggestedRideRows) { row in
                suggestedRideCard(row)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    private func suggestedRideCard(_ row: SuggestedRide) -> some View {
        // Tap the row → route details if we have a backing routeId,
        // otherwise fall through to the find-rides search (the demo
        // rows don't carry a real id).
        Button {
            if let id = row.routeId {
                onOpenRoute(id)
            } else {
                onSearchTapped()
            }
        } label: {
            HStack(spacing: 12) {
                HueAvatar(name: row.name, hue: row.hue, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(VPalette.text)
                        VVerifiedTick(size: 11)
                        Text("★ \(row.rating, specifier: "%.1f")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(VPalette.textHint)
                    }
                    Text(row.route)
                        .font(.system(size: 12))
                        .foregroundColor(VPalette.textSec)
                    Text("Departs \(row.time)")
                        .font(.system(size: 11))
                        .foregroundColor(VPalette.textHint)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("RM \(row.priceMyr)")
                        .font(.system(size: 18, weight: .black, design: .default))
                        .foregroundColor(VPalette.primary)
                    Text("per seat")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(VPalette.textHint)
                }
            }
            .padding(14)
            .background(VPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: VPalette.text.opacity(0.04), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// Shows real driver routes from the store when available; falls back
    /// to a polished demo so the screen never reads as empty on a fresh
    /// install.
    private var suggestedRideRows: [SuggestedRide] {
        let live = store.routes.prefix(2).enumerated().map { idx, r in
            SuggestedRide(
                name:     r.driverName.isEmpty ? "Driver" : r.driverName,
                hue:      [280, 30, 140, 200][idx % 4],
                time:     r.departureTime,
                route:    "\(shortLabel(r.startLocation)) → \(shortLabel(r.endLocation))",
                priceMyr: r.pricePerSeat,
                rating:   r.reliability.averageRating > 0 ? r.reliability.averageRating : 4.9,
                routeId:  r.id
            )
        }
        if !live.isEmpty { return Array(live) }
        return [
            .init(name: "Maya R.",   hue: 280, time: "8:25 AM", route: "Mont Kiara → KLCC",     priceMyr: 14, rating: 4.9),
            .init(name: "David K.",  hue: 30,  time: "8:40 AM", route: "Subang Jaya → Bangsar", priceMyr: 12, rating: 4.8)
        ]
    }

    private func shortLabel(_ raw: String) -> String {
        let trimmed = raw.split(separator: ",").first.map(String.init) ?? raw
        return trimmed.trimmingCharacters(in: .whitespaces)
    }
}

private struct ServiceTile: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let fg: Color
    let bg: Color
    var isPrimary: Bool = false
    var badge: String? = nil
}

private struct SuggestedRide: Identifiable {
    let id = UUID()
    let name: String
    let hue: Double
    let time: String
    let route: String
    let priceMyr: Int
    let rating: Double
    /// Backing route id when the row originated from `store.routes`.
    /// `nil` for the polished demo fallback rows so taps fall through
    /// to the find-rides search instead of pushing a 404 detail screen.
    var routeId: String? = nil
}

// MARK: - Atoms (Home-local; promote to Polished.swift if they earn reuse)

/// Pastel avatar circle keyed by hue, mirroring the `Avatar` component
/// from `tokens.jsx`. Distinct from the existing gradient-style
/// `VAvatar` — that one is a brand-loud hero avatar; this one is a
/// quiet list-row avatar that lets multiple drivers feel visually
/// distinct without each one shouting in the brand color.
struct HueAvatar: View {
    let name: String
    var hue: Double = 210
    var size: CGFloat = 36

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(Color(hue: hue/360, saturation: 0.32, brightness: 0.86))
            Text(initial)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(Color(hue: hue/360, saturation: 0.55, brightness: 0.32))
        }
        .frame(width: size, height: size)
    }
}

/// Small green pill with a white check. Sits next to verified driver
/// names in suggested rides + profile cards.
struct VVerifiedTick: View {
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().fill(VPalette.success)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.65, weight: .black))
                .foregroundColor(.white)
        }
        .frame(width: size + 4, height: size + 4)
    }
}

#Preview("Home") {
    HomeView()
        .environment(AppStore())
}
