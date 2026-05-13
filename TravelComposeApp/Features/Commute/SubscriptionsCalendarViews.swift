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
    // Multi-select moved to Upcoming Commutes (calendar view), where
    // bulk-action operates on per-day rides via SKIP — the real
    // common case ("I'm on vacation Mon–Fri, skip all 5"). Cancelling
    // a recurring subscription is a deliberate per-row act, so the
    // single × on each card is the right affordance here.

    var items: [RouteSubscriptionWithRoute] { store.mySubscriptions() }

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.subscriptionsTitle, onBack: onBack) {
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

    /// Subset of items that can be batch-skipped — future, scheduled,
    /// with a usable rideInstanceId. Past / completed rides aren't
    /// part of the selection pool even when the rider taps "Select
    /// all".
    private var skippableItems: [CommuteRideCalendarItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return items.filter { item in
            item.rideInstanceId != nil &&
            item.rideStatus == .scheduled &&
            item.date >= today
        }
    }

    @State private var actionError: String? = nil
    /// Multi-select state. Entry point is a long-press on any row
    /// (iOS-native pattern — Mail, Photos); each card row grows a
    /// checkmark, and a bottom action bar pinned via `.safeAreaInset`
    /// lets the rider Select-all + "Skip N rides". Real use case:
    /// skipping a vacation week in one go.
    @State private var isSelectMode: Bool = false
    @State private var selectedRideIds: Set<String> = []
    @State private var pendingBulkSkip: Bool = false
    @State private var bulkSkipInFlight: Bool = false
    /// Sticky flag that hides the "Long-press to skip multiple" hint
    /// once the rider has used the gesture at least once. Persisted
    /// per-account in UserDefaults so the hint doesn't keep nagging
    /// on every visit. Reset on logout (via the dev/onboarding key
    /// cleanup) so a new rider sees it fresh.
    @AppStorage("voygo.upcomingLongPressUsed") private var hasUsedLongPress: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.upcomingCommutesTitle, onBack: onBack) {
                    // Select mode is entered via long-press on a row
                    // (iOS-native pattern, mirrors Mail / Photos), so
                    // the nav bar only surfaces "Done" as the exit. We
                    // never show a "Select" button because the entry
                    // point is the gesture itself.
                    if isSelectMode {
                        Button {
                            isSelectMode = false
                            selectedRideIds = []
                        } label: {
                            Text(S.subsDone)
                                .font(.footnote.weight(.heavy))
                                .foregroundColor(VPalette.primary)
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(VPalette.primaryContainer)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(S.subsDone)
                    }
                }
                .background(VoygoTheme.background)

                if items.isEmpty {
                    EmptyStateView(icon: "calendar.badge.exclamationmark",
                                   title: S.upcomingEmptyTitle,
                                   subtitle: S.upcomingEmptyBody)
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        if let err = actionError {
                            VErrorBanner(message: err)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .onTapGesture { actionError = nil }
                        }
                        // Discoverability hint for the long-press entry
                        // into multi-select. Hidden in select mode + on
                        // empty lists so it never duplicates the visible
                        // affordance. Auto-hides once the rider has used
                        // the gesture (UserDefaults flag flips on first
                        // successful long-press).
                        if !isSelectMode,
                           !skippableItems.isEmpty,
                           !hasUsedLongPress {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.tap")
                                    .font(.caption2.weight(.semibold))
                                Text(S.upcomingLongPressHint)
                                    .font(.caption2.weight(.semibold))
                                Spacer()
                            }
                            .foregroundColor(VPalette.textHint)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, -4)
                        }
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
                                        // Two render paths so the outer tap
                                        // gesture (which exists only for
                                        // select-mode toggling) doesn't
                                        // intercept taps meant for the
                                        // per-row Skip button in non-select
                                        // mode. SwiftUI's hit-test will
                                        // shadow inner Button taps when an
                                        // ancestor has .contentShape +
                                        // .onTapGesture, even if that
                                        // gesture no-ops — which made the
                                        // per-row Skip pill feel dead.
                                        if isSelectMode {
                                            HStack(spacing: 12) {
                                                if let rideId = item.rideInstanceId {
                                                    let canSelect = isSkippable(item)
                                                    Image(systemName: selectedRideIds.contains(rideId)
                                                          ? "checkmark.circle.fill"
                                                          : (canSelect ? "circle" : "minus.circle"))
                                                        .font(.title3.weight(.semibold))
                                                        .foregroundColor(
                                                            selectedRideIds.contains(rideId)
                                                                ? VPalette.primary
                                                                : (canSelect ? VPalette.textHint : VPalette.textHint.opacity(0.4))
                                                        )
                                                        .transition(.opacity)
                                                        .padding(.leading, 16)
                                                }
                                                CalendarItemCard(item: item, skipHidden: true)
                                            }
                                            .padding(.trailing, 16)
                                            .contentShape(Rectangle())
                                            .onTapGesture { toggleSelection(item) }
                                        } else {
                                            // Per-row Skip pill on the card
                                            // is the only tap affordance —
                                            // no outer gesture eats it.
                                            // `onSkipped` clears any stale
                                            // action error and triggers a
                                            // calendar refresh so the row
                                            // disappears immediately on
                                            // the off-chance the optimistic
                                            // local removal in
                                            // `store.skipRide` ever
                                            // diverges from server state.
                                            //
                                            // Long-press enters select mode
                                            // AND auto-selects the pressed
                                            // row — the iOS-native pattern
                                            // (Mail, Photos). A medium
                                            // haptic confirms the gesture
                                            // because the transition is
                                            // subtle (checkmark fades in,
                                            // bottom bar slides up). We
                                            // also flip the sticky hint-
                                            // dismissed flag so the
                                            // discoverability tip stops
                                            // showing on future visits.
                                            CalendarItemCard(item: item,
                                                             onSkipped: { actionError = nil },
                                                             skipHidden: false)
                                                .padding(.horizontal, 16)
                                                // simultaneousGesture (not
                                                // onLongPressGesture) so the
                                                // long-press coexists with
                                                // the inner per-row Skip
                                                // button. With the latter,
                                                // SwiftUI gives the inner
                                                // Button gesture priority
                                                // and the long-press never
                                                // fires.
                                                .simultaneousGesture(
                                                    LongPressGesture(minimumDuration: 0.4)
                                                        .onEnded { _ in
                                                            guard isSkippable(item),
                                                                  let rideId = item.rideInstanceId else { return }
                                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                            isSelectMode = true
                                                            selectedRideIds.insert(rideId)
                                                            hasUsedLongPress = true
                                                        }
                                                )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .refreshable {
                        await store.refreshCalendar(routeId: routeId)
                    }
                    // Bottom action bar pinned ABOVE the native tab bar
                    // via `.safeAreaInset` — same pattern shipped for
                    // My commutes' bulk-cancel. Tab bar stays visible.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if isSelectMode {
                            bulkSkipBar
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: isSelectMode)
        .task(id: routeId ?? "all") {
            await store.refreshCalendar(routeId: routeId)
        }
        // Bulk-skip confirm alert. Body interpolates the chosen
        // count so the rider sees exactly how many rides are about
        // to be skipped.
        .alert(
            S.bulkSkipTitle(selectedRideIds.count),
            isPresented: $pendingBulkSkip
        ) {
            Button(S.bulkSkipConfirm(selectedRideIds.count), role: .destructive) {
                Task { await runBulkSkip() }
            }
            Button(S.subKeepIt, role: .cancel) { }
        } message: {
            Text(S.bulkSkipBody)
        }
    }

    private func isSkippable(_ item: CommuteRideCalendarItem) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return item.rideInstanceId != nil &&
            item.rideStatus == .scheduled &&
            item.date >= today
    }

    private func toggleSelection(_ item: CommuteRideCalendarItem) {
        guard let rideId = item.rideInstanceId, isSkippable(item) else { return }
        if selectedRideIds.contains(rideId) {
            selectedRideIds.remove(rideId)
        } else {
            selectedRideIds.insert(rideId)
        }
    }

    /// Pinned bottom toolbar for multi-select mode. Same shape as the
    /// My commutes bulk-cancel bar but the destructive action is
    /// SKIP (gentler — frees seat, sub stays active) not CANCEL.
    private var bulkSkipBar: some View {
        HStack(spacing: 10) {
            Button {
                let allSkippableIds = Set(skippableItems.compactMap { $0.rideInstanceId })
                if selectedRideIds == allSkippableIds {
                    selectedRideIds = []
                } else {
                    selectedRideIds = allSkippableIds
                }
            } label: {
                Text({
                    let allIds = Set(skippableItems.compactMap { $0.rideInstanceId })
                    return selectedRideIds == allIds && !allIds.isEmpty
                        ? S.subsClearAll : S.subsSelectAll
                }())
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
                pendingBulkSkip = true
            } label: {
                HStack(spacing: 6) {
                    if bulkSkipInFlight {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "calendar.badge.minus")
                    }
                    Text(S.bulkSkipCTA(selectedRideIds.count))
                }
                .font(.footnote.weight(.heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(selectedRideIds.isEmpty || bulkSkipInFlight ? VPalette.textHint : VPalette.warning)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectedRideIds.isEmpty || bulkSkipInFlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(VPalette.border).frame(height: 1), alignment: .top)
    }

    /// Skip every selected ride in parallel. Each call goes through
    /// the same `store.skipRide` flow as the per-card Skip button so
    /// the server's free-seat / notify-driver side-effects fire
    /// consistently. Failures are surfaced per-item.
    private func runBulkSkip() async {
        guard !bulkSkipInFlight else { return }
        bulkSkipInFlight = true
        defer { bulkSkipInFlight = false }
        let chosenIds = Array(selectedRideIds)
        var failures: [String] = []
        await withTaskGroup(of: (String, String?).self) { group in
            for rideId in chosenIds {
                group.addTask {
                    let result = await store.skipRide(rideInstanceId: rideId)
                    switch result {
                    case .success:        return (rideId, nil)
                    case .failure(let e): return (rideId, e.localizedDescription)
                    }
                }
            }
            for await (_, err) in group {
                if let err { failures.append(err) }
            }
        }
        if failures.isEmpty {
            // Success haptic — the action bar dismisses and the
            // rows disappear silently otherwise, which felt like
            // "did anything happen?" on a fast network.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            isSelectMode = false
            selectedRideIds = []
            actionError = nil
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            actionError = S.bulkSkipFailed(failures.count)
            // Keep selectMode on; SKIPPED rows fall out of
            // `skippableItems` naturally on next refresh.
            await store.refreshCalendar(routeId: routeId)
            selectedRideIds = selectedRideIds.intersection(
                Set(skippableItems.compactMap { $0.rideInstanceId })
            )
        }
    }
}

struct CalendarItemCard: View {
    @Environment(AppStore.self) private var store
    let item: CommuteRideCalendarItem
    var onSkipped: (() -> Void)? = nil
    /// When true, the per-row "Skip" pill is suppressed. The parent
    /// (UpcomingCalendarView in multi-select mode) wants the whole row
    /// to read as one selectable unit instead of advertising its own
    /// per-row action.
    var skipHidden: Bool = false
    @State private var pendingSkip: Bool = false
    @State private var skipError: String? = nil

    /// Riders can skip future rides only — past rides are immutable
    /// so we hide the action entirely on those rows.
    private var canSkip: Bool {
        !skipHidden &&
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
