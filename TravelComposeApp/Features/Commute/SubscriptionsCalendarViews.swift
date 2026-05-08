import SwiftUI

// MARK: - My Subscriptions (mirrors MySubscriptionsScreen.kt)

struct MySubscriptionsView: View {
    @Environment(AppStore.self) private var store
    var onOpenRoute: (String) -> Void
    var onOpenCalendar: () -> Void
    var onBack: (() -> Void)? = nil

    @State private var actionError: String? = nil
    /// Holds the subscription the user has tapped Cancel on but hasn't
    /// confirmed yet. Drives the confirm alert.
    @State private var pendingCancellation: RouteSubscriptionWithRoute? = nil
    /// Holds a paused subscription whose payment retry is in flight, so we
    /// can disable the retry button to avoid double charges.
    @State private var retryingId: String? = nil

    var items: [RouteSubscriptionWithRoute] { store.mySubscriptions() }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "My Subscriptions", onBack: onBack) {
                    Button(action: onOpenCalendar) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(VPalette.primary)
                            .frame(width: 40, height: 40)
                            .background(VPalette.primaryContainer)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Calendar")
                }

                if items.isEmpty {
                    EmptyStateView(icon: "mappin.slash", title: "No subscriptions",
                                   subtitle: "Search for commute routes and subscribe to start riding")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            if let err = actionError {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(VoygoTheme.warning)
                                    Text(err).font(.caption).foregroundColor(VoygoTheme.warning)
                                    Spacer()
                                    Button("Dismiss") { actionError = nil }.font(.caption).foregroundColor(VoygoTheme.primary)
                                }
                                .padding(12)
                                .background(VoygoTheme.warning.opacity(0.1))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                            }

                            ForEach(items) { item in
                                SubscriptionCard(
                                    item: item,
                                    onOpen:   { onOpenRoute(item.route.id) },
                                    onPause:  { updateSubscription(item.subscription.id, status: .paused) },
                                    onResume: { updateSubscription(item.subscription.id, status: .active) },
                                    onCancel: { pendingCancellation = item },
                                    onRetryPayment: { retryPayment(item) },
                                    isRetryingPayment: retryingId == item.subscription.id
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
        .alert(
            "Cancel subscription?",
            isPresented: Binding(
                get: { pendingCancellation != nil },
                set: { if !$0 { pendingCancellation = nil } }
            ),
            presenting: pendingCancellation
        ) { item in
            Button("Cancel subscription", role: .destructive) {
                cancelSubscription(item)
                pendingCancellation = nil
            }
            Button("Keep it", role: .cancel) { pendingCancellation = nil }
        } message: { item in
            Text("\(item.route.startLocation) → \(item.route.endLocation). A mid-month admin fee may apply per your subscription tier. You'll need to subscribe again to ride.")
        }
    }

    private func updateSubscription(_ id: String, status: RouteSubscriptionStatus) {
        Task {
            let result = await store.updateSubscription(id: id, status: status)
            if case .failure(let error) = result {
                actionError = error.localizedDescription
            }
        }
    }

    /// Two-step cancellation:
    /// 1. Flip the subscription status to .cancelled.
    /// 2. Record a CancellationRecord so any mid-month admin fee or
    ///    driver penalty hits the right balance.
    /// If step 2 fails (network), revert step 1 so the user isn't left in
    /// "cancelled but no fee" inconsistency. The QA report flagged the
    /// previous fire-and-forget path as a real ledger risk.
    private func cancelSubscription(_ item: RouteSubscriptionWithRoute) {
        Task {
            let cancelResult = await store.updateSubscription(id: item.subscription.id, status: .cancelled)
            if case .failure(let error) = cancelResult {
                actionError = error.localizedDescription
                return
            }
            let reportResult = await store.reportCancellation(
                rideInstanceId: nil,
                routeId: item.route.id,
                subscriptionId: item.subscription.id,
                actor: .rider,
                kind: .riderCancelMidMonth,
                notes: nil
            )
            if case .failure(let error) = reportResult {
                // Rollback: restore the subscription to active so the
                // ledger isn't out of sync. The user sees a banner and
                // can retry.
                _ = await store.updateSubscription(id: item.subscription.id, status: .active)
                actionError = "Couldn't record cancellation (\(error.localizedDescription)). Subscription kept active — please try again."
            }
        }
    }

    /// Retry payment for a paused subscription. Reads the tier + days
    /// the rider originally chose at subscribe-time (now persisted on
    /// the subscription model) so the retry charges the same amount the
    /// user accepted, not a default monthly band.
    private func retryPayment(_ item: RouteSubscriptionWithRoute) {
        guard retryingId == nil else { return }
        retryingId = item.subscription.id
        Task {
            let tier = item.subscription.tier
                .flatMap { SubscriptionTier(rawValue: $0) } ?? .monthly
            let days = item.subscription.totalDays ?? 30
            let amount = SubscriptionPricing.totalForTier(
                pricePerSeatMyr: item.route.pricePerSeat,
                tier: tier,
                days: days
            )
            let charge = await store.startCharge(
                subscriptionId: item.subscription.id,
                routeId: item.route.id,
                amountMyr: amount,
                tier: tier
            )
            retryingId = nil
            switch charge {
            case .success(let result):
                if result.status == .paid {
                    _ = await store.updateSubscription(id: item.subscription.id, status: .active)
                } else {
                    actionError = "Retry started — complete payment in the next sheet."
                }
            case .failure(let err):
                actionError = err.localizedDescription
            }
        }
    }
}

struct SubscriptionCard: View {
    let item: RouteSubscriptionWithRoute
    let onOpen: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    var onRetryPayment: (() -> Void)? = nil
    var isRetryingPayment: Bool = false

    var statusColor: Color {
        switch item.subscription.status {
        case .active: return VoygoTheme.success
        case .paused: return VoygoTheme.warning
        case .cancelled: return VoygoTheme.danger
        case .completed: return VoygoTheme.accent
        }
    }

    var body: some View {
        VoygoCard {
            VStack(spacing: 14) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(item.route.startLocation) → \(item.route.endLocation)")
                            .font(.headline).foregroundColor(VoygoTheme.textPrimary)
                        Text("Driver: \(item.route.driverName)")
                            .font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                    }
                    Spacer()
                    StatusBadge(text: item.subscription.status.label, color: statusColor)
                }

                Divider().background(VoygoTheme.cardBorder)

                // Info grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    SubscriptionInfoCell(icon: "mappin.circle.fill", label: "Pickup",
                                         value: item.subscription.selectedPickupPoint.label)
                    SubscriptionInfoCell(icon: "flag.checkered.circle.fill", label: "Drop",
                                         value: item.subscription.selectedDropPoint.label)
                    SubscriptionInfoCell(icon: "clock.fill", label: "Departure",
                                         value: item.route.departureTime)
                    SubscriptionInfoCell(icon: "calendar.badge.clock", label: "Next ride",
                                         value: item.nextRideDate.map { formatDate($0) } ?? "–")
                }

                // Actions
                HStack(spacing: 8) {
                    SecondaryButton(title: "Open Route", action: onOpen)
                    if item.subscription.status == .active {
                        Button(action: onPause) {
                            HStack { Image(systemName: "pause.fill"); Text("Pause") }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(VoygoTheme.warning.opacity(0.15))
                                .foregroundColor(VoygoTheme.warning)
                                .cornerRadius(14)
                        }
                    } else if item.subscription.status == .paused {
                        Button(action: onResume) {
                            HStack { Image(systemName: "play.fill"); Text("Resume") }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(VoygoTheme.success.opacity(0.15))
                                .foregroundColor(VoygoTheme.success)
                                .cornerRadius(14)
                        }
                    }
                    if item.subscription.status != .cancelled {
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(VoygoTheme.danger.opacity(0.7))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Cancel subscription")
                    }
                }

                // Retry-payment CTA — only on paused subscriptions, only if
                // the parent supplied an onRetryPayment handler. The QA
                // report flagged that the "Subscription paused — payment
                // failed" error message had nowhere to go; this is the
                // missing affordance.
                if item.subscription.status == .paused, let onRetryPayment {
                    Button(action: onRetryPayment) {
                        HStack(spacing: 6) {
                            if isRetryingPayment {
                                ProgressView().tint(.white).controlSize(.small)
                            } else {
                                Image(systemName: "creditcard.fill")
                            }
                            Text(isRetryingPayment ? "Charging…" : "Retry payment")
                        }
                        .font(.subheadline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundColor(.white)
                        .background(VoygoTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(isRetryingPayment)
                    .accessibilityLabel("Retry payment")
                }
            }
            .padding(16)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date)
    }
}

private struct SubscriptionInfoCell: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundColor(VoygoTheme.primary).font(.caption).frame(width: 14).padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundColor(VoygoTheme.textHint)
                Text(value).font(.caption.weight(.medium)).foregroundColor(VoygoTheme.textPrimary).lineLimit(1)
            }
        }
    }
}

// MARK: - Upcoming Calendar (mirrors UpcomingCommuteCalendarScreen.kt)

struct UpcomingCalendarView: View {
    @Environment(AppStore.self) private var store
    var routeId: String? = nil
    var onBack: () -> Void

    var items: [CommuteRideCalendarItem] { store.calendarItems(routeId: routeId) }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Upcoming Commutes", onBack: onBack)
                    .background(VoygoTheme.background)

                if items.isEmpty {
                    EmptyStateView(icon: "calendar.badge.exclamationmark",
                                   title: "No upcoming commutes",
                                   subtitle: "Subscribe to a route to see your schedule here")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        // Group by week
                        let grouped = Dictionary(grouping: items) { i -> String in
                            let cal = Calendar.current
                            guard let week = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: i.date)) else { return "" }
                            let f = DateFormatter(); f.dateFormat = "MMM d"; return "Week of \(f.string(from: week))"
                        }
                        let sortedKeys = grouped.keys.sorted()

                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(sortedKeys, id: \.self) { key in
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(title: key).padding(.horizontal, 16)
                                    ForEach(grouped[key] ?? []) { item in
                                        CalendarItemCard(item: item).padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .refreshable {
                        await store.refreshCalendar(routeId: routeId)
                    }
                }
            }
        }
        .task(id: routeId ?? "all") {
            await store.refreshCalendar(routeId: routeId)
        }
    }
}

struct CalendarItemCard: View {
    let item: CommuteRideCalendarItem
    var body: some View {
        VoygoCard {
            HStack(spacing: 14) {
                // Date badge
                VStack(spacing: 2) {
                    let f: DateFormatter = {let d = DateFormatter(); d.dateFormat = "d"; return d}()
                    let m: DateFormatter = {let d = DateFormatter(); d.dateFormat = "MMM"; return d}()
                    Text(f.string(from: item.date)).font(.title2.bold()).foregroundColor(VoygoTheme.primary)
                    Text(m.string(from: item.date)).font(.caption2.bold()).foregroundColor(VoygoTheme.textHint)
                }
                .frame(width: 40)
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .background(VoygoTheme.primary.opacity(0.1))
                .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.startLocation) → \(item.endLocation)")
                        .font(.subheadline.weight(.semibold)).foregroundColor(VoygoTheme.textPrimary)
                    Text("Driver: \(item.driverName)").font(.caption).foregroundColor(VoygoTheme.textSecondary)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin").font(.caption2).foregroundColor(VoygoTheme.accent)
                        Text("\(item.pickupPoint.label) → \(item.dropPoint.label)")
                            .font(.caption2).foregroundColor(VoygoTheme.textHint).lineLimit(1)
                    }
                }
                Spacer()
                StatusBadge(text: item.rideStatus.label,
                            color: item.rideStatus == .scheduled ? VoygoTheme.success : VoygoTheme.textHint)
            }
            .padding(14)
        }
    }
}
