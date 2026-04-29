import SwiftUI

// MARK: - Driver Route Dashboard (mirrors DriverRouteDashboardScreen.kt)

struct DriverDashboardView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onOpenCalendar: (String) -> Void

    @State private var actionResult: String? = nil
    @State private var actionError: String? = nil

    var dashboards: [DriverRouteDashboard] { store.driverDashboards() }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Driver Dashboard", showBack: true, onBack: onBack)
                    .background(VoygoTheme.background)

                if dashboards.isEmpty {
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
                                    onTogglePause: { routeId, isActive in
                                        Task {
                                            let result = await store.setRouteActive(routeId: routeId, active: !isActive)
                                            if case .failure(let error) = result {
                                                actionError = error.localizedDescription
                                            } else {
                                                actionResult = isActive ? "Route paused." : "Route resumed."
                                            }
                                        }
                                    },
                                    onSetWeekdays: { routeId, time in
                                        Task {
                                            let r = await store.updateRouteSchedule(routeId: routeId, departureTime: time, daysOfWeek: .weekdays)
                                            if case .failure(let e) = r { actionError = e.localizedDescription }
                                            else { actionResult = "Schedule updated to weekdays." }
                                        }
                                    },
                                    onSetAllDays: { routeId, time in
                                        Task {
                                            let r = await store.updateRouteSchedule(routeId: routeId, departureTime: time, daysOfWeek: .allDays)
                                            if case .failure(let e) = r { actionError = e.localizedDescription }
                                            else { actionResult = "Schedule updated to all days." }
                                        }
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
        }
    }
}

struct DriverRouteCard: View {
    let dashboard: DriverRouteDashboard
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
                            Image(systemName: route.activeStatus == .active ? "pause.circle.fill" : "play.circle.fill")
                            Text(route.activeStatus == .active ? "Pause Route" : "Resume Route")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(route.activeStatus == .active ? VoygoTheme.warning.opacity(0.15) : VoygoTheme.success.opacity(0.15))
                        .foregroundColor(route.activeStatus == .active ? VoygoTheme.warning : VoygoTheme.success)
                        .cornerRadius(12)
                    }
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

    enum CreateState { case idle, loading, success(String), error(String) }

    var store: AppStore?
    var daysOfWeek: DaysOfWeekFlags {
        DaysOfWeekFlags(monday: monday, tuesday: tuesday, wednesday: wednesday,
                        thursday: thursday, friday: friday, saturday: saturday, sunday: sunday)
    }

    func addPickup() { let t = newPickup.trimmingCharacters(in: .whitespaces); if !t.isEmpty { pickupPoints.append(t); newPickup = "" } }
    func addDrop()   { let t = newDrop.trimmingCharacters(in: .whitespaces);   if !t.isEmpty { dropPoints.append(t);   newDrop = "" } }

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

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Create Route", showBack: true, onBack: onBack)
                    .background(VoygoTheme.background)

                ScrollView {
                    VStack(spacing: 16) {
                        // Basic info
                        VoygoCard {
                            VStack(spacing: 14) {
                                SectionHeader(title: "Route Info")
                                VoygoTextField(label: "Start Location", text: $vm.startLocation, placeholder: "e.g. Damansara")
                                VoygoTextField(label: "Destination",    text: $vm.endLocation,   placeholder: "e.g. KLCC")
                                VoygoTextField(label: "Departure Time (HH:mm)", text: $vm.departureTime,
                                               placeholder: "08:00", keyboardType: .numbersAndPunctuation)
                                HStack(spacing: 12) {
                                    VoygoTextField(label: "Seats", text: $vm.seatCount, placeholder: "3", keyboardType: .numberPad)
                                    VoygoTextField(label: "Price/Seat (RM)", text: $vm.pricePerSeat, placeholder: "8", keyboardType: .numberPad)
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
                        StopsCard(title: "Pickup Points", stops: $vm.pickupPoints, newStop: $vm.newPickup,
                                  icon: "mappin.circle.fill", color: VoygoTheme.accent, onAdd: vm.addPickup)

                        // Drop points
                        StopsCard(title: "Drop Points", stops: $vm.dropPoints, newStop: $vm.newDrop,
                                  icon: "flag.checkered.circle.fill", color: VoygoTheme.warning, onAdd: vm.addDrop)

                        // Submit
                        VStack(spacing: 10) {
                            PrimaryButton("Save Recurring Route",
                                          isLoading: { if case .loading = vm.createState { return true }; return false }(),
                                          action: vm.createRoute)
                            if case .error(let msg) = vm.createState {
                                HStack { Image(systemName: "exclamationmark.circle.fill").foregroundColor(VoygoTheme.danger)
                                    Text(msg).font(.caption).foregroundColor(VoygoTheme.danger) }
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
    }
}

private struct StopsCard: View {
    let title: String
    @Binding var stops: [String]
    @Binding var newStop: String
    let icon: String; let color: Color
    let onAdd: () -> Void

    var body: some View {
        VoygoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: title)
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
}
