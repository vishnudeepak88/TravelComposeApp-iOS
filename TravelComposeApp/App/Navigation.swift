import SwiftUI

// MARK: - Root Navigation

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var authStep: AuthStep = .phone

    enum AuthStep: Equatable { case phone, otp(phone: String) }

    var body: some View {
        Group {
            if store.isAuthenticated {
                MainTabView()
            } else {
                switch authStep {
                case .phone:
                    AuthPhoneView { _ in
                        authStep = .otp(phone: store.phoneNumber)
                    }
                case .otp(let phone):
                    AuthOtpView(phoneNumber: phone, onBack: {
                        authStep = .phone
                    })
                }
            }
        }
        // Ask for push permission the first time the user lands
        // signed-in, then re-register on every subsequent
        // authenticated launch so token rotations get picked up.
        .task(id: store.isAuthenticated) {
            if store.isAuthenticated && AppCapabilities.pushNotificationsAvailable {
                await requestPushAuthorizationIfNeeded()
            }
        }
    }
}

// MARK: - Main Tab Bar
//
// Native `TabView` with `Tab` + `value:` selection. Migrated from a
// custom `VoygoTabBar` HStack in Dec 2026 — the previous implementation
// bypassed iOS 26 Liquid Glass materials, had no Voice Control / VoiceOver
// labels (every tab announced as "Button"), and no badge support. The
// native API gets all of that for free.
//
// Tab-reselect (tap the active tab to scroll the root to top) is
// preserved via a custom Binding that detects same-value writes —
// `TabView` doesn't fire `onChange` when the selected tab is re-tapped,
// so the binding's `set` block is the only hook we have.

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedTab: VoygoTab = .home

    enum VoygoTab: Int, Hashable {
        case home = 0, search = 1, calendar = 2, inbox = 3, profile = 4
    }

    /// Binding that mirrors selectedTab but ALSO posts the
    /// `voygoTabReselected` notification when the user taps the
    /// currently-active tab. Tab roots (HomeTab, InboxView, etc.)
    /// listen and scroll their root ScrollView to top — the iOS
    /// convention for repeated taps.
    private var tabBinding: Binding<VoygoTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab {
                    NotificationCenter.default.post(
                        name: .voygoTabReselected,
                        object: nil,
                        userInfo: ["index": newValue.rawValue]
                    )
                } else {
                    selectedTab = newValue
                }
            }
        )
    }

    var body: some View {
        TabView(selection: tabBinding) {
            // `.dynamicTypeSize(...DynamicTypeSize.accessibility3)`
            // caps the upper bound so layouts that mix system fonts
            // (Dynamic Type aware) with the remaining .font(.system(
            // size:)) hold-outs don't break at the very largest
            // accessibility sizes. AccessibilityXXL still works;
            // we cap at the third accessibility size to balance
            // readability and the existing fixed-size layouts.
            Tab("Home", systemImage: "house.fill", value: VoygoTab.home) {
                HomeTab()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            .accessibilityLabel("Home tab")
            .accessibilityHint("Your next commute and quick actions")

            Tab("Search", systemImage: "magnifyingglass", value: VoygoTab.search) {
                CommuteTab()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            .accessibilityLabel("Search tab")
            .accessibilityHint("Find a carpool route")

            Tab("Calendar", systemImage: "calendar", value: VoygoTab.calendar) {
                TripsTab()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            .accessibilityLabel("Calendar tab")
            .accessibilityHint("Your subscriptions and upcoming rides")

            Tab("Inbox", systemImage: "bubble.left.fill", value: VoygoTab.inbox) {
                InboxView()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            // Sum of per-thread unread counts. Native `.badge` shows
            // the red dot+number on the tab automatically when the
            // value is non-zero. Free affordance the custom tab bar
            // didn't have.
            .badge(store.threads.reduce(0) { $0 + max(0, $1.unreadCount) })
            .accessibilityLabel("Inbox tab")
            .accessibilityHint("Chats with your drivers and notifications")

            Tab("Profile", systemImage: "person.fill", value: VoygoTab.profile) {
                ProfileView()
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            .accessibilityLabel("Profile tab")
            .accessibilityHint("Your account, vehicle and settings")
        }
        // iOS 18+ TabView gets Liquid Glass on iOS 26 automatically;
        // tint sets the brand colour on the selected-tab indicator.
        .tint(VPalette.primary)
        .overlay(alignment: .top) {
            if let message = store.connectionState.bannerText {
                SyncStatusBanner(message: message, isOffline: store.connectionState.isOffline)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .voygoAnimation(.spring(response: 0.32, dampingFraction: 0.82), value: store.connectionState)
        .task {
            await store.refreshAll()
        }
        // Cross-tab deep linking — same NotificationCenter pattern as
        // before; the native TabView selection works exactly like the
        // old `selectedTab` Int.
        .onReceive(NotificationCenter.default.publisher(for: HomeTab.switchToInboxNotification)) { _ in
            selectedTab = .inbox
        }
        .onReceive(NotificationCenter.default.publisher(for: .voygoOpenThread)) { _ in
            selectedTab = .inbox
        }
        .onReceive(NotificationCenter.default.publisher(for: InboxView.openFindRoutesNotification)) { _ in
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .voygoOpenRoute)) { _ in
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .voygoOpenRide)) { _ in
            selectedTab = .calendar
        }
    }
}

private struct SyncStatusBanner: View {
    let message: String
    let isOffline: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isOffline {
                Image(systemName: "wifi.slash")
                    .font(.caption.weight(.bold))
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(VoygoTheme.primary)
            }
            Text(message)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundColor(isOffline ? VoygoTheme.warning : VoygoTheme.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(VoygoTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((isOffline ? VoygoTheme.warning : VoygoTheme.primary).opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

/// Posted when a user taps the already-selected tab. Tab roots opt
/// in by listening for this and scrolling their primary ScrollView to
/// the top. Each notification carries the tab index so multi-tab roots
/// can disambiguate.
extension Notification.Name {
    static let voygoTabReselected = Notification.Name("voygo.tabReselected")
    /// Cross-tab deep-link to a specific chat thread. Posted with userInfo
    /// `["threadId": String, "title": String]`. MainTabView switches to the
    /// Inbox tab and InboxView appends the thread to its NavigationStack
    /// path. Used by notification taps and Driver-dashboard "Message rider"
    /// without giving every tab a shared NavigationPath.
    static let voygoOpenThread = Notification.Name("voygo.openThread")
    // `voygoOpenRoute` lives in PushRegistration.swift — the share-link
    // deep-link and APNs route-tap both fire it. AppStore.handleDeepLink
    // posts it; MainTabView + CommuteTab listen below.
}

// VoygoTabBar was the custom HStack tab bar that bypassed native
// TabView. Replaced by the native `TabView { Tab ... }` block above —
// the new code uses `selection: Binding<VoygoTab>` for the same tab-
// reselect behaviour but gets iOS 26 Liquid Glass, accessibility
// labels, and badge support for free.
//
// The struct is kept as a `@available(*, deprecated)` shim so any
// stale callsite that still references it fails the build loudly
// with a fix-it suggesting `TabView`.
@available(*, deprecated, message: "Use native TabView (see MainTabView). Custom tab bar removed for iOS 26 Liquid Glass + accessibility.")
struct VoygoTabBar: View {
    @Binding var selectedIndex: Int
    var body: some View { EmptyView() }
}

// MARK: - Commute Tab Navigator
//
// Routes are defined in `App/AppRoute.swift`; this tab only owns the
// path + filter-state bindings and delegates the destination switch
// to `appRouteDestinations(...)`.

struct CommuteTab: View {
    @State private var path: [AppRoute] = []
    /// Persistent filter state owned by the tab so SearchFilters can
    /// actually write back. Previously each presentation created throw-
    /// away `Binding(get: { … }, set: { _ in })` placeholders that
    /// silently discarded edits.
    @State private var filtersQuery: String = "Subang Jaya → KLCC"
    @State private var filtersEarliest: String = "06:30"
    @State private var filtersLatest: String = "09:00"
    @State private var filtersDays: DaysOfWeekFlags = .weekdays

    var body: some View {
        NavigationStack(path: $path) {
            FindCommuteRoutesView(
                onOpenRoute:       { path.append(.routeDetails(routeId: $0)) },
                onMySubscriptions: { path.append(.mySubscriptions) },
                onCreateRoute:     { path.append(.createRoute) },
                onDriverDashboard: { path.append(.driverDashboard) }
            )
            .appRouteDestinations(
                path: $path,
                filtersQuery: $filtersQuery,
                filtersEarliest: $filtersEarliest,
                filtersLatest: $filtersLatest,
                filtersDays: $filtersDays
            )
            .navigationBarHidden(true)
            .enableSwipeBack()
            .onReceive(NotificationCenter.default.publisher(for: .voygoOpenRoute)) { note in
                guard let info = note.userInfo,
                      let routeId = info["routeId"] as? String else { return }
                // Avoid stacking duplicates if the user re-taps the same link.
                if path.last != .routeDetails(routeId: routeId) {
                    path.append(.routeDetails(routeId: routeId))
                }
            }
        }
    }
}

// MARK: - Trips Tab Navigator
//
// Subscriptions root, with `routeDetails` and `calendar` reachable from
// the same shared destination map the other tabs use.

struct TripsTab: View {
    @State private var path: [AppRoute] = []
    @State private var filtersQuery: String = ""
    @State private var filtersEarliest: String = "06:30"
    @State private var filtersLatest: String = "09:00"
    @State private var filtersDays: DaysOfWeekFlags = .weekdays

    var body: some View {
        NavigationStack(path: $path) {
            MySubscriptionsView(
                onOpenRoute: { path.append(.routeDetails(routeId: $0)) },
                onOpenCalendar: { path.append(.calendar()) },
                onFindRoutes: { path.append(.findRides) },
                onBack: nil
            )
            .appRouteDestinations(
                path: $path,
                filtersQuery: $filtersQuery,
                filtersEarliest: $filtersEarliest,
                filtersLatest: $filtersLatest,
                filtersDays: $filtersDays
            )
            .navigationBarHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .voygoOpenRide)) { note in
                guard let info = note.userInfo,
                      let rideId = info["rideId"] as? String,
                      !rideId.isEmpty else { return }
                if path.last != .liveTrip(tripId: rideId, isDriver: false) {
                    path.append(.liveTrip(tripId: rideId, isDriver: false))
                }
            }
        }
    }
}
