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
            if store.isAuthenticated {
                await requestPushAuthorizationIfNeeded()
            }
        }
    }
}

// MARK: - Main Tab Bar

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: HomeTab()
                case 1: CommuteTab()
                case 2: TripsTab()
                case 3: InboxView()
                case 4: ProfileView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            VoygoTabBar(selectedIndex: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) {
            if let message = store.connectionState.bannerText {
                SyncStatusBanner(message: message, isOffline: store.connectionState.isOffline)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.connectionState)
        .task {
            await store.refreshAll()
        }
        // Cross-tab deep linking. HomeTab posts this when the user
        // taps Message-driver on the Next-commute card; we switch
        // tabs without owning a shared NavigationPath.
        .onReceive(NotificationCenter.default.publisher(for: HomeTab.switchToInboxNotification)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = 3
            }
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
}

struct VoygoTabBar: View {
    @Binding var selectedIndex: Int

    private let items: [(icon: String, selectedIcon: String, label: String)] = [
        // Renamed: "Routes" → "Search". The tab roots straight onto
        // FindCommuteRoutesView which is a search experience, not a
        // list of the user's routes — keeping the old "Routes" label
        // confused users into thinking it'd show their subscriptions.
        ("house",        "house.fill",         "Home"),
        ("magnifyingglass", "magnifyingglass", "Search"),
        ("calendar",     "calendar",           "Calendar"),
        ("bubble.left",  "bubble.left.fill",   "Inbox"),
        ("person",       "person.fill",        "Profile")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button(action: {
                    if selectedIndex == i {
                        // iOS convention: tap the active tab again to
                        // jump to the top. Roots that care subscribe
                        // via `.voygoTabReselected`.
                        NotificationCenter.default.post(
                            name: .voygoTabReselected,
                            object: nil,
                            userInfo: ["index": i]
                        )
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedIndex = i
                        }
                    }
                }) {
                    VStack(spacing: 5) {
                        Image(systemName: selectedIndex == i ? item.selectedIcon : item.icon)
                            .font(.system(size: 20, weight: selectedIndex == i ? .semibold : .regular))
                            .foregroundColor(selectedIndex == i ? VoygoTheme.onPrimaryContainer : VoygoTheme.textHint)
                            .frame(width: 56, height: 32)
                            .background(
                                Capsule()
                                    .fill(selectedIndex == i ? VoygoTheme.primaryContainer : .clear)
                            )
                        Text(item.label)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(selectedIndex == i ? VoygoTheme.textPrimary : VoygoTheme.textHint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 24)
        .background(
            VoygoTheme.surface
                .overlay(Rectangle().fill(VoygoTheme.cardBorder.opacity(0.5)).frame(height: 1), alignment: .top)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
    }
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
        }
    }
}
