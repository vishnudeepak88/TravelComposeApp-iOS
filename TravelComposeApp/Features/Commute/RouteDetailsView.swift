import SwiftUI

// MARK: - Route Details (mirrors RouteDetailsScreen.kt)

@MainActor
@Observable final class RouteDetailsViewModel {
    var route: RecurringRoute? = nil
    var subscriptions: [RouteSubscription] = []
    var upcomingRides: [CommuteRideInstance] = []
    var isLoading = false
    var subscribeState: SubscribeState = .idle
    var selectedPickupId: String? = nil
    var selectedDropId: String? = nil
    var numberOfDays = "30"
    /// Tier picker — defaults to monthly, the most common choice. Daily and
    /// quarterly are exposed in the UI so the rider can opt in.
    var selectedTier: SubscriptionTier = .monthly
    /// When the backend returns a Billplz hosted-checkout URL we hand it to
    /// the view, which presents `BillplzCheckoutSheet`. nil otherwise.
    var pendingPaymentURL: URL? = nil

    enum SubscribeState { case idle, loading, charging, success(String), error(String) }

    var store: AppStore?
    var onSubscribed: ((String) -> Void)?

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

    /// Total in MYR for the rider, applying the tier discount. Single source
    /// of truth — the same formula the receipt + Billplz bill will use.
    var subscriptionTotalMyr: Int {
        guard let route else { return 0 }
        let days = Int(numberOfDays) ?? 30
        return SubscriptionPricing.totalForTier(
            pricePerSeatMyr: route.pricePerSeat,
            tier: selectedTier,
            days: days
        )
    }

    func subscribe() {
        guard let store, let route, let pickupId = selectedPickupId, let dropId = selectedDropId else { return }
        let days = Int(numberOfDays) ?? 30
        let amount = SubscriptionPricing.totalForTier(
            pricePerSeatMyr: route.pricePerSeat,
            tier: selectedTier,
            days: days
        )
        subscribeState = .loading
        Task {
            let result = await store.subscribe(routeId: route.id, pickupId: pickupId, dropId: dropId, days: days, tier: selectedTier)
            switch result {
            case .success(let subscriptionId):
                subscribeState = .charging
                let chargeResult = await store.startCharge(
                    subscriptionId: subscriptionId,
                    routeId: route.id,
                    amountMyr: amount,
                    tier: selectedTier
                )
                switch chargeResult {
                case .success(let charge):
                    if let urlString = charge.paymentUrl, let url = URL(string: urlString), charge.status == .pending {
                        // Live Billplz: present the hosted checkout sheet.
                        // The view's onDismiss handler will fire `onSubscribed`
                        // once the rider returns from the redirect.
                        pendingPaymentURL = url
                        subscribeState = .success(subscriptionId)
                    } else {
                        // Mock mode (or already paid): jump straight to the
                        // celebratory confirmed screen.
                        subscribeState = .success(subscriptionId)
                        load(routeId: route.id)
                        onSubscribed?(subscriptionId)
                    }
                case .failure(let err):
                    // Subscription was created but the charge failed. Auto-
                    // pause it so the rider doesn't believe they're booked
                    // for tomorrow's commute when no money has moved. We
                    // await the pause result so a pause failure surfaces
                    // alongside the payment failure rather than getting
                    // swallowed by a fire-and-forget Task.
                    let pauseResult = await store.updateSubscription(id: subscriptionId, status: .paused)
                    if case .failure(let pauseErr) = pauseResult {
                        subscribeState = .error(
                            "Payment failed (\(err.localizedDescription)) and we couldn't pause the subscription either: \(pauseErr.localizedDescription). Please cancel from My Subscriptions before retrying."
                        )
                    } else {
                        subscribeState = .error("Subscription paused — payment failed: \(err.localizedDescription). Retry from My Subscriptions.")
                    }
                    load(routeId: route.id)
                }
            case .failure(let err):
                subscribeState = .error(err.localizedDescription)
            }
        }
    }

    /// Called when the Billplz checkout sheet closes. `paid: true` means the
    /// `voygo://payments/return?paid=true` deep link fired before
    /// SFSafariViewController dismissed (user actually completed payment).
    /// `paid: false` means they hit Done without paying — pause the
    /// subscription and surface a retry hint instead of celebrating.
    func paymentCheckoutDismissed(paid: Bool) {
        guard let id = pendingPaymentSubscriptionId else {
            pendingPaymentURL = nil
            return
        }
        pendingPaymentURL = nil

        if paid {
            onSubscribed?(id)
            return
        }

        // Abandoned — pause the subscription and tell the user how to retry.
        // Awaited so a pause-failure shows up in the same banner instead
        // of getting silently swallowed.
        Task { [weak self] in
            guard let self, let store = self.store else { return }
            let result = await store.updateSubscription(id: id, status: .paused)
            await MainActor.run {
                if case .failure(let err) = result {
                    self.subscribeState = .error("Payment cancelled — pause also failed: \(err.localizedDescription).")
                } else {
                    self.subscribeState = .error("Payment not completed. Subscription paused — retry from My Subscriptions.")
                }
                if let routeId = self.route?.id { self.load(routeId: routeId) }
            }
        }
    }

    /// Convenience accessor — if the success state holds an id, return it.
    var pendingPaymentSubscriptionId: String? {
        if case .success(let id) = subscribeState { return id }
        return nil
    }
}

extension RouteDetailsViewModel.SubscribeState {
    /// True while the subscribe button should show a spinner — covers both
    /// the subscription-create RPC and the follow-up payment charge.
    var isInFlight: Bool {
        switch self {
        case .loading, .charging: return true
        default:                  return false
        }
    }
}

struct RouteDetailsView: View {
    let routeId: String
    var onBack: () -> Void
    var onSubscribed: ((String) -> Void)? = nil
    @Environment(AppStore.self) private var store
    @State private var vm = RouteDetailsViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Route Details", showBack: true, onBack: onBack)
                    .background(VoygoTheme.background)

                if vm.isLoading {
                    LoadingView()
                } else if let route = vm.route {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Abstract route diagram hero — narrative
                            // visual that anchors the screen before the
                            // dense info card. The diagram is decorative;
                            // the actual map picker lives elsewhere.
                            VRouteDiagram(
                                stops: routeStops(for: route),
                                height: 180,
                                accent: VPalette.success
                            )
                            .padding(.horizontal, 0)

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

                            // Subscription tier picker — daily / monthly / quarterly.
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Tier").font(.caption.weight(.bold)).foregroundColor(VoygoTheme.textSecondary)
                                HStack(spacing: 6) {
                                    ForEach(SubscriptionTier.allCases) { tier in
                                        let on = tier == vm.selectedTier
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                vm.selectedTier = tier
                                            }
                                        } label: {
                                            VStack(spacing: 1) {
                                                Text(tier.label)
                                                    .font(.system(size: 13, weight: .heavy))
                                                Text(tier == .daily ? "Try it" : tier == .monthly ? "10% off" : "15% off")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .opacity(0.85)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: 50)
                                            .foregroundColor(on ? .white : VoygoTheme.textPrimary)
                                            .background(on ? AnyShapeStyle(VoygoTheme.primaryGradient) : AnyShapeStyle(VoygoTheme.surface))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color.clear : VoygoTheme.cardBorder, lineWidth: 1))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                HStack {
                                    Text("Total")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(VoygoTheme.textSecondary)
                                    Spacer()
                                    Text("RM \(vm.subscriptionTotalMyr)")
                                        .font(.title3.weight(.heavy))
                                        .foregroundColor(VoygoTheme.primary)
                                        .monospacedDigit()
                                }
                                .padding(.top, 6)
                            }

                            // Subscribe button + state
                            VStack(spacing: 10) {
                                PrimaryButton(
                                    subscribeButtonTitle,
                                    isLoading: vm.subscribeState.isInFlight,
                                    // Disable on RM 0 totals — happens if the
                                    // user clears `numberOfDays` to 0 or the
                                    // tier×price math zeroes out (shouldn't,
                                    // but defensive). Better than showing
                                    // "Subscribe & pay RM 0".
                                    isEnabled: vm.selectedPickupId != nil
                                        && vm.selectedDropId != nil
                                        && vm.subscriptionTotalMyr > 0,
                                    action: vm.subscribe
                                )

                                Group {
                                    switch vm.subscribeState {
                                    case .success:
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(VoygoTheme.success)
                                            Text("Subscription active!").font(.subheadline).foregroundColor(VoygoTheme.success)
                                        }
                                    case .charging:
                                        HStack {
                                            ProgressView().tint(VoygoTheme.primary)
                                            Text("Charging payment…").font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
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
                    .refreshable {
                        await store.refreshRouteDetails(routeId: routeId)
                        vm.load(routeId: routeId)
                    }
                } else {
                    EmptyStateView(icon: "questionmark.circle", title: "Route not found", subtitle: "This route may no longer be available")
                }
            }
        }
        .onAppear { vm.store = store; vm.onSubscribed = onSubscribed; vm.load(routeId: routeId) }
        .task(id: routeId) {
            vm.isLoading = vm.route == nil
            await store.refreshRouteDetails(routeId: routeId)
            vm.load(routeId: routeId)
            vm.isLoading = false
        }
        .sheet(item: Binding(
            get: { vm.pendingPaymentURL.map { URLBox(url: $0) } },
            set: { _ in /* dismissal handled by the sheet's onPaid/onAbandoned */ }
        )) { box in
            BillplzCheckoutSheet(
                url: box.url,
                onPaid: {
                    // Real success — close the sheet, advance to BookingConfirmed.
                    vm.paymentCheckoutDismissed(paid: true)
                },
                onAbandoned: {
                    // User hit Done in Safari without paying — keep the
                    // subscription paused via the same path that handles
                    // a charge failure, surface the retry hint.
                    vm.paymentCheckoutDismissed(paid: false)
                }
            )
        }
    }

    private var subscribeButtonTitle: String {
        switch vm.subscribeState {
        case .loading:   return "Creating subscription…"
        case .charging:  return "Charging payment…"
        default:         return "Subscribe & pay RM \(vm.subscriptionTotalMyr)"
        }
    }

    /// Turns the route's start/pickup/drop/end into the 4-anchor stop
    /// sequence the diagram expects. We always show origin → first
    /// pickup → first drop → dest so the curve has its full sweep.
    private func routeStops(for route: RecurringRoute) -> [RouteStop] {
        var stops: [RouteStop] = [.init(label: route.startLocation, kind: .origin)]
        if let firstPickup = route.pickupPoints.first {
            stops.append(.init(label: firstPickup.label, kind: .stop))
        }
        if let firstDrop = route.dropPoints.first {
            stops.append(.init(label: firstDrop.label, kind: .stop))
        }
        stops.append(.init(label: route.endLocation, kind: .dest))
        return stops
    }
}

private struct URLBox: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
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
