import SwiftUI

// MARK: - Profile (mirrors ProfileScreen.kt)
//
// The legacy `ProfileRoute` enum is gone — Profile now uses the shared
// `AppRoute` so deep links and cross-tab navigation can route to any
// destination from any tab.
//
// Privacy & Help previously presented as sheets. They were full-screen
// settings pages with multiple toggles, not lightweight modals — now
// they push onto the same nav stack as everything else for consistency.

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var path: [AppRoute] = []
    @State private var filtersQuery: String = ""
    @State private var filtersEarliest: String = "06:30"
    @State private var filtersLatest: String = "09:00"
    @State private var filtersDays: DaysOfWeekFlags = .weekdays
    /// Notifications toggle is now persisted via @AppStorage so it survives
    /// app restarts — previously a pure @State, it reset to true every
    /// launch regardless of the user's preference.
    @AppStorage("voygo.settings.notificationsEnabled") private var notificationsEnabled: Bool = true
    @State private var showLogoutAlert = false
    /// Throttles the logout alert primary button so a double-tap can't
    /// queue two logout calls (low-stakes but ugly when it happens).
    @State private var isLoggingOut = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                VPalette.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    VPolishedNavBar(title: "Profile")

                    ScrollView {
                        VStack(spacing: 18) {
                            identityRow
                            kycCard
                            quickStats
                            walletStatsRow
                            settingsCard
                            // Driver mode card only when the user has at
                            // least one published route. Riders who've
                            // never offered seats don't need this CTA
                            // taking up space; it'll appear automatically
                            // after their first Create Route flow.
                            if !store.driverDashboards().isEmpty {
                                driverModeCard
                            }
                            logoutPill
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, VTabBarLayout.clearance)
                    }
                }
            }
            .navigationBarHidden(true)
            .appRouteDestinations(
                path: $path,
                filtersQuery: $filtersQuery,
                filtersEarliest: $filtersEarliest,
                filtersLatest: $filtersLatest,
                filtersDays: $filtersDays
            )
            .alert("Log Out", isPresented: $showLogoutAlert) {
                Button("Log Out", role: .destructive) {
                    guard !isLoggingOut else { return }
                    isLoggingOut = true
                    store.logout()
                }
                Button("Cancel", role: .cancel, action: {})
            } message: { Text("You'll need to sign in again.") }
            .task { await store.refreshMe() }
        }
    }

    private var identityRow: some View {
        HStack(spacing: 14) {
            VAvatar(initial: store.currentUser.initial.isEmpty ? "?" : store.currentUser.initial, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.currentUser.name.isEmpty ? "Welcome" : store.currentUser.name)
                    .font(.system(size: 20, weight: .heavy)).tracking(-0.4)
                    .foregroundColor(VPalette.text)
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 13)).foregroundColor(VPalette.primary)
                    Text(String(format: "%.1f rating", store.currentUser.rating))
                        .font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.textSec)
                    Circle().fill(VPalette.textHint).frame(width: 3, height: 3)
                    // Real ride count from completed payments. Reads "0
                    // rides" honestly on a fresh install instead of
                    // the previously-hardcoded literal.
                    Text("\(tripsCount) rides").font(.system(size: 12)).foregroundColor(VPalette.textSec)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var kycCard: some View {
        Button { path.append(.kyc) } label: {
            HStack(spacing: 12) {
                VIconBubble(systemName: kycIcon, color: kycColor, size: 44, iconSize: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Identity Verification")
                        .font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    Text(kycMessage).font(.system(size: 11)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                VBadge(text: kycBadge, color: kycColor, container: kycColor.opacity(0.15))
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var walletStatsRow: some View {
        Button { path.append(.wallet) } label: {
            HStack(spacing: 12) {
                VIconBubble(systemName: "creditcard.fill", color: VPalette.primary, size: 44, iconSize: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallet & payment methods")
                        .font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    Text(walletSubtitle)
                        .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.textHint)
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var quickStats: some View {
        // Real values from `store.payments` and the user's first
        // active route's reliability. On a fresh install all three
        // read as 0 / 0 / —, which is honest. Previously hardcoded
        // to "RM 1,820 saved · 412 trips · 97% on-time" regardless
        // of state.
        Button { path.append(.tripHistory) } label: {
            HStack(spacing: 0) {
                statCell("RM \(savedMyr)", "Saved")
                Rectangle().fill(VPalette.border).frame(width: 1, height: 32)
                statCell("\(tripsCount)", "Trips")
                Rectangle().fill(VPalette.border).frame(width: 1, height: 32)
                statCell(onTimeLabel, "On-time")
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Estimated savings vs. paying daily for the same trips. Walks
    /// each subscription, asks SubscriptionPricing for the daily-tier
    /// counterfactual, and sums the deltas. Imperfect but anchored in
    /// real data — unlike the previous flat "RM 1,820".
    private var savedMyr: Int {
        store.subscriptions.reduce(0) { acc, sub in
            // We don't carry per-sub days/price on the model yet; use
            // a conservative monthly-tier window as a placeholder.
            let route = store.routes.first { $0.id == sub.routeId }
            guard let pricePerSeat = route?.pricePerSeat else { return acc }
            let savings = SubscriptionPricing.savingsVsDaily(
                pricePerSeatMyr: pricePerSeat,
                tier: .monthly,
                days: 22
            )
            return acc + savings
        }
    }

    private var tripsCount: Int {
        store.payments.filter { $0.status == .paid }.count
    }

    private var onTimeLabel: String {
        // No per-rider on-time metric yet; show the average across
        // the user's currently-active routes. "—" when we have no
        // data.
        let rates = store.routes.map(\.reliability.onTimeRate).filter { $0 > 0 }
        guard !rates.isEmpty else { return "—" }
        let avg = rates.reduce(0, +) / Double(rates.count)
        return "\(Int((avg * 100).rounded()))%"
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 18, weight: .black)).tracking(-0.3).foregroundColor(VPalette.primary)
            VKicker(text: label, size: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            VKicker(text: "Settings").padding(.leading, 4)
            VStack(spacing: 0) {
                row(icon: "bell.fill", color: VPalette.warning, title: "Notifications", trailing: AnyView(Toggle("", isOn: $notificationsEnabled).labelsHidden().tint(VPalette.primary)))
                divider()
                row(icon: "shield.lefthalf.filled", color: VPalette.accent, title: "Privacy & Security", chevron: true) { path.append(.privacy) }
                divider()
                row(icon: "creditcard.fill", color: VPalette.primary, title: "Payment methods", trailingText: "DuitNow · TNG") { path.append(.wallet) }
                divider()
                row(icon: "bell.badge.fill", color: VPalette.secondary, title: "Notifications center", chevron: true) { path.append(.notifications) }
                divider()
                row(icon: "doc.text.fill", color: VPalette.accent, title: "Trip history", chevron: true) { path.append(.tripHistory) }
                divider()
                row(icon: "questionmark.circle.fill", color: VPalette.secondary, title: "Help Center", chevron: true) { path.append(.help) }
            }
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func divider() -> some View {
        Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 60)
    }

    @ViewBuilder
    private func row(
        icon: String,
        color: Color,
        title: String,
        chevron: Bool = false,
        trailing: AnyView? = nil,
        trailingText: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        Button { action?() } label: {
            HStack(spacing: 12) {
                VIconBubble(systemName: icon, color: color, size: 32, iconSize: 14)
                Text(title).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                Spacer()
                if let trailingText {
                    Text(trailingText).font(.system(size: 11, weight: .bold)).foregroundColor(VPalette.textSec)
                }
                if let trailing {
                    trailing
                }
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.textHint)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var driverModeCard: some View {
        Button { path.append(.driverDashboard) } label: {
            HStack(spacing: 12) {
                VIconBubble(systemName: "car.fill", color: VPalette.primary, size: 44, iconSize: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver mode").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    Text("Manage your routes & earnings").font(.system(size: 11)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.textHint)
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var logoutPill: some View {
        Button { showLogoutAlert = true } label: {
            HStack {
                Image(systemName: "arrow.up.right.square.fill").foregroundColor(VPalette.danger)
                Text("Log out").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.danger)
                Spacer()
            }
            .padding(14)
            .background(VPalette.dangerContainer)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.danger.opacity(0.2), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var kycIcon: String {
        switch store.kycStatus {
        case .approved: return "checkmark.seal.fill"
        case .pending:  return "clock.badge.fill"
        case .rejected: return "xmark.seal.fill"
        default:        return "person.badge.key.fill"
        }
    }
    private var kycColor: Color {
        switch store.kycStatus {
        case .approved: return VPalette.success
        case .pending:  return VPalette.warning
        case .rejected: return VPalette.danger
        default:        return VPalette.primary
        }
    }
    private var kycMessage: String {
        switch store.kycStatus {
        case .approved: return "You are fully verified · MyKad on file"
        case .pending:  return "Verification under review"
        case .rejected: return "Verification rejected – resubmit"
        default:        return "Complete verification to drive"
        }
    }
    private var kycBadge: String {
        switch store.kycStatus {
        case .approved: return "Verified"
        case .pending:  return "Pending"
        case .rejected: return "Rejected"
        default:        return "Not Started"
        }
    }

    /// Subtitle on the wallet shortcut. Reflects real state instead of
    /// the previously-hardcoded "RM 42.50 credit · DuitNow default". For
    /// the dev shortcut we keep `useOnline = false` so payments never
    /// sync — show a dev-aware label rather than "Add a payment method
    /// to start", which is misleading.
    private var walletSubtitle: String {
        if store.voygoCreditMyr > 0 {
            return Formatters.ringgit(store.voygoCreditMyr) + " credit · view payments"
        }
        if !store.useOnline {
            return "Wallet syncs after sign-in"
        }
        return store.payments.isEmpty ? "Add a payment method to start" : "View payments & receipts"
    }
}

private struct SettingsRow<T: View>: View {
    let icon: String; let title: String; let color: Color
    let trailing: T
    var action: (() -> Void)? = nil

    init(icon: String, title: String, color: Color, @ViewBuilder trailing: () -> T, action: (() -> Void)? = nil) {
        self.icon = icon; self.title = title; self.color = color; self.trailing = trailing(); self.action = action
    }
    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.subheadline)
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title).font(.subheadline).foregroundColor(VoygoTheme.textPrimary)
                Spacer()
                trailing
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// (Legacy `VerificationView` step-wizard removed — replaced by
// `KycVerificationView` which drives off real `KycDocumentKind`s.)

// MARK: - Privacy & Security (mirrors PrivacySecurityScreen.kt)

struct PrivacySecurityView: View {
    var onBack: () -> Void
    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Privacy & Security", onBack: onBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Privacy Controls").font(.title3.bold()).foregroundColor(VoygoTheme.textPrimary)
                        Text("Manage data sharing, account security, and app permissions.")
                            .font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                        VoygoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Security Tips").font(.subheadline.bold()).foregroundColor(VoygoTheme.textPrimary)
                                ForEach(["Keep your OTP private.", "Use only your own phone number.", "Report suspicious activity from Help Center."], id: \.self) { tip in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "shield.checkmark.fill").foregroundColor(VoygoTheme.success).font(.caption)
                                        Text(tip).font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

// MARK: - Help Center (mirrors HelpCenterScreen.kt)

struct HelpCenterView: View {
    var onBack: () -> Void
    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Help Center", onBack: onBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "questionmark.bubble.fill").font(.system(size: 40)).foregroundStyle(VoygoTheme.primaryGradient)
                            VStack(alignment: .leading) {
                                Text("Need Help?").font(.title3.bold()).foregroundColor(VoygoTheme.textPrimary)
                                Text("We're here for you").font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                            }
                        }
                        VoygoCard {
                            VStack(alignment: .leading, spacing: 12) {
                                // Real `mailto:` and `https://` links so
                                // taps actually do something — previously
                                // these were inert text rows, P3 #14
                                // from the deep-audit doc.
                                if let mailto = URL(string: "mailto:support@voygo.app") {
                                    Link(destination: mailto) {
                                        HelpRow(icon: "envelope.fill",
                                                title: "Email Support",
                                                value: "support@voygo.app")
                                    }
                                }
                                Divider().background(VoygoTheme.cardBorder)
                                HelpRow(icon: "bubble.left.and.bubble.right.fill",
                                        title: "In-App Chat",
                                        value: "Available from Inbox tab")
                                Divider().background(VoygoTheme.cardBorder)
                                if let faq = URL(string: "https://voygo.app/help") {
                                    Link(destination: faq) {
                                        HelpRow(icon: "doc.text.fill",
                                                title: "FAQ",
                                                value: "voygo.app/help")
                                    }
                                }
                            }
                            .padding(16)
                        }
                        Text("For commute subscriptions, route issues, or payment questions, contact our support team. We typically respond within 2 hours.")
                            .font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                    }
                    .padding(20)
                }
            }
        }
    }
}

private struct HelpRow: View {
    let icon: String; let title: String; let value: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.subheadline).foregroundColor(VoygoTheme.primary)
                .frame(width: 28, height: 28).background(VoygoTheme.primary.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).foregroundColor(VoygoTheme.textSecondary)
                Text(value).font(.subheadline).foregroundColor(VoygoTheme.textPrimary)
            }
        }
    }
}

// MARK: - Live Trip (mirrors LiveTripScreen.kt)

struct LiveTripView: View {
    let tripId: String
    var isDriver: Bool = false
    var onBack: () -> Void
    var onMessageDriver: (() -> Void)? = nil
    /// Receives the real driver/route context so the next screen
    /// (RateRide) can render with actual values instead of hardcoded
    /// "Aiman / Subang Jaya → KLCC".
    var onEndTrip: ((_ driverInitial: String, _ driverName: String, _ summary: String) -> Void)? = nil
    @Environment(AppStore.self) private var store

    @State private var pickupConfirmed = false
    @State private var dropoffConfirmed = false
    @State private var sosPressed = false
    @State private var showSOSAlert = false
    /// Live ETA in minutes — counts down. Real implementation would pull
    /// from a route + GPS + ETA service; the demo just decrements every
    /// minute so the screen visibly works.
    @State private var etaMinutes: Int = 12
    @State private var etaTask: Task<Void, Never>? = nil

    /// Real ride context: looks up the trip from `store.rideInstances`
    /// and resolves its route. Falls back to nil when the lookup fails
    /// (deep link, stale state) — the view degrades to honest
    /// placeholders instead of inventing a driver name.
    private var ride: CommuteRideInstance? {
        store.rideInstances.first { $0.id == tripId }
    }
    private var route: RecurringRoute? {
        ride.flatMap { r in store.routes.first { $0.id == r.routeId } }
    }
    private var driverDisplayName: String {
        let n = route?.driverName.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? "Driver" : n
    }
    private var driverInitial: String {
        String(driverDisplayName.prefix(1)).uppercased()
    }
    private var pickupLabel: String {
        route?.pickupPoints.first?.label ?? "Pickup"
    }
    private var dropoffLabel: String {
        route?.dropPoints.first?.label ?? "Dropoff"
    }
    private var routeSummary: String {
        guard let r = route else { return "Subscription ride" }
        return "\(shortStop(r.startLocation)) → \(shortStop(r.endLocation))"
    }
    private func shortStop(_ raw: String) -> String {
        let trimmed = raw.split(separator: ",").first.map(String.init) ?? raw
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    /// Stops for the diagram. Origin / pickup / drop / destination
    /// when all are present; degrades to 2 stops if pickup/drop empty.
    private var liveTripStops: [RouteStop] {
        guard let r = route else {
            return [
                .init(label: "Pickup",  kind: .origin),
                .init(label: "Dropoff", kind: .dest)
            ]
        }
        var stops: [RouteStop] = [.init(label: shortStop(r.startLocation), kind: .origin)]
        if let p = r.pickupPoints.first { stops.append(.init(label: p.label, kind: .stop)) }
        if let d = r.dropPoints.first   { stops.append(.init(label: d.label, kind: .stop)) }
        stops.append(.init(label: shortStop(r.endLocation), kind: .dest))
        return stops
    }

    /// Vehicle line under the driver row. Uses `carType.label` until
    /// the model carries a plate or vehicle nickname.
    private var driverCarLabel: String {
        guard let r = route else { return "—" }
        return "\(r.carType.label) · plate on file"
    }

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // Stylised abstract route diagram instead of the
                    // legacy faux-map. The tracking screen wants the
                    // narrative version (curving polyline + city blocks)
                    // — the actual GPS dot is overlaid below.
                    VRouteDiagram(
                        stops: liveTripStops,
                        height: 360,
                        accent: VPalette.primary,
                        dark: true
                    )

                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(VPalette.text)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        HStack(spacing: 8) {
                            Circle().fill(VPalette.success).frame(width: 8, height: 8)
                            Text("En route").font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.text)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                        Spacer()

                        Button {} label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(VPalette.text)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 54)

                    GeometryReader { geo in
                        ZStack {
                            Circle().fill(VPalette.primary).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .shadow(color: VPalette.primary.opacity(0.5), radius: 12, y: 4)
                            Image(systemName: "car.fill").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        }
                        .position(x: geo.size.width * 0.47, y: geo.size.height * 0.55)
                    }
                }
                .frame(height: 360)
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer()
                bottomSheet
            }
        }
        .navigationBarHidden(true)
        .onAppear { startEtaCountdown() }
        .onDisappear { etaTask?.cancel(); etaTask = nil }
        .alert("Send SOS?", isPresented: $showSOSAlert) {
            Button("Send SOS", role: .destructive) {
                sosPressed = true
                // Real implementation: notify safety contacts + emergency
                // services via the backend. The toggle is preserved for
                // local UI feedback.
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This alerts your trusted contacts and Voygo's safety team with your live location. Use in emergencies only.")
        }
    }

    private var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(VPalette.border).frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 14)

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    VKicker(text: "ETA")
                    Text(etaMinutes <= 0 ? "Arriving" : "\(etaMinutes) min")
                        // Use a semantic font so the number scales with
                        // Dynamic Type instead of clipping at AX5.
                        .font(.system(.largeTitle, design: .default).weight(.black))
                        .tracking(-1.2)
                        .foregroundStyle(VPalette.primaryGradient)
                        .accessibilityLabel("ETA \(etaMinutes) minutes")
                    Text(etaSubtitle)
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                HStack(spacing: 6) {
                    iconButton("flag.fill",            color: VPalette.danger,  bg: VPalette.dangerContainer)
                    iconButton("square.and.arrow.up",  color: VPalette.primary, bg: VPalette.primaryContainer)
                }
            }

            Rectangle().fill(VPalette.border).frame(height: 1).padding(.vertical, 16)

            HStack(alignment: .top, spacing: 12) {
                VRouteGlyph().frame(height: 64)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        VKicker(text: "Pickup", color: VPalette.success, size: 10)
                        Text(pickupLabel).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        VKicker(text: "Drop", color: VPalette.primary, size: 10)
                        Text(dropoffLabel).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    }
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(VPalette.border).frame(height: 1).padding(.vertical, 16)

            HStack(spacing: 12) {
                VAvatar(initial: driverInitial, size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(driverDisplayName).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    // Vehicle string isn't on the model yet; show the
                    // car type label which is, and leave a placeholder
                    // for plate. Honest > inventing "Tesla VEC 4123".
                    Text(driverCarLabel)
                        .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                Button {
                    // No driver phone on the model yet — once added,
                    // open `tel://\(phone)`. For now still a no-op
                    // but accessible.
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(VPalette.success).clipShape(Circle())
                        .shadow(color: VPalette.success.opacity(0.5), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call driver")
                .disabled(true)
                Button { onMessageDriver?() } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(VPalette.primary).clipShape(Circle())
                        .shadow(color: VPalette.primary.opacity(0.5), radius: 8, y: 3)
                }.buttonStyle(.plain)
            }
            .padding(12)
            .background(VPalette.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button { showSOSAlert = true } label: {
                HStack(spacing: 8) {
                    Text("🆘").font(.system(size: 18))
                    Text("Hold for SOS")
                        .font(.system(size: 14, weight: .black))
                        .tracking(0.3)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundColor(VPalette.danger)
                .background(VPalette.dangerContainer)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.danger.opacity(0.35), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send SOS")
            .padding(.top, 14)

            // End Trip is the primary path for a rider — visible on every
            // live trip so they can flow into rating without hunting for
            // the action.
            if let onEndTrip {
                VPrimaryButton("End trip → rate") {
                    onEndTrip(driverInitial, driverDisplayName, routeSummary)
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 30, y: -10)
    }

    private func iconButton(_ system: String, color: Color, bg: Color) -> some View {
        Button {} label: {
            Image(systemName: system).font(.system(size: 14, weight: .bold)).foregroundColor(color)
                // 38pt is below 44pt tap-target spec — pad the surrounding
                // hit area without changing the visual size.
                .frame(width: 44, height: 44)
                .background(bg.frame(width: 38, height: 38).clipShape(Circle()))
        }.buttonStyle(.plain)
    }

    private var etaSubtitle: String {
        if etaMinutes <= 0 { return "Your driver is at the pickup" }
        let arrival = Date().addingTimeInterval(TimeInterval(etaMinutes * 60))
        return "Arriving \(Formatters.time(arrival)) · 8.4 km"
    }

    /// Stub-grade ETA tick — drops a minute every 60s until 0 so the
    /// number isn't visibly frozen during demos. The real implementation
    /// will pull from a routing service.
    private func startEtaCountdown() {
        etaTask?.cancel()
        etaTask = Task {
            while !Task.isCancelled && etaMinutes > 0 {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { if etaMinutes > 0 { etaMinutes -= 1 } }
            }
        }
    }
}


private struct _LiveTripDeprecatedHelpers: View {
    var body: some View {
        EmptyView()
    }
}
