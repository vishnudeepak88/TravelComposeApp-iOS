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
        // Idempotency guard — prevent a second tap during the
        // sub-create / charge round-trip from firing two POSTs and
        // two charges. Previously the button's `isEnabled` didn't
        // factor `isInFlight`, so a rapid double-tap could spawn
        // two parallel `subscribe → charge` chains. Re-entry here
        // is the last line of defense.
        guard !subscribeState.isInFlight else { return }
        guard let store, let route, let pickupId = selectedPickupId, let dropId = selectedDropId else { return }
        let days = Int(numberOfDays) ?? 30
        // Local pre-computed total stays for the in-flight CTA copy
        // (`subscribe.payCTA` already references it). Backend recomputes
        // the authoritative amount from server-truth — see
        // `AppStore.startCharge` and `/payments/charge`.
        _ = SubscriptionPricing.totalForTier(
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
                    tier: selectedTier,
                    days: days
                )
                switch chargeResult {
                case .success(let charge):
                    // Branch by EXPLICIT payment status, not by
                    // "did we get a URL". The old code treated
                    // anything-not-pending as success — including
                    // `.failed` returns where the FPX bank declined
                    // in-line. Riders saw "Subscription active!"
                    // for a payment that never moved any money.
                    switch charge.status {
                    case .pending:
                        if let urlString = charge.paymentUrl, let url = URL(string: urlString) {
                            // Live Billplz: present the hosted checkout
                            // sheet. The view's onDismiss handler will
                            // fire `onSubscribed` once the rider
                            // returns from the redirect.
                            pendingPaymentURL = url
                            subscribeState = .success(subscriptionId)
                        } else {
                            // Backend said .pending but didn't give us
                            // a URL — misconfigured Billplz or a
                            // contract drift. Treat as a charge failure
                            // so we pause and tell the rider to retry.
                            let pauseResult = await store.updateSubscription(id: subscriptionId, status: .paused)
                            if case .failure(let pauseErr) = pauseResult {
                                subscribeState = .error(S.subscribePauseFailed(pauseErr.localizedDescription))
                            } else {
                                subscribeState = .error(S.subscribePauseRetry)
                            }
                            load(routeId: route.id)
                        }
                    case .paid:
                        // Mock mode (no Billplz creds) or instant
                        // success path: jump straight to confirmed.
                        subscribeState = .success(subscriptionId)
                        load(routeId: route.id)
                        onSubscribed?(subscriptionId)
                    case .failed, .refunded:
                        // Bank declined in-line, or refunded before
                        // we even rendered. Pause + surface error.
                        let pauseResult = await store.updateSubscription(id: subscriptionId, status: .paused)
                        if case .failure(let pauseErr) = pauseResult {
                            subscribeState = .error(S.subscribeDeclinedPauseFailed(pauseErr.localizedDescription))
                        } else {
                            subscribeState = .error(S.subscribeDeclinedPaused)
                        }
                        load(routeId: route.id)
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
                            S.subscribeFailedPauseFailed(err.localizedDescription, pauseErr.localizedDescription)
                        )
                    } else {
                        subscribeState = .error(S.subscribePaymentFailed(err.localizedDescription))
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
                    self.subscribeState = .error(S.subscribeCancelledPauseFailed(err.localizedDescription))
                } else {
                    self.subscribeState = .error(S.subscribeNotCompleted)
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
    /// Optional "Book solo" entry from this route. Caller decides
    /// where to push (.soloPick filtered to this route, or straight
    /// into the date picker for solo). Leaving nil hides the CTA so
    /// previews + driver-side route detail aren't affected.
    var onBookSolo: ((_ routeId: String) -> Void)? = nil
    @Environment(AppStore.self) private var store
    @State private var vm = RouteDetailsViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.routeDetailsTitle, onBack: onBack)

                if vm.isLoading {
                    // Page-shaped skeleton while the route loads.
                    // Replaces the bare `LoadingView()` spinner so a
                    // slow network feels like the screen is filling
                    // in rather than blank.
                    routeDetailsSkeleton
                } else if let route = vm.route {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Real Apple Maps preview with pickup/drop pins
                            // and a MapKit driving route when available.
                            VRouteMapPreview(
                                route: route,
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
                                            Text(Formatters.ringgit(route.pricePerSeat)).font(.title2.bold()).foregroundColor(VoygoTheme.primary)
                                            Text(S.homePerSeat).font(.caption2).foregroundColor(VoygoTheme.textHint)
                                        }
                                    }

                                    Divider().background(VoygoTheme.cardBorder)

                                    RouteInfoRow(icon: "arrow.right.circle.fill", label: S.routeInfoRoute,
                                                 value: "\(route.startLocation) → \(route.endLocation)")
                                    RouteInfoRow(icon: "clock.fill", label: S.routeInfoDeparture, value: route.departureTime)
                                    RouteInfoRow(icon: "calendar", label: S.routeInfoSchedule, value: route.daysOfWeek.shortLabel)
                                    RouteInfoRow(icon: route.carType.icon, label: S.routeInfoCarType, value: route.carType.label)
                                    RouteInfoRow(icon: "person.3.fill", label: S.routeInfoAvailableSeats, value: S.routeInfoSeatsOf(vm.availableSeats, route.seatCount))
                                    RouteInfoRow(icon: "person.badge.plus.fill", label: S.routeInfoActiveRiders, value: "\(vm.subscriptions.count)")

                                    Divider().background(VoygoTheme.cardBorder)

                                    // Reliability
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(S.routeInfoDriverReliability).font(.subheadline.bold()).foregroundColor(VoygoTheme.textPrimary)
                                        HStack(spacing: 0) {
                                            ReliabilityMetric(label: S.routeInfoOnTime, value: "\(Int(route.reliability.onTimeRate * 100))%")
                                            Spacer()
                                            ReliabilityMetric(label: S.routeInfoCancelRate, value: "\(Int(route.reliability.cancellationRate * 100))%")
                                            Spacer()
                                            ReliabilityMetric(label: S.routeInfoRepeatRiders, value: "\(route.reliability.repeatRiders)")
                                        }
                                    }
                                }
                                .padding(16)
                            }

                            // Pickup selection
                            VoygoCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(title: S.routePickupPoint)
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
                                    SectionHeader(title: S.routeDropPoint)
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
                                    SectionHeader(title: S.subscribeSection)
                                    VoygoTextField(label: S.subscribeNumberOfDays, text: $vm.numberOfDays, placeholder: "30", keyboardType: .numberPad)
                                    HStack {
                                        Image(systemName: "calendar.badge.clock").foregroundColor(VoygoTheme.textHint).font(.caption)
                                        Text(S.subscribeStartsTodayDays(Int(vm.numberOfDays) ?? 30))
                                            .font(.caption).foregroundColor(VoygoTheme.textHint)
                                    }
                                }
                                .padding(16)
                            }

                            // Subscription tier picker — daily / monthly / quarterly.
                            VStack(alignment: .leading, spacing: 8) {
                                Text(S.subscribeTier).font(.caption.weight(.bold)).foregroundColor(VoygoTheme.textSecondary)
                                HStack(spacing: 6) {
                                    ForEach(SubscriptionTier.allCases) { tier in
                                        let on = tier == vm.selectedTier
                                        // Derive discount % from the single source of
                                        // truth in `Trust.swift` so a future re-pricing
                                        // (e.g. monthly drops to 12% off) updates the
                                        // chip copy automatically. Daily is full price,
                                        // so it gets the "Try it" callout instead.
                                        let discountPercent = Int((1.0 - tier.discountFactor) * 100.0)
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                vm.selectedTier = tier
                                            }
                                        } label: {
                                            VStack(spacing: 1) {
                                                Text(tier.label)
                                                    .font(.footnote.weight(.heavy))
                                                Text(discountPercent <= 0 ? S.subscribeTierTry : S.subscribeTierDiscount(percent: discountPercent))
                                                    .font(.caption2.weight(.semibold))
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
                                    Text(S.subscribeTotal)
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(VoygoTheme.textSecondary)
                                    Spacer()
                                    Text(Formatters.ringgit(vm.subscriptionTotalMyr))
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
                                        && vm.subscriptionTotalMyr > 0
                                        && !vm.subscribeState.isInFlight,
                                    action: vm.subscribe
                                )

                                Group {
                                    switch vm.subscribeState {
                                    case .success:
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(VoygoTheme.success)
                                            Text(S.subscriptionActive).font(.subheadline).foregroundColor(VoygoTheme.success)
                                        }
                                    case .charging:
                                        HStack {
                                            ProgressView().tint(VoygoTheme.primary)
                                            Text(S.subscribeCharging).font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                                        }
                                    case .error(let msg):
                                        VErrorBanner(message: msg, onRetry: vm.subscribe)
                                    default: EmptyView()
                                    }
                                }

                                // Secondary affordance — book this exact
                                // route for one day exclusively at 2× the
                                // seat price. Distinct from subscribing
                                // (which is recurring) so it sits below
                                // the primary CTA, not next to it.
                                if let route = vm.route, let onBookSolo {
                                    Button {
                                        onBookSolo(route.id)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "person.fill.checkmark")
                                                .font(.footnote.weight(.heavy))
                                                .foregroundColor(VoygoTheme.accent)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(S.subscribeBookSolo)
                                                    .font(.footnote.weight(.heavy))
                                                    .foregroundColor(VoygoTheme.textPrimary)
                                                Text(S.subscribeSoloPrice(route.pricePerSeat * 2))
                                                    .font(.caption2)
                                                    .foregroundColor(VoygoTheme.textSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.heavy))
                                                .foregroundColor(VoygoTheme.textHint)
                                        }
                                        .padding(12)
                                        .background(VoygoTheme.surfaceHigh)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(VoygoTheme.cardBorder, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
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
                    EmptyStateView(icon: "questionmark.circle", title: S.routeNotFound, subtitle: S.routeNotFoundBody)
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
        case .loading:   return S.subscribeCreating
        case .charging:  return S.subscribeCharging
        default:         return S.subscribeAndPay(amountMyr: vm.subscriptionTotalMyr)
        }
    }

    /// Page-shaped skeleton matching the real layout so the user
    /// sees the screen filling in rather than a centered spinner.
    private var routeDetailsSkeleton: some View {
        ScrollView {
            VStack(spacing: 16) {
                VSkeleton(height: 180, corner: 18)
                    .padding(.horizontal, 16)
                VStack(spacing: 12) {
                    VSkeleton(height: 24)
                    VSkeleton(height: 14)
                    VSkeleton(height: 14)
                    VSkeleton(height: 14)
                    VSkeleton(height: 60, corner: 12)
                }
                .padding(16)
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
                VStack(spacing: 10) {
                    VSkeleton(height: 18)
                    VSkeleton(height: 18)
                    VSkeleton(height: 18)
                }
                .padding(16)
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
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
