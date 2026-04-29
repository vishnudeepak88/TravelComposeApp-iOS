import SwiftUI

// MARK: - My Subscriptions (mirrors MySubscriptionsScreen.kt)

struct MySubscriptionsView: View {
    @EnvironmentObject var store: AppStore
    var onOpenRoute: (String) -> Void
    var onOpenCalendar: () -> Void
    var onBack: (() -> Void)? = nil

    @State private var actionError: String? = nil

    var items: [RouteSubscriptionWithRoute] { store.mySubscriptions() }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(
                    title: "My Subscriptions",
                    showBack: onBack != nil,
                    onBack: onBack,
                    trailingContent: AnyView(
                        Button(action: onOpenCalendar) {
                            Image(systemName: "calendar").font(.system(size: 18, weight: .semibold))
                                .foregroundColor(VoygoTheme.primary)
                                .frame(width: 36, height: 36)
                                .background(VoygoTheme.surfaceHigh)
                                .clipShape(Circle())
                        }
                    )
                )
                .background(VoygoTheme.background)

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
                                    onCancel: { cancelSubscription(item) }
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

    private func updateSubscription(_ id: String, status: RouteSubscriptionStatus) {
        Task {
            let result = await store.updateSubscription(id: id, status: status)
            if case .failure(let error) = result {
                actionError = error.localizedDescription
            }
        }
    }

    /// Cancellation goes through two flows simultaneously:
    /// 1. Flip the subscription status to .cancelled (existing path).
    /// 2. Record a CancellationRecord with the policy engine so any
    ///    mid-month admin fee or driver penalty hits the right balance.
    private func cancelSubscription(_ item: RouteSubscriptionWithRoute) {
        Task {
            let result = await store.updateSubscription(id: item.subscription.id, status: .cancelled)
            if case .failure(let error) = result {
                actionError = error.localizedDescription
                return
            }
            let cancelResult = await store.reportCancellation(
                rideInstanceId: nil,
                routeId: item.route.id,
                subscriptionId: item.subscription.id,
                actor: .rider,
                kind: .riderCancelMidMonth,
                notes: nil
            )
            if case .failure(let error) = cancelResult {
                actionError = error.localizedDescription
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
                    }
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
    @EnvironmentObject var store: AppStore
    var routeId: String? = nil
    var onBack: () -> Void

    var items: [CommuteRideCalendarItem] { store.calendarItems(routeId: routeId) }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Upcoming Commutes", showBack: true, onBack: onBack)
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
