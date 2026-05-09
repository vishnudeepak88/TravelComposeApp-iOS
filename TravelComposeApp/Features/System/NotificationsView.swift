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
        if !today.isEmpty     { out.append(("Today",     today)) }
        if !yesterday.isEmpty { out.append(("Yesterday", yesterday)) }
        if !week.isEmpty      { out.append(("This week", week)) }
        if !earlier.isEmpty   { out.append(("Earlier",   earlier)) }
        return out
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Notifications", onBack: onBack) {
                    Button {
                        Task { await store.markAllNotificationsRead() }
                    } label: {
                        Text("Mark all read")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(store.unreadNotificationsCount > 0 ? VPalette.primary : VPalette.textHint)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.unreadNotificationsCount == 0)
                    .accessibilityLabel("Mark all notifications as read")
                }

                if store.notifications.isEmpty && !isRefreshing {
                    EmptyStateView(
                        icon: "bell.slash",
                        title: "No notifications yet",
                        subtitle: "Ride updates, pickup reminders, and chat alerts will appear here."
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
                                    VStack(spacing: 0) {
                                        ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, n in
                                            notifRow(n)
                                            if idx < group.items.count - 1 {
                                                Rectangle().fill(VPalette.border).frame(height: 1)
                                            }
                                        }
                                    }
                                    .background(VPalette.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
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
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(VPalette.text)
                        Spacer()
                        Text(relativeTime(n.createdAt))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(VPalette.textHint)
                    }
                    if !n.body.isEmpty {
                        Text(n.body)
                            .font(.system(size: 12))
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
