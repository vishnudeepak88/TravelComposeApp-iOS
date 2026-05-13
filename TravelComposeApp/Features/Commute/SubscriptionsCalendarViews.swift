import SwiftUI

// MARK: - My Subscriptions (mirrors MySubscriptionsScreen.kt)

struct MySubscriptionsView: View {
    @Environment(AppStore.self) private var store
    var onOpenRoute: (String) -> Void
    var onOpenCalendar: () -> Void
    /// Empty-state CTA: drills the rider into the search flow so they
    /// don't bounce off "No subscriptions" with no next step. Optional
    /// for the compatibility of older call sites; falls back to a
    /// no-op which hides the button.
    var onFindRoutes: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil

    @State private var actionError: String? = nil
    /// Holds the subscription the user has tapped Cancel on but hasn't
    /// confirmed yet. Drives the confirm alert.
    @State private var pendingCancellation: RouteSubscriptionWithRoute? = nil
    /// Holds a paused subscription whose payment retry is in flight, so we
    /// can disable the retry button to avoid double charges.
    @State private var retryingId: String? = nil
    /// Tracks whether the initial refresh has completed so we can
    /// show a skeleton instead of the empty-state on first paint.
    @State private var hasLoaded: Bool = false
    /// Multi-select mode + accumulated selection. When the rider taps
    /// "Select" in the nav bar, the cards swap their tap target from
    /// "open route" to "toggle in `selectedIds`" and a bottom action
    /// bar appears with bulk-cancel + select-all controls.
    @State private var isSelectMode: Bool = false
    @State private var selectedIds: Set<String> = []
    @State private var pendingBulkCancel: Bool = false
    @State private var bulkCancelInFlight: Bool = false

    var items: [RouteSubscriptionWithRoute] { store.mySubscriptions() }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.subscriptionsTitle, onBack: onBack) {
                    HStack(spacing: 8) {
                        // Calendar shortcut hides in select-mode to make
                        // room for Select-all + Done. Riders can still
                        // get there by exiting select-mode first.
                        if !isSelectMode {
                            Button(action: onOpenCalendar) {
                                Image(systemName: "calendar")
                                    .font(.callout.weight(.bold))
                                    .foregroundColor(VPalette.primary)
                                    .frame(width: 40, height: 40)
                                    .background(VPalette.primaryContainer)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(S.subsCalendarA11y)
                        }
                        // Toggle Select / Done. Hidden when there's
                        // nothing to select so we don't tease an
                        // affordance the empty state can't fulfill.
                        if !items.isEmpty {
                            Button {
                                if isSelectMode {
                                    isSelectMode = false
                                    selectedIds = []
                                } else {
                                    isSelectMode = true
                                }
                            } label: {
                                Text(isSelectMode ? S.subsDone : S.subsSelect)
                                    .font(.footnote.weight(.heavy))
                                    .foregroundColor(VPalette.primary)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(VPalette.primaryContainer)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isSelectMode ? S.subsDone : S.subsSelect)
                        }
                    }
                }

                if items.isEmpty && !hasLoaded {
                    // First paint — show skeleton cards instead of an
                    // empty-state that would lie about an empty list.
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(0..<3, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 10) {
                                    VSkeleton(height: 18)
                                    VSkeleton(height: 12)
                                    VSkeleton(height: 12)
                                }
                                .padding(16)
                                .background(VPalette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                } else if items.isEmpty {
                    EmptyStateView(icon: "mappin.slash", title: S.subscriptionsEmptyTitle,
                                   subtitle: S.subscriptionsEmptyBody,
                                   ctaLabel: onFindRoutes != nil ? S.subscriptionsEmptyCTA : nil,
                                   ctaAction: onFindRoutes)
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 14) {
                                Color.clear.frame(height: 0).id("top")
                                if let err = actionError {
                                    VErrorBanner(message: err)
                                        .padding(.horizontal, 16)
                                        .onTapGesture { actionError = nil }
                                }

                                ForEach(items) { item in
                                    HStack(spacing: 12) {
                                        if isSelectMode {
                                            // Per-row selection checkbox. Tap target
                                            // is the entire card row when in select
                                            // mode so the rider doesn't need to hit
                                            // the small circle precisely.
                                            Image(systemName: selectedIds.contains(item.subscription.id)
                                                  ? "checkmark.circle.fill"
                                                  : "circle")
                                                .font(.title3.weight(.semibold))
                                                .foregroundColor(
                                                    selectedIds.contains(item.subscription.id)
                                                        ? VPalette.primary
                                                        : VPalette.textHint
                                                )
                                                .transition(.opacity)
                                        }
                                        SubscriptionCard(
                                            item: item,
                                            onOpen:   {
                                                if isSelectMode {
                                                    toggleSelection(item.subscription.id)
                                                } else {
                                                    onOpenRoute(item.route.id)
                                                }
                                            },
                                            onPause:  { updateSubscription(item.subscription.id, status: .paused) },
                                            onResume: { updateSubscription(item.subscription.id, status: .active) },
                                            onCancel: { pendingCancellation = item },
                                            onRetryPayment: { retryPayment(item) },
                                            isRetryingPayment: retryingId == item.subscription.id,
                                            // Suppress in-card action buttons in
                                            // select mode so the row reads as
                                            // selectable, not as a per-action
                                            // surface.
                                            actionsHidden: isSelectMode
                                        )
                                    }
                                    .padding(.horizontal, 16)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isSelectMode {
                                            toggleSelection(item.subscription.id)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .refreshable {
                            await store.refreshAll()
                        }
                        // Bulk-action bar pinned ABOVE the native tab
                        // bar (not replacing it) via safeAreaInset.
                        // The inset both reserves layout space inside
                        // the ScrollView (so the bottom cards aren't
                        // covered) AND renders above the Liquid Glass
                        // tab bar. Result: rider can still navigate
                        // between tabs while selecting, and the
                        // action buttons are fully visible.
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if isSelectMode {
                                bulkActionBar
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .voygoTabReselected)) { note in
                            if (note.userInfo?["index"] as? Int) == 2 {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo("top", anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: isSelectMode)
        .task {
            await store.refreshAll()
            hasLoaded = true
        }
        .alert(
            S.cancelSubscriptionTitle,
            isPresented: Binding(
                get: { pendingCancellation != nil },
                set: { if !$0 { pendingCancellation = nil } }
            ),
            presenting: pendingCancellation
        ) { item in
            Button(S.confirmCancel, role: .destructive) {
                cancelSubscription(item)
                pendingCancellation = nil
            }
            Button(S.subKeepIt, role: .cancel) { pendingCancellation = nil }
        } message: { item in
            // Use the canonical S.cancelSubscriptionMessage instead of
            // the old "mid-month admin fee may apply" copy — that
            // string contradicted both the localized message in
            // Strings.swift (which the rest of the app uses) and the
            // actual policy engine (cancellation refunds are
            // tiered: full ≥12h, 50% ≥2h, none <2h — admin fees
            // don't enter into it). Prefix the route name so the
            // rider sees which sub they're cancelling.
            Text("\(item.route.startLocation) → \(item.route.endLocation).\n\(S.cancelSubscriptionMessage)")
        }
        // Bulk-cancel confirm alert. Body interpolates the chosen
        // count so the rider sees exactly how many subscriptions are
        // about to be cancelled. Disabled buttons while in-flight to
        // prevent double-firing.
        .alert(
            S.subsBulkCancelTitle(selectedIds.count),
            isPresented: $pendingBulkCancel
        ) {
            Button(S.subsBulkCancelConfirm(selectedIds.count), role: .destructive) {
                Task { await runBulkCancel() }
            }
            Button(S.subKeepIt, role: .cancel) { }
        } message: {
            Text(S.subsBulkCancelBody)
        }
    }

    /// Pinned bottom toolbar for multi-select mode. Mirrors the
    /// iOS Mail / Photos delete-many pattern: Select all (left),
    /// destructive primary (centre/wide), Cancel (right).
    private var bulkActionBar: some View {
        // No outer VStack / Spacer / ignoresSafeArea — the parent now
        // hosts this via `.safeAreaInset(edge: .bottom)` which sizes
        // the inset to wrap the content and places it above the
        // native tab bar's safe area.
        HStack(spacing: 10) {
            Button {
                if selectedIds.count == items.count {
                    // Already all selected → tap means "clear".
                    selectedIds = []
                } else {
                    selectedIds = Set(items.map { $0.subscription.id })
                }
            } label: {
                Text(selectedIds.count == items.count && !items.isEmpty
                     ? S.subsClearAll
                     : S.subsSelectAll)
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(VPalette.primaryContainer)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                pendingBulkCancel = true
            } label: {
                HStack(spacing: 6) {
                    if bulkCancelInFlight {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "xmark.bin.fill")
                    }
                    Text(S.subsBulkCancelCTA(selectedIds.count))
                }
                .font(.footnote.weight(.heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(selectedIds.isEmpty || bulkCancelInFlight ? VPalette.textHint : VPalette.danger)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedIds.isEmpty || bulkCancelInFlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(VPalette.border).frame(height: 1), alignment: .top)
    }

    /// Toggle a subscription's selection state. Used by the row tap
    /// and the per-row checkbox.
    private func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    /// Cancel every selected subscription in parallel. Each one goes
    /// through the same two-step `cancelSubscription` flow as the
    /// single-row tap (status flip → cancellation record), so the
    /// refund/penalty ledger stays consistent. Failures are surfaced
    /// per-item in a comma-joined error banner — the rider can retry
    /// the failed ones individually.
    private func runBulkCancel() async {
        guard !bulkCancelInFlight else { return }
        bulkCancelInFlight = true
        defer { bulkCancelInFlight = false }
        let chosen = items.filter { selectedIds.contains($0.subscription.id) }
        var failures: [String] = []
        // Fan out in parallel — these are independent server calls
        // against different subscription ids; serial would cost the
        // rider one round-trip per item.
        await withTaskGroup(of: (String, AppError?).self) { group in
            for item in chosen {
                group.addTask {
                    let cancelResult = await store.updateSubscription(id: item.subscription.id, status: .cancelled)
                    if case .failure(let err) = cancelResult {
                        return (item.route.startLocation, err)
                    }
                    let report = await store.reportCancellation(
                        rideInstanceId: nil,
                        routeId: item.route.id,
                        subscriptionId: item.subscription.id,
                        actor: .rider,
                        kind: .riderCancelMidMonth,
                        notes: nil
                    )
                    if case .failure(let err) = report {
                        // Rollback the status flip so the ledger
                        // doesn't drift — same recovery the single
                        // cancel path uses.
                        _ = await store.updateSubscription(id: item.subscription.id, status: .active)
                        return (item.route.startLocation, err)
                    }
                    return (item.route.startLocation, nil)
                }
            }
            for await (routeLabel, err) in group {
                if err != nil { failures.append(routeLabel) }
            }
        }
        if failures.isEmpty {
            // All clean — exit select mode and clear selection.
            isSelectMode = false
            selectedIds = []
        } else {
            actionError = S.subsBulkCancelFailed(failures.joined(separator: ", "))
            // Keep select-mode on so the rider can retry just the
            // failures (the successful ones already disappeared from
            // `items` via the status filter).
            selectedIds = selectedIds.filter { id in
                items.contains { $0.subscription.id == id }
            }
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
            // Backend re-derives the amount; we only pass id + tier + days.
            let charge = await store.startCharge(
                subscriptionId: item.subscription.id,
                tier: tier,
                days: days
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
    /// When true the per-row action buttons (Open Route / Pause / X)
    /// are suppressed so the card reads as a single selectable unit
    /// in multi-select mode. The whole card tap fires `onOpen` which
    /// the parent re-routes to selection-toggle.
    var actionsHidden: Bool = false

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

                // Actions — suppressed in multi-select mode so the
                // whole card reads as one selectable unit.
                if !actionsHidden {
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
                                .font(.title3)
                                .foregroundColor(VoygoTheme.danger.opacity(0.7))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Cancel subscription")
                    }
                }
                } // end if !actionsHidden

                // Retry-payment CTA — only on paused subscriptions, only if
                // the parent supplied an onRetryPayment handler. The QA
                // report flagged that the "Subscription paused — payment
                // failed" error message had nowhere to go; this is the
                // missing affordance.
                if !actionsHidden, item.subscription.status == .paused, let onRetryPayment {
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
    @Environment(AppStore.self) private var store
    let item: CommuteRideCalendarItem
    var onSkipped: (() -> Void)? = nil
    @State private var pendingSkip: Bool = false
    @State private var skipError: String? = nil

    /// Riders can skip future rides only — past rides are immutable
    /// so we hide the action entirely on those rows.
    private var canSkip: Bool {
        item.rideInstanceId != nil &&
        item.rideStatus == .scheduled &&
        item.date >= Calendar.current.startOfDay(for: Date())
    }

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
                        Image(systemName: "mappin").font(.caption2).foregroundColor(VoygoTheme.accent).accessibilityHidden(true)
                        Text("\(item.pickupPoint.label) → \(item.dropPoint.label)")
                            .font(.caption2).foregroundColor(VoygoTheme.textHint).lineLimit(1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusBadge(text: item.rideStatus.label,
                                color: item.rideStatus == .scheduled ? VoygoTheme.success : VoygoTheme.textHint)
                    if canSkip {
                        // Skip-a-day: lets a rider drop a single instance without
                        // cancelling their whole subscription. Frees the seat
                        // for someone else and notifies the driver.
                        Button {
                            // `rideInstanceId` is optional on the DTO
                            // (server returns it nil for some legacy
                            // calendar rows). Guard rather than force-
                            // unwrap so a stale row never crashes the
                            // calendar; surface a soft error instead.
                            guard let rideId = item.rideInstanceId else {
                                skipError = "This ride isn't skippable yet — please reload the calendar."
                                return
                            }
                            Task {
                                pendingSkip = true
                                let result = await store.skipRide(rideInstanceId: rideId)
                                pendingSkip = false
                                switch result {
                                case .success: onSkipped?()
                                case .failure(let err): skipError = err.localizedDescription
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if pendingSkip {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "calendar.badge.minus")
                                        .font(.caption2.weight(.bold))
                                }
                                Text(S.skipShort)
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundColor(VoygoTheme.warning)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(VoygoTheme.warning.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(pendingSkip)
                        .accessibilityLabel(S.skipAccessibility)
                    }
                }
            }
            .padding(14)
        }
        .alert(S.skipFailedTitle, isPresented: Binding(
            get: { skipError != nil },
            set: { if !$0 { skipError = nil } }
        ), presenting: skipError) { _ in
            Button("OK", role: .cancel) { skipError = nil }
        } message: { Text($0) }
    }
}
