import SwiftUI

// MARK: - Root Navigation

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var authStep: AuthStep = .phone
    @State private var pendingPhone = ""

    enum AuthStep { case phone, otp(phone: String) }

    var body: some View {
        if store.isAuthenticated {
            MainTabView()
        } else {
            switch authStep {
            case .phone:
                AuthPhoneView { phone in
                    pendingPhone = phone
                    authStep = .otp(phone: phone)
                }
            case .otp(let phone):
                AuthOtpView(phoneNumber: phone) { code in
                    store.phoneNumber = phone
                    store.completeSignIn(code: code)
                } onBack: {
                    authStep = .phone
                }
            }
        }
    }
}

// MARK: - Main Tab Bar

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case 0: CommuteTab()
                case 1: InboxView()
                case 2: ProfileView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            VoygoTabBar(selectedIndex: $selectedTab)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

struct VoygoTabBar: View {
    @Binding var selectedIndex: Int

    private let items: [(icon: String, selectedIcon: String, label: String)] = [
        ("house",        "house.fill",        "Commute"),
        ("bubble.left",  "bubble.left.fill",  "Inbox"),
        ("person",       "person.fill",       "Profile")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedIndex = i } }) {
                    VStack(spacing: 4) {
                        Image(systemName: selectedIndex == i ? item.selectedIcon : item.icon)
                            .font(.system(size: 22, weight: selectedIndex == i ? .bold : .regular))
                            .foregroundColor(selectedIndex == i ? VoygoTheme.primary : VoygoTheme.textHint)
                            .scaleEffect(selectedIndex == i ? 1.12 : 1.0)
                        Text(item.label)
                            .font(.caption2.weight(selectedIndex == i ? .bold : .regular))
                            .foregroundColor(selectedIndex == i ? VoygoTheme.primary : VoygoTheme.textHint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background(
            VoygoTheme.surface
                .overlay(Rectangle().fill(VoygoTheme.cardBorder).frame(height: 1).padding(.bottom, 0), alignment: .top)
                .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
        )
        .shadow(color: .black.opacity(0.25), radius: 16, y: -4)
    }
}

// MARK: - Commute Tab Navigator

struct CommuteTab: View {
    @State private var path: [CommuteRoute] = []

    enum CommuteRoute: Hashable {
        case routeDetails(routeId: String)
        case mySubscriptions
        case calendar(routeId: String? = nil)
        case createRoute
        case driverDashboard
        case driverCalendar(routeId: String)
        case liveTrip(tripId: String, isDriver: Bool)
    }

    var body: some View {
        NavigationStack(path: $path) {
            FindCommuteRoutesView(
                onOpenRoute:       { path.append(.routeDetails(routeId: $0)) },
                onMySubscriptions: { path.append(.mySubscriptions) },
                onCreateRoute:     { path.append(.createRoute) },
                onDriverDashboard: { path.append(.driverDashboard) }
            )
            .navigationDestination(for: CommuteRoute.self) { route in
                switch route {
                case .routeDetails(let id):
                    RouteDetailsView(routeId: id, onBack: { path.removeLast() })
                        .navigationBarHidden(true)

                case .mySubscriptions:
                    MySubscriptionsView(
                        onOpenRoute: { path.append(.routeDetails(routeId: $0)) },
                        onOpenCalendar: { path.append(.calendar()) },
                        onBack: { path.removeLast() }
                    )
                    .navigationBarHidden(true)

                case .calendar(let routeId):
                    UpcomingCalendarView(routeId: routeId, onBack: { path.removeLast() })
                        .navigationBarHidden(true)

                case .createRoute:
                    CreateRouteView(
                        onBack: { path.removeLast() },
                        onCreated: { id in
                            // pop back to root and open created route
                            path = [.routeDetails(routeId: id)]
                        }
                    )
                    .navigationBarHidden(true)

                case .driverDashboard:
                    DriverDashboardView(
                        onBack:         { path.removeLast() },
                        onOpenCalendar: { path.append(.driverCalendar(routeId: $0)) }
                    )
                    .navigationBarHidden(true)

                case .driverCalendar(let routeId):
                    UpcomingCalendarView(routeId: routeId, onBack: { path.removeLast() })
                        .navigationBarHidden(true)

                case .liveTrip(let id, let isDriver):
                    LiveTripView(tripId: id, isDriver: isDriver, onBack: { path.removeLast() })
                        .navigationBarHidden(true)
                }
            }
            .navigationBarHidden(true)
        }
    }
}
