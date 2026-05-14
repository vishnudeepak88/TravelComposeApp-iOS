import SwiftUI

// MARK: - Notifications (backend-backed)
//
// Reads from `store.notifications` which `refreshAll()` populates via
// `GET /notifications/me`. Honest empty state when the feed is empty;
// real "Mark all read" iterates the unread ids and PUTs each one.
//
// Tapping a row optimistically marks it read and — when the row
// references a route / subscription / ride — drills into the matching
// destination. Notifications referencing objects the local store
// doesn't have (e.g. a route that was removed) still mark-read but
// don't navigate, so the UI never wedges.

struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    /// Optional drill-in callback. When set, tapping a row that names
    /// a `routeId` will push `.routeDetails(...)` via the parent
    /// navigator. The default no-op keeps `NotificationsView` usable
    /// as a leaf screen (e.g. preview).
    var onOpenRoute: (String) -> Void = { _ in }
    /// Drill-in to subscriptions / calendar for ride-or-subscription
    /// notifications. The parent decides which.
    var onOpenSubscriptions: () -> Void = {}
    var onOpenCalendar: () -> Void = {}

    @State private var isRefreshing: Bool = false

    private var groups: [(label: String, items: [NotificationDTO])] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let startOfYesterday = cal.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = cal.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        var today: [NotificationDTO] = []
        var yesterday: [NotificationDTO] = []
        var week: [NotificationDTO] = []
        var earlier: [NotificationDTO] = []

        for n in store.notifications {
            if n.createdAt >= startOfToday {
                today.append(n)
            } else if n.createdAt >= startOfYesterday {
                yesterday.append(n)
            } else if n.createdAt >= startOfWeek {
                week.append(n)
            } else {
                earlier.append(n)
            }
        }
        var out: [(label: String, items: [NotificationDTO])] = []
        if !today.isEmpty     { out.append((S.notifGroupToday,     today)) }
        if !yesterday.isEmpty { out.append((S.notifGroupYesterday, yesterday)) }
        if !week.isEmpty      { out.append((S.notifGroupThisWeek,  week)) }
        if !earlier.isEmpty   { out.append((S.notifGroupEarlier,   earlier)) }
        return out
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.notifTitle, onBack: onBack) {
                    Button {
                        Task { await store.markAllNotificationsRead() }
                    } label: {
                        Text(S.notifMarkAllRead)
                            .font(.caption.weight(.bold))
                            .foregroundColor(store.unreadNotificationsCount > 0 ? VPalette.primary : VPalette.textHint)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.unreadNotificationsCount == 0)
                    .accessibilityLabel(S.notifMarkAllRead)
                }

                if store.notifications.isEmpty && !isRefreshing {
                    EmptyStateView(
                        icon: "bell.slash",
                        title: S.notifEmptyTitle,
                        subtitle: S.notifEmptyBody
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            if isRefreshing && store.notifications.isEmpty {
                                ForEach(0..<3, id: \.self) { _ in
                                    VSkeleton(height: 70, corner: 16)
                                }
                                .padding(.horizontal, 16)
                            }

                            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                                VStack(alignment: .leading, spacing: 8) {
                                    VKicker(text: group.label).padding(.horizontal, 4)
                                    // Per-row cards (was a single grouped
                                    // container) so each row can have its
                                    // own swipe-to-clear gesture without
                                    // the action button getting clipped by
                                    // the parent's rounded corners.
                                    VStack(spacing: 8) {
                                        ForEach(group.items, id: \.id) { n in
                                            notifRow(n)
                                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
                                                .swipeToClear(label: S.notifClear) {
                                                    store.dismissNotificationLocally(n.id)
                                                }
                                                // Combined leading-slide + opacity transition so
                                                // the row reads as continuing leftward off-screen
                                                // even after the sweep animation hands off to the
                                                // parent's ForEach diff.
                                                .transition(.asymmetric(
                                                    insertion: .opacity,
                                                    removal: .move(edge: .leading).combined(with: .opacity)
                                                ))
                                        }
                                    }
                                    .animation(.easeInOut(duration: 0.28), value: group.items.map(\.id))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                    .refreshable {
                        await store.refreshNotifications()
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            // Ensure a fresh pull when the view appears, even if the
            // global `refreshAll` ran a while back.
            isRefreshing = true
            await store.refreshNotifications()
            isRefreshing = false
        }
    }

    // MARK: - Row

    private func notifRow(_ n: NotificationDTO) -> some View {
        let style = NotificationStyle.from(typeRaw: n.type)
        let unread = n.readAt == nil
        return Button {
            handleTap(n)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if unread {
                    Circle().fill(VPalette.primary).frame(width: 6, height: 6).padding(.top, 14)
                } else {
                    Color.clear.frame(width: 6, height: 6)
                }
                VIconBubble(systemName: style.icon, color: style.color, size: 38, iconSize: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(n.title)
                            .font(.footnote.weight(.heavy))
                            .foregroundColor(VPalette.text)
                        Spacer()
                        Text(relativeTime(n.createdAt))
                            .font(.caption2.weight(.bold))
                            .foregroundColor(VPalette.textHint)
                    }
                    if !n.body.isEmpty {
                        Text(n.body)
                            .font(.caption)
                            .foregroundColor(VPalette.textSec)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(unread ? VPalette.primaryContainer.opacity(0.35) : VPalette.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Marks the notification read optimistically and routes to the
    /// best-fitting destination. Notifications referencing objects
    /// that aren't (yet) in the local store still mark-read but stay
    /// on this screen — better than navigating to a 404.
    private func handleTap(_ n: NotificationDTO) {
        Task { await store.markNotificationRead(n.id) }
        // CHAT_MESSAGE: special-case to open the matching thread.
        // Server-side fan-out sets `routeId` on every CHAT_MESSAGE
        // notification; we resolve that to the local `ChatThread`
        // and post `.voygoOpenThread` — same path the in-app push
        // tap takes. Without this branch, tapping a chat
        // notification just navigated to Route Details (or
        // nowhere), and the rider had to manually jump to Inbox.
        let kind = n.type.uppercased()
        if (kind == "CHAT_MESSAGE" || kind == "MESSAGE"),
           let routeId = n.routeId,
           let thread = store.threads.first(where: { $0.tripId == routeId }) {
            NotificationCenter.default.post(
                name: .voygoOpenThread,
                object: nil,
                userInfo: ["threadId": thread.id, "title": thread.title]
            )
            return
        }
        if let routeId = n.routeId, store.routes.contains(where: { $0.id == routeId }) {
            onOpenRoute(routeId)
            return
        }
        if n.subscriptionId != nil {
            onOpenSubscriptions()
            return
        }
        if n.rideInstanceId != nil {
            onOpenCalendar()
            return
        }
        // No referenced object — read-only notification, no navigation.
    }

    /// Compact relative timestamp (`2m`, `4h`, `Tue`, `Mar 12`) so the
    /// row trailing slot stays narrow even on long notification titles.
    private func relativeTime(_ date: Date) -> String {
        let now = Date()
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60        { return "now" }
        if elapsed < 3600      { return "\(Int(elapsed / 60))m" }
        if elapsed < 86_400    { return "\(Int(elapsed / 3600))h" }
        if elapsed < 86_400 * 7 {
            let f = DateFormatter(); f.dateFormat = "EEE"
            return f.string(from: date)
        }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

/// Decoration for a notification kind. Keeping this server-string-driven
/// means a backend that introduces a new `kind` doesn't break the iOS
/// build — unknown kinds fall back to a neutral icon.
private struct NotificationStyle {
    let icon: String
    let color: Color

    static func from(typeRaw: String) -> NotificationStyle {
        switch typeRaw.uppercased() {
        case "RIDE_REMINDER", "PICKUP_REMINDER":
            return .init(icon: "clock.fill",        color: VPalette.warning)
        case "DRIVER_UPDATE", "ROUTE_UPDATE":
            return .init(icon: "car.fill",          color: VPalette.primary)
        case "DRIVER_ARRIVED", "ON_THE_WAY":
            return .init(icon: "location.fill",     color: VPalette.success)
        case "SUBSCRIPTION_PAUSED", "SUBSCRIPTION_CANCELLED":
            return .init(icon: "pause.fill",        color: VPalette.warning)
        case "PAYMENT_FAILED", "CHARGE_FAILED":
            return .init(icon: "exclamationmark.triangle.fill", color: VPalette.danger)
        case "PAYMENT_SUCCEEDED", "CHARGED":
            return .init(icon: "checkmark.seal.fill", color: VPalette.success)
        case "REFUND", "CREDITED":
            return .init(icon: "arrow.uturn.left",  color: VPalette.success)
        case "CHAT_MESSAGE", "MESSAGE":
            return .init(icon: "bubble.left.fill",  color: VPalette.accent)
        case "SAFETY_ALERT", "SOS":
            return .init(icon: "exclamationmark.shield.fill", color: VPalette.danger)
        default:
            return .init(icon: "bell.fill",         color: VPalette.textSec)
        }
    }
}

#Preview("NotificationsView") {
    NotificationsView(onBack: {})
        .environment(AppStore())
}
