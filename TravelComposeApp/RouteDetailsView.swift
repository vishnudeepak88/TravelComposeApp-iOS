import SwiftUI

// MARK: - Route Details (mirrors RouteDetailsScreen.kt)

@MainActor
final class RouteDetailsViewModel: ObservableObject {
    @Published var route: RecurringRoute? = nil
    @Published var subscriptions: [RouteSubscription] = []
    @Published var upcomingRides: [CommuteRideInstance] = []
    @Published var isLoading = false
    @Published var subscribeState: SubscribeState = .idle
    @Published var selectedPickupId: String? = nil
    @Published var selectedDropId: String? = nil
    @Published var numberOfDays = "30"

    enum SubscribeState { case idle, loading, success(String), error(String) }

    var store: AppStore?

    func load(routeId: String) {
        guard let store else { return }
        route = store.routes.first { $0.id == routeId }
        subscriptions = store.subscriptions.filter { $0.routeId == routeId }
        upcomingRides = store.upcomingRides(routeId: routeId)
        selectedPickupId = route?.pickupPoints.first?.id
        selectedDropId   = route?.dropPoints.first?.id
    }

    var availableSeats: Int {
        upcomingRides.first?.seatAvailability ?? (route?.seatCount ?? 0)
    }

    func subscribe() {
        guard let store, let route, let pickupId = selectedPickupId, let dropId = selectedDropId else { return }
        let days = Int(numberOfDays) ?? 30
        subscribeState = .loading
        let result = store.subscribe(routeId: route.id, pickupId: pickupId, dropId: dropId, days: days)
        switch result {
        case .success(let id): subscribeState = .success(id)
        case .failure(let err): subscribeState = .error(err.localizedDescription ?? "Failed")
        }
    }
}

struct RouteDetailsView: View {
    let routeId: String
    var onBack: () -> Void
    @EnvironmentObject var store: AppStore
    @StateObject private var vm = RouteDetailsViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Route Details", showBack: true, onBack: onBack)
                    .background(VoygoTheme.surface)

                if vm.isLoading {
                    LoadingView()
                } else if let route = vm.route {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Route card
                            VoygoCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        AvatarView(initial: String(route.driverName.prefix(1)))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(route.driverName).font(.headline).foregroundColor(VoygoTheme.textPrimary)
                                            HStack(spacing: 4) {
                                                Image(systemName: "star.fill").foregroundColor(.yellow).font(.caption)
                                                Text(String(format: "%.1f", route.reliability.averageRating))
                                                    .font(.caption).foregroundColor(VoygoTheme.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing) {
                                            Text("RM \(route.pricePerSeat)").font(.title2.bold()).foregroundColor(VoygoTheme.primary)
                                            Text("per seat").font(.caption2).foregroundColor(VoygoTheme.textHint)
                                        }
                                    }

                                    Divider().background(VoygoTheme.cardBorder)

                                    RouteInfoRow(icon: "arrow.right.circle.fill", label: "Route",
                                                 value: "\(route.startLocation) → \(route.endLocation)")
                                    RouteInfoRow(icon: "clock.fill", label: "Departure", value: route.departureTime)
                                    RouteInfoRow(icon: "calendar", label: "Schedule", value: route.daysOfWeek.shortLabel)
                                    RouteInfoRow(icon: route.carType.icon, label: "Car type", value: route.carType.label)
                                    RouteInfoRow(icon: "person.3.fill", label: "Available seats", value: "\(vm.availableSeats) of \(route.seatCount)")
                                    RouteInfoRow(icon: "person.badge.plus.fill", label: "Active riders", value: "\(vm.subscriptions.count)")

                                    Divider().background(VoygoTheme.cardBorder)

                                    // Reliability
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Driver Reliability").font(.subheadline.bold()).foregroundColor(VoygoTheme.textPrimary)
                                        HStack(spacing: 0) {
                                            ReliabilityMetric(label: "On-time", value: "\(Int(route.reliability.onTimeRate * 100))%")
                                            Spacer()
                                            ReliabilityMetric(label: "Cancel rate", value: "\(Int(route.reliability.cancellationRate * 100))%")
                                            Spacer()
                                            ReliabilityMetric(label: "Repeat riders", value: "\(route.reliability.repeatRiders)")
                                        }
                                    }
                                }
                                .padding(16)
                            }

                            // Pickup selection
                            VoygoCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(title: "Pickup Point")
                                    ForEach(route.pickupPoints) { point in
                                        Button(action: { vm.selectedPickupId = point.id }) {
                                            HStack(spacing: 12) {
                                                ZStack {
                                                    Circle().fill(vm.selectedPickupId == point.id ? VoygoTheme.primary : VoygoTheme.surfaceHigh)
                                                        .frame(width: 20, height: 20)
                                                    if vm.selectedPickupId == point.id {
                                                        Circle().fill(.white).frame(width: 8, height: 8)
                                                    }
                                                }
                                                Image(systemName: "mappin.circle.fill").foregroundColor(VoygoTheme.accent).font(.subheadline)
                                                Text(point.label).font(.subheadline).foregroundColor(VoygoTheme.textPrimary)
                                                Spacer()
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }
                                }
                                .padding(16)
                            }

                            // Drop selection
                            VoygoCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(title: "Drop Point")
                                    ForEach(route.dropPoints) { point in
                                        Button(action: { vm.selectedDropId = point.id }) {
                                            HStack(spacing: 12) {
                                                ZStack {
                                                    Circle().fill(vm.selectedDropId == point.id ? VoygoTheme.primary : VoygoTheme.surfaceHigh)
                                                        .frame(width: 20, height: 20)
                                                    if vm.selectedDropId == point.id {
                                                        Circle().fill(.white).frame(width: 8, height: 8)
                                                    }
                                                }
                                                Image(systemName: "flag.checkered.circle.fill").foregroundColor(VoygoTheme.warning).font(.subheadline)
                                                Text(point.label).font(.subheadline).foregroundColor(VoygoTheme.textPrimary)
                                                Spacer()
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }
                                }
                                .padding(16)
                            }

                            // Subscription config
                            VoygoCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Subscription")
                                    VoygoTextField(label: "Number of days", text: $vm.numberOfDays, placeholder: "30", keyboardType: .numberPad)
                                    HStack {
                                        Image(systemName: "calendar.badge.clock").foregroundColor(VoygoTheme.textHint).font(.caption)
                                        Text("Starts today · \(vm.numberOfDays.isEmpty ? "30" : vm.numberOfDays) days")
                                            .font(.caption).foregroundColor(VoygoTheme.textHint)
                                    }
                                }
                                .padding(16)
                            }

                            // Subscribe button + state
                            VStack(spacing: 10) {
                                PrimaryButton("Subscribe To Route",
                                              isLoading: { if case .loading = vm.subscribeState { return true }; return false }(),
                                              isEnabled: vm.selectedPickupId != nil && vm.selectedDropId != nil,
                                              action: vm.subscribe)

                                Group {
                                    switch vm.subscribeState {
                                    case .success:
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(VoygoTheme.success)
                                            Text("Subscription active!").font(.subheadline).foregroundColor(VoygoTheme.success)
                                        }
                                    case .error(let msg):
                                        HStack {
                                            Image(systemName: "exclamationmark.circle.fill").foregroundColor(VoygoTheme.danger)
                                            Text(msg).font(.subheadline).foregroundColor(VoygoTheme.danger)
                                        }
                                    default: EmptyView()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 16)
                        .padding(.bottom, 32)
                    }
                } else {
                    EmptyStateView(icon: "questionmark.circle", title: "Route not found", subtitle: "This route may no longer be available")
                }
            }
        }
        .onAppear { vm.store = store; vm.load(routeId: routeId) }
    }
}

private struct RouteInfoRow: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(VoygoTheme.primary).font(.subheadline).frame(width: 18)
            Text(label).font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundColor(VoygoTheme.textPrimary)
        }
    }
}

private struct ReliabilityMetric: View {
    let label: String; let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold()).foregroundColor(VoygoTheme.textPrimary)
            Text(label).font(.caption2).foregroundColor(VoygoTheme.textHint)
        }
    }
}
