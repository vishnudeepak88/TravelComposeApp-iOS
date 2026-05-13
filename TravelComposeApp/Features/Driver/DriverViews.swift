import SwiftUI
import CoreLocation

// MARK: - Driver Route Dashboard (mirrors DriverRouteDashboardScreen.kt)

struct DriverDashboardView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onOpenCalendar: (String) -> Void
    var onOpenPayouts: (() -> Void)? = nil
    /// Empty-state CTA — drills the driver into the create-route flow
    /// so "No routes yet" stops being a dead-end.
    var onCreateRoute: (() -> Void)? = nil
    /// Pushes to the demand screen — riders' waiting list of corridors
    /// they want drivers to add. Wired from AppRoute → DriverDemandView.
    var onOpenDemand: (() -> Void)? = nil

    @State private var actionResult: String? = nil
    @State private var actionError: String? = nil
    /// Tracks an in-flight pause/resume so the button disables during the
    /// async call and a double-tap can't fire two requests.
    @State private var inFlightRouteId: String? = nil
    /// Same idea for the Mon–Fri / All-Days schedule chips — rapid taps
    /// were previously firing two updateRouteSchedule requests at the
    /// same route in parallel.
    @State private var inFlightScheduleRouteId: String? = nil
    /// Pending pause/resume awaiting user confirmation. Pausing an active
    /// route cancels every scheduled pickup, which a colleague riding
    /// tomorrow morning shouldn't have happen on a fat-finger tap.
    @State private var pendingToggle: (routeId: String, currentlyActive: Bool)? = nil
    /// First-paint flag — show skeletons before the empty-state ever
    /// renders, so we don't briefly tell the driver "No routes yet"
    /// while their data is still arriving.
    @State private var hasLoaded: Bool = false
    /// Set when the driver taps "Edit" on a route card. Drives the
    /// `EditRouteSheet` sheet presentation.
    @State private var editingRouteId: String? = nil

    var dashboards: [DriverRouteDashboard] { store.driverDashboards() }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Driver Dashboard", onBack: onBack) {
                    HStack(spacing: 8) {
                        if let onOpenDemand {
                            Button(action: onOpenDemand) {
                                Image(systemName: "hand.raised.fill")
                                    .font(.callout.weight(.bold))
                                    .foregroundColor(VPalette.primary)
                                    .frame(width: 40, height: 40)
                                    .background(VPalette.primaryContainer)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rider demand")
                        }
                        if let onOpenPayouts {
                            Button(action: onOpenPayouts) {
                                Image(systemName: "banknote.fill")
                                    .font(.callout.weight(.bold))
                                    .foregroundColor(VPalette.primary)
                                    .frame(width: 40, height: 40)
                                    .background(VPalette.primaryContainer)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Payouts")
                        }
                    }
                }

                if dashboards.isEmpty && !hasLoaded {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(0..<2, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 12) {
                                    VSkeleton(height: 18)
                                    VSkeleton(height: 14)
                                    HStack(spacing: 8) {
                                        VSkeleton(height: 28, corner: 14)
                                        VSkeleton(height: 28, corner: 14)
                                    }
                                }
                                .padding(16)
                                .background(VPalette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                } else if dashboards.isEmpty {
                    EmptyStateView(icon: "car.badge.plus", title: S.driverEmptyTitle,
                                   subtitle: S.driverEmptyBody,
                                   ctaLabel: onCreateRoute != nil ? S.driverEmptyCTA : nil,
                                   ctaAction: onCreateRoute)
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let msg = actionResult {
                                InfoBanner(message: msg, color: VoygoTheme.success) { actionResult = nil }
                                    .padding(.horizontal, 16)
                            }
                            if let err = actionError {
                                InfoBanner(message: err, color: VoygoTheme.danger) { actionError = nil }
                                    .padding(.horizontal, 16)
                            }

                            ForEach(dashboards) { dashboard in
                                DriverRouteCard(
                                    dashboard: dashboard,
                                    isToggling: inFlightRouteId == dashboard.route.id,
                                    onTogglePause: { routeId, isActive in
                                        // Pausing a running route is destructive
                                        // (cancels every scheduled pickup) — confirm first.
                                        if isActive {
                                            pendingToggle = (routeId, true)
                                        } else {
                                            performToggle(routeId: routeId, currentlyActive: false)
                                        }
                                    },
                                    onSetWeekdays: { routeId, time in
                                        scheduleUpdate(routeId: routeId, time: time, days: .weekdays, label: "weekdays")
                                    },
                                    onSetAllDays: { routeId, time in
                                        scheduleUpdate(routeId: routeId, time: time, days: .allDays, label: "all days")
                                    },
                                    onCalendar: { onOpenCalendar($0) },
                                    onEdit: { routeId in editingRouteId = routeId }
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .refreshable {
                        await store.refreshAll()
                    }
                }
            }
        }
        .task {
            await store.refreshAll()
            // Pull rider-demand counts so the nav-bar hand-raised
            // button knows whether to badge.
            await store.refreshRouteRequestDemand()
            hasLoaded = true
        }
        .alert(
            "Pause this route?",
            isPresented: Binding(
                get: { pendingToggle != nil },
                set: { if !$0 { pendingToggle = nil } }
            ),
            presenting: pendingToggle
        ) { p in
            Button("Pause", role: .destructive) {
                performToggle(routeId: p.routeId, currentlyActive: p.currentlyActive)
                pendingToggle = nil
            }
            Button("Cancel", role: .cancel) { pendingToggle = nil }
        } message: { _ in
            Text("Pausing cancels every scheduled pickup on this route. Riders will be notified.")
        }
        .sheet(item: Binding(
            get: { editingRouteId.map { EditRouteSheetID(routeId: $0) } },
            set: { if $0 == nil { editingRouteId = nil } }
        )) { id in
            if let route = store.routes.first(where: { $0.id == id.routeId }) {
                EditRouteSheet(
                    route: route,
                    hasActiveSubscribers: store.subscriptions.contains {
                        $0.routeId == id.routeId && $0.status == .active
                    }
                ) {
                    editingRouteId = nil
                }
            }
        }
    }

    /// Throttled schedule update — gates on `inFlightScheduleRouteId` so
    /// rapid taps on Mon–Fri or All-Days don't fire parallel requests
    /// against the same route.
    private func scheduleUpdate(routeId: String, time: String, days: DaysOfWeekFlags, label: String) {
        guard isValidHHmm(time) else {
            actionError = "Departure time must be HH:mm (e.g. 07:42)."
            return
        }
        guard inFlightScheduleRouteId != routeId else { return }
        inFlightScheduleRouteId = routeId
        Task {
            let r = await store.updateRouteSchedule(routeId: routeId, departureTime: time, daysOfWeek: days)
            inFlightScheduleRouteId = nil
            if case .failure(let e) = r {
                actionError = e.localizedDescription
            } else {
                actionResult = "Schedule updated to \(label)."
            }
        }
    }

    private func performToggle(routeId: String, currentlyActive: Bool) {
        guard inFlightRouteId == nil else { return }
        inFlightRouteId = routeId
        Task {
            let result = await store.setRouteActive(routeId: routeId, active: !currentlyActive)
            inFlightRouteId = nil
            if case .failure(let error) = result {
                actionError = error.localizedDescription
            } else {
                actionResult = currentlyActive ? "Route paused." : "Route resumed."
            }
        }
    }

    /// HH:mm validator shared by the schedule editor buttons. Anything else
    /// would silently send garbage to the backend and quietly fail.
    private func isValidHHmm(_ s: String) -> Bool {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }
}

struct DriverRouteCard: View {
    let dashboard: DriverRouteDashboard
    /// True while the parent's pause/resume request is in flight — disables
    /// the toggle so a double-tap can't fire a second request.
    var isToggling: Bool = false
    var onTogglePause: (String, Bool) -> Void
    var onSetWeekdays: (String, String) -> Void
    var onSetAllDays:  (String, String) -> Void
    var onCalendar: (String) -> Void
    /// Optional — opens the route-edit sheet from the dashboard.
    /// Nil-defaulted so existing call sites compile without churn.
    var onEdit: ((String) -> Void)? = nil

    @Environment(AppStore.self) private var store
    @State private var departureInput: String = ""
    @State private var rideControlInFlight: Bool = false
    @State private var rideControlError: String? = nil
    @State private var pendingNoShowRiderId: String? = nil
    @State private var noShowConfirmFor: (rideId: String, riderId: String)? = nil

    var route: RecurringRoute { dashboard.route }

    /// Today's ride for this route, if any. Drives the ride-control
    /// panel — only shown when the driver actually has a ride today
    /// (SCHEDULED or IN_PROGRESS).
    private var todayRide: CommuteRideInstance? {
        let cal = Calendar.current
        return dashboard.upcomingRides.first(where: {
            cal.isDateInToday($0.date) &&
            ($0.rideStatus == .scheduled || $0.rideStatus == .inProgress)
        })
    }

    var body: some View {
        VoygoCard {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(route.startLocation) → \(route.endLocation)")
                            .font(.headline).foregroundColor(VoygoTheme.textPrimary)
                        Text("\(Formatters.ringgit(route.pricePerSeat))/seat · \(route.carType.label)")
                            .font(.caption).foregroundColor(VoygoTheme.textSecondary)
                    }
                    Spacer()
                    StatusBadge(text: route.activeStatus == .active ? "Active" : "Paused",
                                color: route.activeStatus == .active ? VoygoTheme.success : VoygoTheme.warning)
                }

                // Stats row
                HStack(spacing: 0) {
                    DashStatCell(icon: "person.3.fill", value: "\(dashboard.subscribedRiders.count)", label: "Riders")
                    Spacer()
                    DashStatCell(icon: "calendar", value: "\(dashboard.upcomingRides.count)", label: "Upcoming")
                    Spacer()
                    DashStatCell(icon: "seat.fill", value: "\(route.seatCount)", label: "Seats")
                    Spacer()
                    DashStatCell(icon: "calendar.day.timeline.leading", value: route.daysOfWeek.shortLabel, label: "Days")
                }

                // Solo bookings banner — surfaces upcoming exclusive
                // rides so the driver sees at a glance which days
                // their car is locked to one rider. Without this they
                // only learn via push notification at booking time.
                let upcomingSolos = dashboard.upcomingRides.filter { $0.isSolo }
                if !upcomingSolos.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "person.fill.checkmark")
                            .font(.subheadline.weight(.heavy))
                            .foregroundColor(VoygoTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(upcomingSolos.count) solo \(upcomingSolos.count == 1 ? "booking" : "bookings") ahead")
                                .font(.footnote.weight(.heavy))
                                .foregroundColor(VoygoTheme.textPrimary)
                            Text(soloDatesSummary(upcomingSolos))
                                .font(.caption2)
                                .foregroundColor(VoygoTheme.textSecondary)
                        }
                        Spacer()
                        Text(Formatters.ringgit(upcomingSolos.compactMap { $0.soloPriceMyr }.reduce(0, +)))
                            .font(.footnote.weight(.black))
                            .foregroundColor(VoygoTheme.accent)
                    }
                    .padding(10)
                    .background(VoygoTheme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Divider().background(VoygoTheme.cardBorder)

                // Schedule editor
                VoygoTextField(label: "Departure Time (HH:mm)", text: $departureInput,
                               placeholder: route.departureTime, keyboardType: .numbersAndPunctuation)
                    .onAppear { departureInput = route.departureTime }

                // Day preset buttons
                HStack(spacing: 8) {
                    Button(action: { onSetWeekdays(route.id, departureInput.isEmpty ? route.departureTime : departureInput) }) {
                        Text("Mon–Fri").font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(VoygoTheme.primary.opacity(0.15))
                            .foregroundColor(VoygoTheme.primary).cornerRadius(8)
                    }
                    Button(action: { onSetAllDays(route.id, departureInput.isEmpty ? route.departureTime : departureInput) }) {
                        Text("All Days").font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(VoygoTheme.accent.opacity(0.15))
                            .foregroundColor(VoygoTheme.accent).cornerRadius(8)
                    }
                    Spacer()
                }

                // Today's ride control panel — only when the driver
                // has a ride scheduled or in progress TODAY. Without
                // these the on-time-rate metric (which feeds the
                // payout streak bonus) and the no-show penalty engine
                // had no way to be triggered from iOS.
                if let ride = todayRide {
                    rideControlPanel(ride)
                }

                // Action buttons
                HStack(spacing: 10) {
                    Button(action: { onTogglePause(route.id, route.activeStatus == .active) }) {
                        HStack(spacing: 6) {
                            if isToggling {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(route.activeStatus == .active ? VoygoTheme.warning : VoygoTheme.success)
                            } else {
                                Image(systemName: route.activeStatus == .active ? "pause.circle.fill" : "play.circle.fill")
                                Text(route.activeStatus == .active ? "Pause Route" : "Resume Route")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(route.activeStatus == .active ? VoygoTheme.warning.opacity(0.15) : VoygoTheme.success.opacity(0.15))
                        .foregroundColor(route.activeStatus == .active ? VoygoTheme.warning : VoygoTheme.success)
                        .cornerRadius(12)
                    }
                    .disabled(isToggling)
                    Button(action: { onCalendar(route.id) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                            Text("Calendar")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(VoygoTheme.primary.opacity(0.15))
                        .foregroundColor(VoygoTheme.primary)
                        .cornerRadius(12)
                    }
                }

                // Edit row — only shown when the parent wired an
                // `onEdit` callback. Opens the EditRouteSheet which
                // handles price (with active-rider freeze) + seats +
                // car type + start/end labels. Pickup/drop point
                // editing lives in a future iteration.
                if let onEdit {
                    Button { onEdit(route.id) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.pencil")
                            Text(S.driverEditRoute)
                        }
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(VoygoTheme.textSecondary.opacity(0.10))
                        .foregroundColor(VoygoTheme.textPrimary)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    /// Inline ride-control panel for today's ride. Replaces the
    /// missing "start / end / no-show" surface that drivers needed
    /// to trigger the on-time-rate metric and penalty engine. The
    /// passenger list is read from `ride.confirmedPassengers` and
    /// each name has a swipe-style "No-show" affordance (currently
    /// rendered as a small label — could promote to a swipe action
    /// once we add a List wrapper).
    @ViewBuilder
    private func rideControlPanel(_ ride: CommuteRideInstance) -> some View {
        let inProgress = ride.rideStatus == .inProgress
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: inProgress ? "dot.radiowaves.left.and.right" : "clock.fill")
                    .foregroundColor(inProgress ? VoygoTheme.success : VoygoTheme.warning)
                Text(S.driverTodayRide)
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VoygoTheme.textPrimary)
                Spacer()
                StatusBadge(
                    text: inProgress ? S.driverRideInProgress : S.driverRideScheduled,
                    color: inProgress ? VoygoTheme.success : VoygoTheme.warning
                )
            }

            // Confirmed-passenger list with per-row No-show action.
            // Empty state: a ride with no confirmed passengers is
            // unusual but valid (subscription model — riders show
            // up if they want); render nothing rather than a label.
            if !ride.confirmedPassengers.isEmpty {
                VStack(spacing: 6) {
                    ForEach(ride.confirmedPassengers, id: \.self) { riderId in
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundColor(VoygoTheme.textSecondary)
                            Text(displayName(forRider: riderId))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(VoygoTheme.textPrimary)
                            Spacer()
                            // No-show requires confirmation — destructive
                            // action with a clear undo path.
                            Button {
                                noShowConfirmFor = (ride.id, riderId)
                            } label: {
                                Text(S.driverMarkNoShow)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(VoygoTheme.warning.opacity(0.15))
                                    .foregroundColor(VoygoTheme.warning)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(rideControlInFlight && pendingNoShowRiderId == riderId)
                        }
                    }
                }
            }

            if let err = rideControlError {
                Text(err)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(VoygoTheme.warning)
                    .onTapGesture { rideControlError = nil }
            }

            // Start / End buttons. Only one is enabled at a time
            // depending on ride state — server enforces this too.
            HStack(spacing: 10) {
                Button {
                    Task { await runStart(rideId: ride.id) }
                } label: {
                    Label(S.driverStartRide, systemImage: "play.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(VoygoTheme.success.opacity(0.15))
                        .foregroundColor(VoygoTheme.success)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(inProgress || rideControlInFlight)

                Button {
                    Task { await runEnd(rideId: ride.id) }
                } label: {
                    Label(S.driverEndRide, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background((inProgress ? VoygoTheme.primary : VoygoTheme.textSecondary).opacity(0.15))
                        .foregroundColor(inProgress ? VoygoTheme.primary : VoygoTheme.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(!inProgress || rideControlInFlight)
            }
        }
        .padding(12)
        .background(VoygoTheme.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .alert(
            S.driverConfirmNoShowTitle,
            isPresented: Binding(
                get: { noShowConfirmFor != nil },
                set: { if !$0 { noShowConfirmFor = nil } }
            ),
            presenting: noShowConfirmFor
        ) { pair in
            Button(S.driverMarkNoShow, role: .destructive) {
                let p = pair
                noShowConfirmFor = nil
                Task { await runNoShow(rideId: p.rideId, riderId: p.riderId) }
            }
            Button(S.cancel, role: .cancel) { noShowConfirmFor = nil }
        } message: { pair in
            Text(S.driverConfirmNoShowBody(displayName(forRider: pair.riderId)))
        }
    }

    private func displayName(forRider riderId: String) -> String {
        // Look up the rider's display name from cached threads /
        // subscriptions if we have it; otherwise show a short id.
        if let sub = dashboard.subscribedRiders.first(where: { $0.riderId == riderId }) {
            return sub.riderName.isEmpty ? String(riderId.prefix(8)) : sub.riderName
        }
        return String(riderId.prefix(8))
    }

    private func runStart(rideId: String) async {
        rideControlInFlight = true
        rideControlError = nil
        let result = await store.startRide(rideInstanceId: rideId)
        if case .failure(let err) = result {
            rideControlError = err.localizedDescription
        }
        rideControlInFlight = false
    }

    private func runEnd(rideId: String) async {
        rideControlInFlight = true
        rideControlError = nil
        let result = await store.endRide(rideInstanceId: rideId)
        if case .failure(let err) = result {
            rideControlError = err.localizedDescription
        }
        rideControlInFlight = false
    }

    private func runNoShow(rideId: String, riderId: String) async {
        rideControlInFlight = true
        rideControlError = nil
        pendingNoShowRiderId = riderId
        let result = await store.markRiderNoShow(rideInstanceId: rideId, riderId: riderId)
        if case .failure(let err) = result {
            rideControlError = err.localizedDescription
        }
        rideControlInFlight = false
        pendingNoShowRiderId = nil
    }

    /// Comma-separated month-day list of upcoming solo bookings —
    /// "May 14, May 16" — for the dashboard's solo-summary banner.
    /// Truncates at 3 entries to keep the line readable.
    private func soloDatesSummary(_ rides: [CommuteRideInstance]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let labels = rides.prefix(3).map { formatter.string(from: $0.date) }
        let head = labels.joined(separator: ", ")
        return rides.count > 3 ? "\(head), +\(rides.count - 3) more" : head
    }
}

private struct DashStatCell: View {
    let icon: String; let value: String; let label: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.subheadline).foregroundColor(VoygoTheme.primary)
            Text(value).font(.subheadline.bold()).foregroundColor(VoygoTheme.textPrimary).lineLimit(1)
            Text(label).font(.caption2).foregroundColor(VoygoTheme.textHint)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct InfoBanner: View {
    let message: String; let color: Color; let onDismiss: () -> Void
    var body: some View {
        HStack {
            Image(systemName: "info.circle.fill").foregroundColor(color)
            Text(message).font(.caption).foregroundColor(color)
            Spacer()
            Button("×", action: onDismiss).font(.headline).foregroundColor(color)
        }
        .padding(12)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Create Recurring Route (mirrors CreateRecurringRouteScreen.kt)

@MainActor
@Observable final class CreateRouteViewModel {
    var startLocation = ""
    var endLocation   = ""
    var departureTime = "08:00"
    // Int-typed so the stepper controls don't have to parse on every
    // tap. The submit path converts to the API model below.
    var seatCount: Int = 3
    var pricePerSeat: Int = 8
    var carType: CarType = .sedan
    // Plate + colour intentionally NOT here. Vehicle identity is set
    // ONCE on the driver's profile (Profile → Your vehicle) and the
    // server reads it back per-route. Keeping it off the route prevents
    // the "list plate A on route, arrive in car B" bait-and-switch.
    var monday = true; var tuesday = true; var wednesday = true
    var thursday = true; var friday = true; var saturday = false; var sunday = false
    var pickupPoints: [String] = []
    var dropPoints: [String]   = []
    var createState: CreateState = .idle
    var newPickup = ""
    var newDrop   = ""

    /// Coordinates captured when the user picks a Start/Destination from the
    /// place picker. Cleared on text edit so we don't ship stale lat/lng for
    /// a different label.
    var startCoordinate: PlaceSuggestion? = nil
    var endCoordinate: PlaceSuggestion? = nil

    /// Suggested pickup/drop hubs near Start/Destination — once the driver
    /// has picked the route's endpoints, MKLocalSearch finds nearby
    /// LRT/MRT/bus stops so the rider stops can be added with one tap
    /// instead of being typed out.
    var pickupSuggestions: [PlaceSuggestion] = []
    var dropSuggestions: [PlaceSuggestion] = []
    var isLoadingPickupSuggestions = false
    var isLoadingDropSuggestions = false
    /// Lowercased labels that came from the corridor-suggestions
    /// endpoint (popular on similar routes). The view renders a small
    /// "Popular" badge on those chips so the driver knows other people
    /// have used them — a soft social signal that this is a real
    /// commuter touchpoint, not just any building MapKit happens to
    /// index nearby.
    var popularPickupLabels: Set<String> = []
    var popularDropLabels: Set<String> = []

    private var pickupSuggestionTask: Task<Void, Never>? = nil
    private var dropSuggestionTask: Task<Void, Never>? = nil

    enum CreateState { case idle, loading, success(String), error(String) }

    var store: AppStore?
    var daysOfWeek: DaysOfWeekFlags {
        DaysOfWeekFlags(monday: monday, tuesday: tuesday, wednesday: wednesday,
                        thursday: thursday, friday: friday, saturday: saturday, sunday: sunday)
    }

    func addPickup() {
        let t = sanitizeStop(newPickup)
        guard !t.isEmpty else { return }
        if !pickupPoints.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
            pickupPoints.append(t)
        }
        newPickup = ""
        dismissKeyboard()
    }

    func addDrop() {
        let t = sanitizeStop(newDrop)
        guard !t.isEmpty else { return }
        if !dropPoints.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
            dropPoints.append(t)
        }
        newDrop = ""
        dismissKeyboard()
    }

    /// Filter out emoji + zero-width chars + cap to 60 chars so a paste
    /// from a chat doesn't destabilise the form. Trims surrounding
    /// whitespace.
    private func sanitizeStop(_ raw: String) -> String {
        let allowed: Set<Character> = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ,.-/'&"
        )
        let cleaned = raw.filter { allowed.contains($0) }
        return String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    private func dismissKeyboard() {
        // The user expects the keyboard to drop after they tap "+". The
        // previous implementation left it up; the user had to tap somewhere
        // empty to dismiss it.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    /// Adds a suggestion to the active list, dedupes against what's already
    /// there (case-insensitive), and removes it from the suggestion pool so
    /// the chip disappears from the rail.
    func acceptPickupSuggestion(_ s: PlaceSuggestion) {
        if !pickupPoints.contains(where: { $0.caseInsensitiveCompare(s.displayName) == .orderedSame }) {
            pickupPoints.append(s.displayName)
        }
        pickupSuggestions.removeAll { $0.id == s.id }
        // Top up the rail so multiple accepts don't drain it to empty.
        // The refresh re-runs the MapKit search (or pulls defaults if
        // no Start coord is set), filtering against the freshly-added
        // stop. Cached MapKit responses make this near-free.
        refreshPickupSuggestions()
    }
    func acceptDropSuggestion(_ s: PlaceSuggestion) {
        if !dropPoints.contains(where: { $0.caseInsensitiveCompare(s.displayName) == .orderedSame }) {
            dropPoints.append(s.displayName)
        }
        dropSuggestions.removeAll { $0.id == s.id }
        refreshDropSuggestions()
    }

    /// Called by the view when Start coordinates change. Fires two
    /// fetches in parallel:
    ///   1. Corridor suggestions — labels OTHER drivers used as
    ///      pickups on similar routes (server endpoint, learns from
    ///      route_points). Ranked first because social proof.
    ///   2. MKLocalSearch nearby transit hubs / petrol / 7-11 / etc.
    /// They merge into a single rail with corridor items first; the
    /// view renders a "Popular" badge on chips whose label is in
    /// `popularPickupLabels`.
    func refreshPickupSuggestions() {
        pickupSuggestionTask?.cancel()
        if startCoordinate == nil {
            pickupSuggestions = filteredPickupDefaults(against: pickupPoints)
            popularPickupLabels = []
            return
        }
        guard let coord = startCoordinate else { return }
        let target = CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon)
        let corridor: CLLocationCoordinate2D? = endCoordinate.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let originLat = coord.lat
        let originLng = coord.lon
        let destLat = endCoordinate?.lat
        let destLng = endCoordinate?.lon
        pickupSuggestionTask = Task { [weak self] in
            await MainActor.run { self?.isLoadingPickupSuggestions = true }
            // Run both in parallel. Either can fail independently —
            // we tolerate either coming back empty.
            async let corridorRows: [CorridorSuggestion] =
                (try? await VoygoAPIClient.corridorSuggestions(
                    kind: .pickup,
                    originLat: originLat, originLng: originLng,
                    destLat: destLat, destLng: destLng
                )) ?? []
            async let mapKitHubs: [PlaceSuggestion] =
                (try? await VoygoLocationService.shared.searchNearbyHubs(
                    near: target, purpose: .pickup, corridorAnchor: corridor
                )) ?? []
            let corridorList = await corridorRows
            let mapKit = await mapKitHubs
            await MainActor.run {
                guard let self else { return }
                self.isLoadingPickupSuggestions = false
                self.applyMergedSuggestions(
                    corridor: corridorList,
                    mapKit: mapKit,
                    existing: self.pickupPoints,
                    target: \.pickupSuggestions,
                    popularTarget: \.popularPickupLabels,
                    fallback: self.filteredPickupDefaults(against: self.pickupPoints)
                )
            }
        }
    }
    func refreshDropSuggestions() {
        dropSuggestionTask?.cancel()
        if endCoordinate == nil {
            dropSuggestions = filteredDropDefaults(against: dropPoints)
            popularDropLabels = []
            return
        }
        guard let coord = endCoordinate else { return }
        let target = CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon)
        let originLat = startCoordinate?.lat
        let originLng = startCoordinate?.lon
        let destLat = coord.lat
        let destLng = coord.lon
        dropSuggestionTask = Task { [weak self] in
            await MainActor.run { self?.isLoadingDropSuggestions = true }
            async let corridorRows: [CorridorSuggestion] =
                (try? await VoygoAPIClient.corridorSuggestions(
                    kind: .drop,
                    originLat: originLat, originLng: originLng,
                    destLat: destLat, destLng: destLng
                )) ?? []
            // No corridor anchor for the MapKit side — riders want
            // to be dropped AT the destination, not halfway there.
            async let mapKitHubs: [PlaceSuggestion] =
                (try? await VoygoLocationService.shared.searchNearbyHubs(
                    near: target, purpose: .drop, corridorAnchor: nil
                )) ?? []
            let corridorList = await corridorRows
            let mapKit = await mapKitHubs
            await MainActor.run {
                guard let self else { return }
                self.isLoadingDropSuggestions = false
                self.applyMergedSuggestions(
                    corridor: corridorList,
                    mapKit: mapKit,
                    existing: self.dropPoints,
                    target: \.dropSuggestions,
                    popularTarget: \.popularDropLabels,
                    fallback: self.filteredDropDefaults(against: self.dropPoints)
                )
            }
        }
    }

    /// Merges corridor suggestions in front of MapKit results,
    /// dedups by lowercased label, hides anything already added by
    /// the driver, and falls back to the static popular-hubs list
    /// if both sources came back empty. Writes the result back into
    /// the @Observable property `target` AND tracks which labels
    /// came from the corridor source in `popularTarget` so the UI
    /// can render a badge.
    private func applyMergedSuggestions(
        corridor: [CorridorSuggestion],
        mapKit: [PlaceSuggestion],
        existing: [String],
        target: ReferenceWritableKeyPath<CreateRouteViewModel, [PlaceSuggestion]>,
        popularTarget: ReferenceWritableKeyPath<CreateRouteViewModel, Set<String>>,
        fallback: [PlaceSuggestion]
    ) {
        let existingLower = Set(existing.map { $0.lowercased() })
        var merged: [PlaceSuggestion] = []
        var seen = Set<String>()
        var popular = Set<String>()
        // Corridor first — social signal wins.
        for row in corridor {
            let lower = row.label.lowercased()
            if existingLower.contains(lower) || seen.contains(lower) { continue }
            seen.insert(lower)
            popular.insert(lower)
            merged.append(row.toPlaceSuggestion())
        }
        // Then MapKit results that haven't already been seen.
        for hub in mapKit {
            let lower = hub.displayName.lowercased()
            if existingLower.contains(lower) || seen.contains(lower) { continue }
            seen.insert(lower)
            merged.append(hub)
        }
        self[keyPath: target] = merged.isEmpty ? fallback : merged
        self[keyPath: popularTarget] = popular
    }

    /// Filter the popular PICKUP hubs list against already-added stops
    /// so we don't suggest a duplicate. Empty-state fallback for the
    /// pickup rail.
    private func filteredPickupDefaults(against existing: [String]) -> [PlaceSuggestion] {
        let lower = Set(existing.map { $0.lowercased() })
        return VoygoLocationService.popularLocalHubs.filter {
            !lower.contains($0.displayName.lowercased())
        }
    }

    /// Filter the popular DROP destinations against already-added drops.
    /// Different list from pickup defaults — biased toward workplaces,
    /// schools and hospitals (where riders actually go) rather than
    /// transit hubs (where riders wait).
    private func filteredDropDefaults(against existing: [String]) -> [PlaceSuggestion] {
        let lower = Set(existing.map { $0.lowercased() })
        return VoygoLocationService.popularLocalDestinations.filter {
            !lower.contains($0.displayName.lowercased())
        }
    }

    /// Cancel both pickup/drop suggestion tasks. Called from
    /// CreateRouteView's `.onDisappear` so a 3-step MKLocalSearch chain
    /// doesn't keep firing into a dismissed screen.
    func cancelSuggestionTasks() {
        pickupSuggestionTask?.cancel()
        dropSuggestionTask?.cancel()
        pickupSuggestionTask = nil
        dropSuggestionTask = nil
    }

    /// Bridge to drive a SwiftUI `DatePicker` against `departureTime`
    /// while preserving the existing `HH:mm` String shape downstream.
    var departureTimeAsDateBinding: Binding<Date> {
        Binding(
            get: { [self] in self.dateFromHHmm(self.departureTime) ?? Date() },
            set: { [self] newValue in self.departureTime = self.hhmmFromDate(newValue) }
        )
    }

    private func dateFromHHmm(_ s: String) -> Date? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())
    }

    private func hhmmFromDate(_ d: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: d)
        let m = cal.component(.minute, from: d)
        return String(format: "%02d:%02d", h, m)
    }

    func createRoute() {
        guard let store else { return }
        createState = .loading
        Task {
            // Vehicle identity is intentionally NOT passed here — the
            // server reads it from the driver's profile (PUT
            // /users/me/vehicle) via a JOIN. Drivers set it once on
            // Profile and every route reflects the current values.
            let result = await store.createRoute(startLocation: startLocation, endLocation: endLocation,
                                                departureTime: departureTime, seatCount: seatCount, pricePerSeat: pricePerSeat,
                                                carType: carType, daysOfWeek: daysOfWeek,
                                                pickupNames: pickupPoints, dropNames: dropPoints)
            switch result {
            case .success(let id): createState = .success(id)
            case .failure(let err): createState = .error(err.localizedDescription)
            }
        }
    }
}

struct CreateRouteView: View {
    var onBack: () -> Void
    var onCreated: (String) -> Void
    @Environment(AppStore.self) private var store
    @State private var vm = CreateRouteViewModel()

    /// Which field, if any, is currently picking on the map. Driving the
    /// sheet from an enum + Identifiable wrapper keeps a single sheet
    /// presenter (vs two `.sheet(isPresented:)` modifiers that can race
    /// when the user taps one row right after dismissing the other).
    @State private var picker: PickerTarget? = nil

    private enum PickerTarget: Identifiable, Hashable {
        case start, end
        var id: Self { self }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Create Route", onBack: onBack)
                    .background(VoygoTheme.background)

                ScrollView {
                    VStack(spacing: 16) {
                        // Basic info
                        VoygoCard {
                            VStack(spacing: 14) {
                                SectionHeader(title: "Route Info")
                                LocationPickerRow(
                                    label: "Start Location",
                                    placeholder: "Pick on map · e.g. Komtar",
                                    icon: "mappin.circle.fill",
                                    iconColor: VoygoTheme.success,
                                    value: vm.startLocation,
                                    onTap: { picker = .start }
                                )
                                LocationPickerRow(
                                    label: "Destination",
                                    placeholder: "Pick on map · e.g. Bayan Lepas",
                                    icon: "flag.checkered.circle.fill",
                                    iconColor: VoygoTheme.primary,
                                    value: vm.endLocation,
                                    onTap: { picker = .end }
                                )
                                // Native DatePicker keeps the input strictly
                                // valid (no `??::,,..` garbage) and is what
                                // VoiceOver users expect for time entry.
                                // The legacy String-shaped `vm.departureTime`
                                // is preserved via a Date↔String binding
                                // so AppStore.createRoute keeps its existing
                                // signature.
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("DEPARTURE TIME")
                                        .font(.caption2.weight(.heavy))
                                        .tracking(1.2)
                                        .foregroundColor(VPalette.textHint)
                                    DatePicker(
                                        "Departure",
                                        selection: vm.departureTimeAsDateBinding,
                                        displayedComponents: [.hourAndMinute]
                                    )
                                    .labelsHidden()
                                    .datePickerStyle(.compact)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .frame(height: 54)
                                    .background(VPalette.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(VPalette.border, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                HStack(spacing: 12) {
                                    NumericStepperRow(
                                        // Stepper cap tracks the car body —
                                        // sedan/hatch/EV: 4, SUV: 6. Drivers
                                        // physically can't seat 8 in a Myvi,
                                        // so the form shouldn't let them list
                                        // that many.
                                        label: "SEATS",
                                        value: $vm.seatCount,
                                        range: 1...vm.carType.maxPassengerSeats,
                                        step: 1,
                                        suffix: nil
                                    )
                                    NumericStepperRow(
                                        label: "PRICE/SEAT",
                                        value: $vm.pricePerSeat,
                                        range: 1...500,
                                        step: 1,
                                        suffix: "RM"
                                    )
                                }
                                // Small hint that the cap depends on the car
                                // they picked — surfaces the rule without a
                                // disabled-state mystery.
                                Text("Up to \(vm.carType.maxPassengerSeats) passengers in a \(vm.carType.label)")
                                    .font(.caption2)
                                    .foregroundColor(VPalette.textHint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(16)
                        }

                        // Car type
                        VoygoCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Car Type")
                                HStack(spacing: 8) {
                                    ForEach(CarType.allCases) { type in
                                        Button(action: {
                                            vm.carType = type
                                            // Clamp seats if the new body is smaller. A
                                            // driver who set 6 seats for an SUV then
                                            // switched to a Sedan should see seats drop
                                            // to 4 automatically instead of a silent
                                            // server-side validation failure.
                                            if vm.seatCount > type.maxPassengerSeats {
                                                vm.seatCount = type.maxPassengerSeats
                                            }
                                        }) {
                                            VStack(spacing: 4) {
                                                Image(systemName: type.icon)
                                                    .font(.title3)
                                                    .foregroundColor(vm.carType == type ? .white : VoygoTheme.textSecondary)
                                                Text(type.label).font(.caption2.bold())
                                                    .foregroundColor(vm.carType == type ? .white : VoygoTheme.textHint)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(vm.carType == type ? VoygoTheme.primary : VoygoTheme.surfaceHigh)
                                            .cornerRadius(10)
                                        }
                                    }
                                }
                                // Vehicle identity is owned by the
                                // driver profile, not the route — set
                                // it once on Profile → Your vehicle
                                // and every route reflects it. Show a
                                // soft hint here when nothing's set yet
                                // so the driver doesn't ship a route
                                // riders can't visually identify.
                                if (store.currentUser.plateNumber ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                                    HStack(spacing: 10) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(VPalette.warning)
                                            .font(.subheadline.weight(.heavy))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Add your vehicle to Profile")
                                                .font(.caption.weight(.heavy))
                                                .foregroundColor(VPalette.text)
                                            Text("Plate + colour go on your profile so riders can spot the right car. Set once, applies to every route.")
                                                .font(.caption2)
                                                .foregroundColor(VPalette.textHint)
                                        }
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(VPalette.warning.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: "car.side.fill")
                                            .foregroundColor(VPalette.primary)
                                            .font(.subheadline.weight(.heavy))
                                        Text(vehicleHint)
                                            .font(.caption2)
                                            .foregroundColor(VPalette.textSec)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(16)
                        }

                        // Days of week
                        VoygoCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Days of Week")
                                HStack(spacing: 6) {
                                    DayChip(label: "M", selected: vm.monday,    action: { vm.monday    = !vm.monday })
                                    DayChip(label: "T", selected: vm.tuesday,   action: { vm.tuesday   = !vm.tuesday })
                                    DayChip(label: "W", selected: vm.wednesday, action: { vm.wednesday = !vm.wednesday })
                                    DayChip(label: "T", selected: vm.thursday,  action: { vm.thursday  = !vm.thursday })
                                    DayChip(label: "F", selected: vm.friday,    action: { vm.friday    = !vm.friday })
                                    DayChip(label: "S", selected: vm.saturday,  action: { vm.saturday  = !vm.saturday })
                                    DayChip(label: "S", selected: vm.sunday,    action: { vm.sunday    = !vm.sunday })
                                }
                            }
                            .padding(16)
                        }

                        // Pickup points
                        StopsCard(
                            title: "Pickup Points",
                            stops: $vm.pickupPoints,
                            newStop: $vm.newPickup,
                            icon: "mappin.circle.fill",
                            color: VoygoTheme.accent,
                            suggestions: vm.pickupSuggestions,
                            isLoadingSuggestions: vm.isLoadingPickupSuggestions,
                            suggestionsAnchor: vm.startCoordinate?.displayName,
                            popularLabels: vm.popularPickupLabels,
                            onAdd: vm.addPickup,
                            onAcceptSuggestion: vm.acceptPickupSuggestion
                        )

                        // Drop points
                        StopsCard(
                            title: "Drop Points",
                            stops: $vm.dropPoints,
                            newStop: $vm.newDrop,
                            icon: "flag.checkered.circle.fill",
                            color: VoygoTheme.warning,
                            suggestions: vm.dropSuggestions,
                            isLoadingSuggestions: vm.isLoadingDropSuggestions,
                            suggestionsAnchor: vm.endCoordinate?.displayName,
                            popularLabels: vm.popularDropLabels,
                            onAdd: vm.addDrop,
                            onAcceptSuggestion: vm.acceptDropSuggestion
                        )

                        // Submit
                        VStack(spacing: 10) {
                            PrimaryButton(
                                "Save Recurring Route",
                                isLoading: { if case .loading = vm.createState { return true }; return false }(),
                                isEnabled: canSaveRoute,
                                action: vm.createRoute
                            )
                            if case .error(let msg) = vm.createState {
                                VErrorBanner(message: msg, onRetry: vm.createRoute)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    // Bottom clearance for the floating tab bar — without
                    // this the Save button + the last Drop-Points card sit
                    // underneath the bar and look like the screen has run
                    // out of scrollable content. `VTabBarLayout.clearance`
                    // matches the bar height the rest of the app uses.
                    .padding(.bottom, VTabBarLayout.clearance)
                }
                // Tap outside the keyboard to dismiss it AND let the user
                // drag the scroll view down without first dismissing the
                // keyboard manually. Critical on the Seats / Price fields
                // which sit halfway down the form.
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            vm.store = store
            // Seed the suggestion rails immediately with popular KL
            // hubs so the form has visible chips before the user picks
            // Start/Destination. MapKit corridor results replace these
            // once both endpoints are picked.
            vm.refreshPickupSuggestions()
            vm.refreshDropSuggestions()
        }
        .onChange(of: { if case .success(let id) = vm.createState { return id }; return "" }()) { _, id in
            if !id.isEmpty { onCreated(id) }
        }
        // Both endpoints feed both rails now (corridor sampling), so a
        // change to either coordinate refreshes both pickup AND drop
        // suggestion lists. Cheap — MKLocalSearch results cache.
        .onChange(of: vm.startCoordinate) { _, _ in
            vm.refreshPickupSuggestions()
            vm.refreshDropSuggestions()
        }
        .onChange(of: vm.endCoordinate) { _, _ in
            vm.refreshPickupSuggestions()
            vm.refreshDropSuggestions()
        }
        // If the user clears the Start/Destination text fields manually
        // (e.g. by retyping a different address), wipe the captured
        // coordinate too — otherwise the suggestion rail keeps proposing
        // hubs near a city the route no longer starts/ends in.
        .onChange(of: vm.startLocation) { _, value in
            if value.trimmingCharacters(in: .whitespaces).isEmpty && vm.startCoordinate != nil {
                vm.startCoordinate = nil
                vm.pickupSuggestions = []
            }
        }
        .onChange(of: vm.endLocation) { _, value in
            if value.trimmingCharacters(in: .whitespaces).isEmpty && vm.endCoordinate != nil {
                vm.endCoordinate = nil
                vm.dropSuggestions = []
            }
        }
        .sheet(item: $picker) { target in
            mapPicker(for: target)
        }
        .onDisappear {
            // The 3-call MKLocalSearch chain should not outlive the
            // screen. Cancel both running tasks so they don't update
            // @Published state on a deallocated VM.
            vm.cancelSuggestionTasks()
        }
    }

    @ViewBuilder
    private func mapPicker(for target: PickerTarget) -> some View {
        let title = target == .start ? "Where from?" : "Where to?"
        PlacePickerSheet(
            title: title,
            onPick: { suggestion in
                switch target {
                case .start:
                    vm.startLocation = suggestion.displayName
                    vm.startCoordinate = suggestion
                case .end:
                    vm.endLocation = suggestion.displayName
                    vm.endCoordinate = suggestion
                }
                picker = nil
            },
            onCancel: { picker = nil }
        )
    }

    /// Save button is only enabled once the route makes minimum sense:
    /// both endpoints filled, departure time parses as HH:mm, seats and
    /// price > 0. Anything weaker would let the AppStore validation fail
    /// with a vague "required" toast instead of a localized button hint.
    private var canSaveRoute: Bool {
        let s = vm.startLocation.trimmingCharacters(in: .whitespaces)
        let e = vm.endLocation.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !e.isEmpty else { return false }
        let parts = vm.departureTime.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return false }
        return vm.seatCount > 0 && vm.pricePerSeat > 0
    }

    /// Short, human-readable summary of the driver's current vehicle
    /// — shown on Create Route when the profile is already filled in
    /// so the driver can sanity-check what riders will see.
    private var vehicleHint: String {
        let plate = (store.currentUser.plateNumber ?? "").trimmingCharacters(in: .whitespaces)
        let color = (store.currentUser.carColor ?? "").trimmingCharacters(in: .whitespaces)
        let model = (store.currentUser.carModel ?? "").trimmingCharacters(in: .whitespaces)
        let descriptor = [color, model].filter { !$0.isEmpty }.joined(separator: " ")
        if descriptor.isEmpty { return "Riders will see: \(plate)" }
        return "Riders will see: \(plate) · \(descriptor)"
    }
}

// MARK: - NumericStepperRow
//
// Card-shaped Int picker with a tappable label, big −/+ buttons, AND
// a tappable centre number that opens a numeric keyboard for fast
// jumps (e.g. RM 50 instead of tapping + fifty times). Used on the
// Create Route form for both Seats and Price/Seat.

struct NumericStepperRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    /// Optional unit suffix shown to the left of the number ("RM 50").
    let suffix: String?

    @State private var isEditing: Bool = false
    @State private var editingText: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundColor(VPalette.textHint)
            HStack(spacing: 0) {
                stepperButton(systemName: "minus", enabled: value > range.lowerBound) {
                    value = max(range.lowerBound, value - step)
                }
                centre
                stepperButton(systemName: "plus", enabled: value < range.upperBound) {
                    value = min(range.upperBound, value + step)
                }
            }
            .frame(height: 48)
            .background(VPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(VPalette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }

    private var centre: some View {
        ZStack {
            if isEditing {
                HStack(spacing: 4) {
                    if let suffix { Text(suffix).font(.footnote.weight(.heavy)).foregroundColor(VPalette.textSec) }
                    TextField("", text: $editingText)
                        .keyboardType(.numberPad)
                        .font(.body.weight(.heavy))
                        .foregroundColor(VPalette.text)
                        .multilineTextAlignment(.center)
                        .focused($fieldFocused)
                        .frame(minWidth: 40)
                        .onSubmit(commitEdit)
                        .onChange(of: fieldFocused) { _, focused in
                            if !focused { commitEdit() }
                        }
                }
            } else {
                Button {
                    editingText = String(value)
                    isEditing = true
                    fieldFocused = true
                } label: {
                    HStack(spacing: 4) {
                        if let suffix { Text(suffix).font(.footnote.weight(.heavy)).foregroundColor(VPalette.textSec) }
                        Text("\(value)")
                            .font(.body.weight(.heavy))
                            .foregroundColor(VPalette.text)
                            .contentTransition(.numericText(value: Double(value)))
                            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: value)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label) \(value). Tap to type.")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepperButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.heavy))
                .foregroundColor(enabled ? VPalette.primary : VPalette.textHint.opacity(0.5))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func commitEdit() {
        defer { isEditing = false }
        let trimmed = editingText.trimmingCharacters(in: .whitespaces)
        guard let parsed = Int(trimmed) else { return }
        value = min(range.upperBound, max(range.lowerBound, parsed))
    }
}

#Preview("NumericStepperRow") {
    StatefulPreviewWrapper(3) { value in
        VStack(spacing: 16) {
            NumericStepperRow(label: "SEATS",      value: value,           range: 1...20, step: 1, suffix: nil)
            NumericStepperRow(label: "PRICE/SEAT", value: .constant(8),    range: 1...500, step: 1, suffix: "RM")
        }
        .padding()
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State var value: Value
    let content: (Binding<Value>) -> Content
    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: initial)
        self.content = content
    }
    var body: some View { content($value) }
}

/// Tappable row that looks like a VoygoTextField but, instead of accepting
/// keyboard input, opens the map picker. Shows the picked label or a hint
/// placeholder, and a pin icon so the user knows it's a location field.
private struct LocationPickerRow: View {
    let label: String
    let placeholder: String
    let icon: String
    let iconColor: Color
    let value: String
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(VoygoTheme.textSecondary)
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundColor(iconColor)
                    VStack(alignment: .leading, spacing: 2) {
                        if value.isEmpty {
                            Text(placeholder)
                                .font(.subheadline)
                                .foregroundColor(VoygoTheme.textHint)
                                .lineLimit(1)
                        } else {
                            Text(value)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(VoygoTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(VoygoTheme.textHint)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .background(VoygoTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(value.isEmpty ? VoygoTheme.outline.opacity(0.7) : VoygoTheme.primary.opacity(0.6), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct StopsCard: View {
    let title: String
    @Binding var stops: [String]
    @Binding var newStop: String
    let icon: String; let color: Color
    /// MKLocalSearch-derived nearby hubs the driver can add with one tap.
    /// Empty = no Start/Destination picked yet (or none found nearby).
    var suggestions: [PlaceSuggestion] = []
    var isLoadingSuggestions: Bool = false
    /// Display name of the anchor (Start address for pickups, Destination
    /// for drops) — used in the section subtitle so the user knows where
    /// the suggestions came from.
    var suggestionsAnchor: String? = nil
    /// Lowercased labels that came from the corridor-suggestions
    /// endpoint (popular on similar routes). The chip renders a
    /// "🔥 Popular" badge so the driver knows other commuters have
    /// already picked this spot.
    var popularLabels: Set<String> = []
    let onAdd: () -> Void
    var onAcceptSuggestion: ((PlaceSuggestion) -> Void)? = nil

    var body: some View {
        VoygoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title)

                if isLoadingSuggestions || !suggestions.isEmpty {
                    suggestionsRail
                }

                HStack(spacing: 8) {
                    VoygoTextField(label: "Add stop", text: $newStop, placeholder: "e.g. Komtar")
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2).foregroundColor(color)
                    }
                    .disabled(newStop.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !stops.isEmpty {
                    ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                        HStack {
                            Image(systemName: icon).foregroundColor(color).font(.caption)
                            Text(stop).font(.subheadline).foregroundColor(VoygoTheme.textPrimary)
                            Spacer()
                            Button(action: { stops.remove(at: i) }) {
                                Image(systemName: "xmark.circle").foregroundColor(VoygoTheme.textHint).font(.caption)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var suggestionsRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
                if let anchor = suggestionsAnchor, !anchor.isEmpty {
                    Text("Suggested near \(shortAnchor(anchor))")
                        .font(.caption.weight(.bold))
                        .foregroundColor(VoygoTheme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("Suggested nearby")
                        .font(.caption.weight(.bold))
                        .foregroundColor(VoygoTheme.textSecondary)
                }
                Spacer()
                if isLoadingSuggestions {
                    ProgressView().controlSize(.mini)
                }
            }

            if isLoadingSuggestions && suggestions.isEmpty {
                Text("Looking up transit hubs…")
                    .font(.caption)
                    .foregroundColor(VoygoTheme.textHint)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { s in
                            let isPopular = popularLabels.contains(s.displayName.lowercased())
                            Button {
                                onAcceptSuggestion?(s)
                            } label: {
                                HStack(spacing: 6) {
                                    // Popular chips lead with a flame
                                    // so the social signal is visible
                                    // even before the label.
                                    Image(systemName: isPopular ? "flame.fill" : "plus.circle.fill")
                                        .font(.caption.weight(.bold))
                                    Text(s.displayName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    if isPopular {
                                        Text("Popular")
                                            .font(.caption2.weight(.black))
                                            .tracking(0.3)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.white)
                                            .foregroundColor(color)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundColor(isPopular ? .white : color)
                                .background(isPopular ? color : color.opacity(0.12))
                                .overlay(Capsule().stroke(isPopular ? color : color.opacity(0.35), lineWidth: 1))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    /// Trim long reverse-geocoded addresses ("Lot 1, Persiaran XYZ, …, Subang
    /// Jaya, Selangor") down to the first comma-separated chunk so the
    /// "Suggested near …" header stays one line.
    private func shortAnchor(_ s: String) -> String {
        if let comma = s.firstIndex(of: ",") {
            return String(s[..<comma])
        }
        return String(s.prefix(28))
    }
}

// MARK: - Edit Route Sheet

/// Identifiable wrapper so the `.sheet(item:)` modifier on
/// DriverDashboardView can re-render when `editingRouteId` changes.
private struct EditRouteSheetID: Identifiable {
    let routeId: String
    var id: String { routeId }
}

/// Driver-only edit sheet. Pre-fills price / seats / car type /
/// start+end labels from the existing route and patches them via
/// `AppStore.patchRoute`. Pickup/drop POINT editing is excluded
/// from this iteration — the existing flow surfaces those during
/// route creation only, and re-editing the point set requires a
/// separate spatial validation pass we haven't built yet.
///
/// Price-freeze guard: if the route has active subscribers the
/// price field is disabled with an inline hint. The server ALSO
/// rejects with 409 — defense in depth.
struct EditRouteSheet: View {
    let route: RecurringRoute
    let hasActiveSubscribers: Bool
    var onClose: () -> Void

    @Environment(AppStore.self) private var store
    @State private var pricePerSeat: Int
    @State private var seatCount: Int
    @State private var carType: CarType
    @State private var startLocation: String
    @State private var endLocation: String
    @State private var submitState: SubmitState = .idle
    @State private var errorMessage: String? = nil

    enum SubmitState: Equatable { case idle, submitting, success }

    init(route: RecurringRoute, hasActiveSubscribers: Bool, onClose: @escaping () -> Void) {
        self.route = route
        self.hasActiveSubscribers = hasActiveSubscribers
        self.onClose = onClose
        _pricePerSeat = State(initialValue: route.pricePerSeat)
        _seatCount = State(initialValue: route.seatCount)
        _carType = State(initialValue: route.carType)
        _startLocation = State(initialValue: route.startLocation)
        _endLocation = State(initialValue: route.endLocation)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    sectionCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(S.driverEditPricing)
                                .font(.subheadline.weight(.heavy))
                                .foregroundColor(VoygoTheme.textPrimary)

                            HStack {
                                Text(S.driverEditPricePerSeat)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(VoygoTheme.textSecondary)
                                Spacer()
                                Stepper(value: $pricePerSeat, in: 1...500, step: 1) {
                                    Text(Formatters.ringgit(pricePerSeat))
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundColor(VoygoTheme.primary)
                                }
                                .disabled(hasActiveSubscribers)
                            }
                            if hasActiveSubscribers {
                                Text(S.driverEditPriceLocked)
                                    .font(.caption2)
                                    .foregroundColor(VoygoTheme.warning)
                            }

                            HStack {
                                Text(S.driverEditSeats)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(VoygoTheme.textSecondary)
                                Spacer()
                                Stepper(value: $seatCount, in: 1...8) {
                                    Text("\(seatCount)")
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundColor(VoygoTheme.textPrimary)
                                }
                            }
                        }
                    }

                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(S.driverEditRouteLabels)
                                .font(.subheadline.weight(.heavy))
                                .foregroundColor(VoygoTheme.textPrimary)
                            VoygoTextField(label: S.driverEditStart, text: $startLocation,
                                           placeholder: route.startLocation)
                            VoygoTextField(label: S.driverEditEnd, text: $endLocation,
                                           placeholder: route.endLocation)
                        }
                    }

                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(S.driverEditCarType)
                                .font(.subheadline.weight(.heavy))
                                .foregroundColor(VoygoTheme.textPrimary)
                            // Use a Picker so the menu adapts naturally
                            // to AX sizes; segmented would clip labels.
                            Picker("", selection: $carType) {
                                ForEach(CarType.allCases, id: \.self) { ct in
                                    Text(ct.label).tag(ct)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(VoygoTheme.primary)
                        }
                    }

                    if let err = errorMessage {
                        InfoBanner(message: err, color: VoygoTheme.danger) {
                            errorMessage = nil
                        }
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 6) {
                            if submitState == .submitting { ProgressView().controlSize(.small).tint(.white) }
                            Text(submitState == .success ? S.driverEditSaved : S.driverEditSave)
                        }
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(VoygoTheme.primary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasChanges || submitState == .submitting)
                    .opacity(hasChanges ? 1.0 : 0.5)
                }
                .padding(16)
            }
            .background(VoygoTheme.background)
            .navigationTitle(S.driverEditRoute)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(S.cancel) { onClose() }
                }
            }
        }
    }

    /// At least one field has diverged from the route's current
    /// values — gates the Save button so a no-op submit can't fire.
    private var hasChanges: Bool {
        pricePerSeat != route.pricePerSeat ||
        seatCount != route.seatCount ||
        carType != route.carType ||
        startLocation != route.startLocation ||
        endLocation != route.endLocation
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(14)
        .background(VoygoTheme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VoygoTheme.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func submit() async {
        guard submitState != .submitting else { return }
        submitState = .submitting
        errorMessage = nil
        // Send only the fields that diverged so the server's diff
        // tracking + audit log captures intent cleanly.
        let result = await store.patchRoute(
            routeId: route.id,
            pricePerSeat: pricePerSeat != route.pricePerSeat ? pricePerSeat : nil,
            seatCount: seatCount != route.seatCount ? seatCount : nil,
            carType: carType != route.carType ? carType.rawValue : nil,
            startLocation: startLocation != route.startLocation ? startLocation : nil,
            endLocation: endLocation != route.endLocation ? endLocation : nil
        )
        switch result {
        case .success:
            submitState = .success
            // Auto-dismiss after a beat so the driver sees the
            // success confirmation flash.
            try? await Task.sleep(nanoseconds: 600_000_000)
            onClose()
        case .failure(let err):
            submitState = .idle
            errorMessage = err.localizedDescription
        }
    }
}
