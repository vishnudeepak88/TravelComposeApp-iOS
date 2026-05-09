import SwiftUI
import CoreLocation

// MARK: - Driver Route Dashboard (mirrors DriverRouteDashboardScreen.kt)

struct DriverDashboardView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onOpenCalendar: (String) -> Void
    var onOpenPayouts: (() -> Void)? = nil

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

    var dashboards: [DriverRouteDashboard] { store.driverDashboards() }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Driver Dashboard", onBack: onBack) {
                    if let onOpenPayouts {
                        Button(action: onOpenPayouts) {
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(VPalette.primary)
                                .frame(width: 40, height: 40)
                                .background(VPalette.primaryContainer)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Payouts")
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
                    EmptyStateView(icon: "car.badge.plus", title: "No routes yet",
                                   subtitle: "Create your first recurring route to start picking up riders")
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
                                    onCalendar: { onOpenCalendar($0) }
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

    @State private var departureInput: String = ""

    var route: RecurringRoute { dashboard.route }

    var body: some View {
        VoygoCard {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(route.startLocation) → \(route.endLocation)")
                            .font(.headline).foregroundColor(VoygoTheme.textPrimary)
                        Text("RM \(route.pricePerSeat)/seat · \(route.carType.label)")
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
            }
            .padding(16)
        }
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
    var seatCount     = "3"
    var pricePerSeat  = "8"
    var carType: CarType = .sedan
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
    }
    func acceptDropSuggestion(_ s: PlaceSuggestion) {
        if !dropPoints.contains(where: { $0.caseInsensitiveCompare(s.displayName) == .orderedSame }) {
            dropPoints.append(s.displayName)
        }
        dropSuggestions.removeAll { $0.id == s.id }
    }

    /// Called by the view when Start coordinates change. Kicks off a debounced
    /// MKLocalSearch for nearby transit hubs.
    func refreshPickupSuggestions() {
        pickupSuggestionTask?.cancel()
        guard let coord = startCoordinate else { pickupSuggestions = []; return }
        let target = CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon)
        pickupSuggestionTask = Task { [weak self] in
            await MainActor.run { self?.isLoadingPickupSuggestions = true }
            let hubs = (try? await VoygoLocationService.shared.searchNearbyHubs(near: target)) ?? []
            await MainActor.run {
                guard let self else { return }
                self.isLoadingPickupSuggestions = false
                // Hide ones the user has already added so the rail doesn't
                // suggest a duplicate.
                let existing = Set(self.pickupPoints.map { $0.lowercased() })
                self.pickupSuggestions = hubs.filter { !existing.contains($0.displayName.lowercased()) }
            }
        }
    }
    func refreshDropSuggestions() {
        dropSuggestionTask?.cancel()
        guard let coord = endCoordinate else { dropSuggestions = []; return }
        let target = CLLocationCoordinate2D(latitude: coord.lat, longitude: coord.lon)
        dropSuggestionTask = Task { [weak self] in
            await MainActor.run { self?.isLoadingDropSuggestions = true }
            let hubs = (try? await VoygoLocationService.shared.searchNearbyHubs(near: target)) ?? []
            await MainActor.run {
                guard let self else { return }
                self.isLoadingDropSuggestions = false
                let existing = Set(self.dropPoints.map { $0.lowercased() })
                self.dropSuggestions = hubs.filter { !existing.contains($0.displayName.lowercased()) }
            }
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
        let seats = Int(seatCount) ?? 0
        let price = Int(pricePerSeat) ?? 0
        Task {
            let result = await store.createRoute(startLocation: startLocation, endLocation: endLocation,
                                                departureTime: departureTime, seatCount: seats, pricePerSeat: price,
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
                                    placeholder: "Pick on map · e.g. Damansara",
                                    icon: "mappin.circle.fill",
                                    iconColor: VoygoTheme.success,
                                    value: vm.startLocation,
                                    onTap: { picker = .start }
                                )
                                LocationPickerRow(
                                    label: "Destination",
                                    placeholder: "Pick on map · e.g. KLCC",
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
                                        .font(.system(size: 11, weight: .heavy))
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
                                    VStack(alignment: .leading, spacing: 4) {
                                        VoygoTextField(label: "Seats", text: $vm.seatCount, placeholder: "3", keyboardType: .numberPad)
                                        if (Int(vm.seatCount) ?? 0) <= 0 {
                                            Text("Must be 1 or more")
                                                .font(.system(size: 11))
                                                .foregroundColor(VPalette.danger)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        VoygoTextField(label: "Price/Seat (RM)", text: $vm.pricePerSeat, placeholder: "8", keyboardType: .numberPad)
                                        if (Int(vm.pricePerSeat) ?? 0) <= 0 {
                                            Text("Must be RM 1 or more")
                                                .font(.system(size: 11))
                                                .foregroundColor(VPalette.danger)
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        }

                        // Car type
                        VoygoCard {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Car Type")
                                HStack(spacing: 8) {
                                    ForEach(CarType.allCases) { type in
                                        Button(action: { vm.carType = type }) {
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
                    .padding(.vertical, 16)
                }
            }
        }
        .onAppear { vm.store = store }
        .onChange(of: { if case .success(let id) = vm.createState { return id }; return "" }()) { _, id in
            if !id.isEmpty { onCreated(id) }
        }
        .onChange(of: vm.startCoordinate) { _, _ in vm.refreshPickupSuggestions() }
        .onChange(of: vm.endCoordinate) { _, _ in vm.refreshDropSuggestions() }
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
        return (Int(vm.seatCount) ?? 0) > 0 && (Int(vm.pricePerSeat) ?? 0) > 0
    }
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
                        .font(.system(size: 18, weight: .semibold))
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
                        .font(.system(size: 13, weight: .bold))
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
                    VoygoTextField(label: "Add stop", text: $newStop, placeholder: "e.g. Masjid Jamek")
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
                            Button {
                                onAcceptSuggestion?(s)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.caption.weight(.bold))
                                    Text(s.displayName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundColor(color)
                                .background(color.opacity(0.12))
                                .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 1))
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
