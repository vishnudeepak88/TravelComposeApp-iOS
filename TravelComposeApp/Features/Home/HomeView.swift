import SwiftUI

// MARK: - Home Tab (super-app hero)
//
// New top-level landing screen ported from the design handoff bundle
// (`car-pool/project/screens-c.jsx`). Replaces "Routes" as the default
// tab so the first thing the rider sees is a vibrant green gradient,
// a tappable search card, and the "Heading your way" feed — not a list.
//
// Drilling into the search card switches to the same FindCommute flow
// the Search tab already owns. The service grid is a marketing surface
// for now: Carpool routes the user to Search, the others surface a
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
                    switchToSearchTab()
                },
                onCarpoolTapped:      { switchToSearchTab() },
                onLongHaulTapped:     { path.append(.longHaulBrowse) },
                onSoloTapped:         { path.append(.soloPick) },
                onBookDayTapped:      { path.append(.bookDayPick) },
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
                },
                onOpenSubscriptions:  { path.append(.mySubscriptions) }
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

    private func switchToSearchTab() {
        NotificationCenter.default.post(
            name: .voygoOpenFindRoutes,
            object: nil
        )
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    var onSearchTapped: () -> Void = {}
    var onCarpoolTapped: () -> Void = {}
    /// Tap on the Long-haul service tile. Pushes onto the new
    /// `LongHaulBrowseView`; previously this raised the same
    /// "coming soon" alert as the other aspirational tiles.
    var onLongHaulTapped: () -> Void = {}
    /// Tap on the Ride solo service tile. Routes to `SoloPickRouteView`
    /// — rider picks a route, picks a date, sees the 2× quote, confirms.
    /// Replaces the previous "Coming soon" alert.
    var onSoloTapped: () -> Void = {}
    /// Tap on the Book-a-day service tile (was "Schedule"). Routes
    /// to `BookDayPickRouteView` — single ride at 1× seat price,
    /// no monthly commitment. Replaces the previous coming-soon
    /// alert on the third tile.
    var onBookDayTapped: () -> Void = {}
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
    /// "Resolve" tap on the persistent action-required banner. Routes
    /// the rider into MySubscriptions where retry-payment lives.
    var onOpenSubscriptions: () -> Void = {}

    @State private var showComingSoonFor: String? = nil

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return S.homeGreetingMorning
        case 12..<17: return S.homeGreetingAfternoon
        case 17..<22: return S.homeGreetingEvening
        default:      return S.homeGreetingFallback
        }
    }

    /// Time-aware hero subtitle. The previous hardcoded "Where to,
    /// this morning?" looked weird in the evening and broke the
    /// promise the greeting just made ("Good evening" + "this
    /// morning?" reads as if the app forgot what time it is).
    private var heroSubtitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return S.homeWhereToMorning
        case 12..<17: return S.homeWhereToAfternoon
        case 17..<22: return S.homeWhereToEvening
        default:      return S.homeWhereToLate
        }
    }

    private var firstName: String {
        let full = store.currentUser.name
        guard !full.isEmpty else { return S.homeFirstNameFallback }
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

    /// Subscriptions that need the rider's attention — paused (likely
    /// from a failed payment, since manual pause from the rider side
    /// is rare) or auto-cancelled. Drives the persistent "Action
    /// required" banner; without it a rider whose card was declined
    /// shows up at the curb tomorrow.
    private var pausedSubscriptions: [RouteSubscriptionWithRoute] {
        store.mySubscriptions().filter { $0.subscription.status == .paused }
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        hero

                        // Persistent "Action required" banner — surfaces
                        // any paused subscription (typically because a
                        // charge failed). Without this the rider only
                        // sees a notification once and forgets, then
                        // wakes up at the curb without a driver.
                        if !pausedSubscriptions.isEmpty {
                            actionRequiredBanner
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }

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
            S.comingSoonTitle,
            isPresented: Binding(
                get: { showComingSoonFor != nil },
                set: { if !$0 { showComingSoonFor = nil } }
            ),
            presenting: showComingSoonFor
        ) { _ in
            Button("OK", role: .cancel) { showComingSoonFor = nil }
        } message: { feature in
            Text(S.comingSoonMessage(feature: feature))
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
                    Text(S.homeNextCommute)
                        .font(.callout.weight(.black))
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
                .accessibilityLabel(S.homeA11yNextCommute)

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
                        .font(.footnote.weight(.heavy))
                        .foregroundColor(VPalette.text)
                    Text(S.homeDeparts(nc.route.departureTime))
                        .font(.caption2)
                        .foregroundColor(VPalette.textSec)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.textHint)
            }
            .padding(14)

            Rectangle().fill(VPalette.border).frame(height: 1)

            // Route — start → end
            HStack(alignment: .center, spacing: 12) {
                VIconBubble(systemName: "arrow.right.circle.fill", color: VPalette.success, size: 36, iconSize: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(shortStop(nc.route.startLocation)) → \(shortStop(nc.route.endLocation))")
                        .font(.footnote.weight(.heavy))
                        .foregroundColor(VPalette.text)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.caption2)
                            .foregroundColor(VPalette.textHint)
                        Text(pickupDropLabel(nc))
                            .font(.caption2)
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
                HueAvatar(name: nc.route.driverName.isEmpty ? S.homeDriverFallback : nc.route.driverName,
                          hue: 200, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(nc.route.driverName.isEmpty ? S.homeDriverFallback : nc.route.driverName)
                            .font(.footnote.weight(.heavy))
                            .foregroundColor(VPalette.text)
                        VVerifiedTick(size: 10)
                    }
                    Text(nc.route.carType.label)
                        .font(.caption2)
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
            actionPill(icon: "calendar", label: S.homeActionCalendar, action: onOpenCalendar)
            actionPill(icon: "bubble.left.fill", label: messageLabel(nc),
                       action: { onMessageDriver(nc.route.id) })
            actionPill(icon: "info.circle.fill", label: S.homeActionDetails,
                       action: { onOpenRoute(nc.route.id) })
        }
    }

    private func actionPill(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.heavy))
                Text(label)
                    .font(.caption.weight(.heavy))
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
        if cal.isDateInToday(nc.displayDate) { return S.homeWhenToday }
        if cal.isDateInTomorrow(nc.displayDate) { return S.homeWhenTomorrow }
        let f = DateFormatter()
        // Locale.current picks up the device language so the weekday
        // and month abbreviations honour the user's choice (e.g.
        // "Isn, 12 Mei" in Bahasa) instead of being pinned to en_MY.
        // Use setLocalizedDateFormatFromTemplate so the symbols render
        // in the correct order for each locale (some locales put day
        // before the weekday or vice-versa).
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
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
        case .active:    return S.homeStatusConfirmed
        case .paused:    return S.homeStatusPaused
        case .completed: return S.homeStatusCompleted
        case .cancelled: return S.homeStatusCancelled
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
        return hasThread ? S.homeActionMessage : S.homeActionInbox
    }

    // MARK: Action-required banner

    private var actionRequiredBanner: some View {
        Button(action: onOpenSubscriptions) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body.weight(.heavy))
                    .foregroundColor(VPalette.danger)
                    .frame(width: 38, height: 38)
                    .background(VPalette.danger.opacity(0.12))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(pausedSubscriptions.count == 1
                         ? S.actionRequiredOne
                         : S.actionRequiredMany(count: pausedSubscriptions.count))
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(VPalette.text)
                    Text(S.actionRequiredBody)
                        .font(.caption.weight(.medium))
                        .foregroundColor(VPalette.textSec)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.heavy))
                    .foregroundColor(VPalette.textHint)
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(VPalette.danger.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(S.homeA11yActionRequired)
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
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.85))
                        HStack(spacing: 4) {
                            Text(firstName).font(.body.weight(.heavy))
                            Text("👋")
                        }
                        .foregroundColor(.white)
                    }
                    Spacer(minLength: 0)
                    Button(action: onOpenNotifications) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.callout.weight(.semibold))
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

                Text(heroSubtitle)
                    .font(.title2.weight(.black))
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
                        .font(.callout.weight(.bold))
                        .foregroundColor(VPalette.primary)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(S.homeTo)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(VPalette.textHint)
                    Text(S.homeDestPlaceholder)
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(VPalette.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // Localized via `Strings.swift` → `Localizable.strings`.
                // English "Book a ride" / Malay "Tempah perjalanan".
                Text(S.homeBookARide)
                    .font(.footnote.weight(.heavy))
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
        // Labels are localized via Strings.swift, but each tile keeps a
        // `kind` so the tap router doesn't have to substring-match the
        // (now translated) label. Avoids the bug where switching the
        // device to Bahasa Malaysia would silently re-route every
        // non-Carpool tile through the coming-soon alert.
        let tiles: [ServiceTile] = [
            .init(kind: .carpool,  icon: "car.fill",            label: S.homeServiceCarpool,  fg: VPalette.primary,      bg: VPalette.primaryContainer,      isPrimary: true,  badge: S.homeServiceNewBadge),
            .init(kind: .solo,     icon: "person.fill",         label: S.homeServiceSolo,     fg: VPalette.accentCoral,  bg: VPalette.accentCoralContainer),
            // "Schedule" repurposed to "Book a day" — single ride on a
            // recurring route at 1× seat price. Different commitment
            // level from Carpool (monthly) and Solo (whole car).
            .init(kind: .schedule, icon: "calendar.badge.plus", label: S.homeServiceBookDay,  fg: VPalette.accentPurple, bg: VPalette.accentPurpleContainer),
            // Long-haul is the second real surface (after Carpool):
            // tapping it pushes onto the long-haul browse view.
            .init(kind: .longHaul, icon: "location.north.fill", label: S.homeServiceLongHaul, fg: VPalette.accentAmber,  bg: VPalette.accentAmberContainer, isLongHaul: true)
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
            ForEach(tiles) { tile in
                Button {
                    switch tile.kind {
                    case .carpool:  onCarpoolTapped()
                    case .longHaul: onLongHaulTapped()
                    case .solo:     onSoloTapped()
                    case .schedule: onBookDayTapped()
                    }
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
                    .font(.title2.weight(.bold))
                    .foregroundColor(tile.fg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let badge = tile.badge {
                    Text(badge)
                        .font(.caption2.weight(.black))
                        .tracking(0.4)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(VPalette.accentCoral)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(6)
                }
            }
            Text(tile.label)
                .font(.caption2.weight(.semibold))
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
                        .font(.caption.weight(.heavy))
                        .tracking(0.4)
                        .foregroundColor(.white.opacity(0.92))
                    Text(S.homePromoTitle)
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(.white)
                }
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.95))
                    Image(systemName: "car.fill")
                        .font(.title3.weight(.bold))
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
                    .font(.callout.weight(.black))
                    .tracking(-0.2)
                    .foregroundColor(VPalette.text)
                Spacer()
                Button(action: onSearchTapped) {
                    Text(S.homeSeeAll)
                        .font(.caption.weight(.heavy))
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
                            .font(.subheadline.weight(.heavy))
                            .foregroundColor(VPalette.text)
                        VVerifiedTick(size: 11)
                        Text("★ \(row.rating, specifier: "%.1f")")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(VPalette.textHint)
                    }
                    Text(row.route)
                        .font(.caption)
                        .foregroundColor(VPalette.textSec)
                    Text(S.homeDeparts(row.time))
                        .font(.caption2)
                        .foregroundColor(VPalette.textHint)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.ringgit(row.priceMyr))
                        .font(.headline.weight(.black))
                        .foregroundColor(VPalette.primary)
                        .minimumScaleFactor(0.8)
                    Text(S.homePerSeat)
                        .font(.caption2.weight(.semibold))
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
                name:     r.driverName.isEmpty ? S.homeDriverFallback : r.driverName,
                hue:      [280, 30, 140, 200][idx % 4],
                time:     r.departureTime,
                route:    "\(shortLabel(r.startLocation)) → \(shortLabel(r.endLocation))",
                priceMyr: r.pricePerSeat,
                rating:   r.reliability.averageRating > 0 ? r.reliability.averageRating : 4.9,
                routeId:  r.id
            )
        }
        if !live.isEmpty { return Array(live) }
        // Demo rows for first-launch / empty-feed states. Gated to DEBUG
        // so release builds never render misleading fake driver names —
        // the empty state takes over instead.
        #if DEBUG
        return [
            .init(name: "Maya R.",   hue: 280, time: "8:25 AM", route: "Mont Kiara → KLCC",     priceMyr: 14, rating: 4.9),
            .init(name: "David K.",  hue: 30,  time: "8:40 AM", route: "Subang Jaya → Bangsar", priceMyr: 12, rating: 4.8)
        ]
        #else
        return []
        #endif
    }

    private func shortLabel(_ raw: String) -> String {
        let trimmed = raw.split(separator: ",").first.map(String.init) ?? raw
        return trimmed.trimmingCharacters(in: .whitespaces)
    }
}

private struct ServiceTile: Identifiable {
    enum Kind { case carpool, solo, schedule, longHaul }
    let id = UUID()
    let kind: Kind
    let icon: String
    let label: String
    let fg: Color
    let bg: Color
    var isPrimary: Bool = false
    /// Retained for source compatibility with older call-sites; the
    /// tap router keys off `kind` now.
    var isLongHaul: Bool = false
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
