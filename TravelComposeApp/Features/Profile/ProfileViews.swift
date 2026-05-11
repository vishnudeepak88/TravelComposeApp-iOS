import SwiftUI
import CoreLocation

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
    // The previous `notificationsEnabled` @AppStorage was a placebo —
    // flipping it did nothing (no UNUserNotificationCenter call,
    // no server write). Removed: the Notifications row now bounces
    // to iOS Settings via UIApplication.openSettingsURLString, which
    // is Apple's recommended pattern for notification opt-out.
    @State private var showLogoutAlert = false
    /// Throttles the logout alert primary button so a double-tap can't
    /// queue two logout calls (low-stakes but ugly when it happens).
    @State private var isLoggingOut = false
    /// Edit-name sheet state. The Profile identity row is tappable so
    /// a fresh signup who lands on the auto-generated "User 6789"
    /// fallback can replace it with their real name in two taps.
    @State private var showEditName = false
    /// Edit-vehicle sheet for drivers. Vehicle identity (plate +
    /// colour + model) lives on the user profile — not per-route —
    /// so a driver can't bait riders with one plate on a route and
    /// arrive in a different car.
    @State private var showEditVehicle = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                VPalette.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    VPolishedNavBar(title: "Profile")

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 18) {
                                Color.clear.frame(height: 0).id("top")
                                identityRow
                                kycCard
                                quickStats
                                walletStatsRow
                                // Favorites + requests entry points —
                                // surfaced as compact tiles so a rider
                                // can find what they saved + what they
                                // asked for without buried navigation.
                                myCommuteSection
                                // Vehicle identity card for drivers.
                                // Always rendered once a user has at
                                // least one published route (they're
                                // verifiably a driver) — that's the
                                // same gate we use for driverModeCard.
                                // We also show it for KYC-approved
                                // users so they can pre-fill it before
                                // creating their first route.
                                if shouldShowVehicleCard {
                                    vehicleCard
                                }
                                settingsCard
                                // Driver mode card visible to anyone who's
                                // either KYC-approved (very likely to become
                                // a driver) OR already has routes. Matches
                                // the vehicle-card gate above so an approved
                                // driver isn't left wondering "I'm verified,
                                // where do I create my first route?". Copy
                                // adapts: "Publish your first route" before
                                // they have any, "Manage routes & earnings"
                                // once they do.
                                if shouldShowDriverModeCard {
                                    driverModeCard
                                }
                                logoutPill
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, VTabBarLayout.clearance)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .voygoTabReselected)) { note in
                            if (note.userInfo?["index"] as? Int) == 4 {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo("top", anchor: .top)
                                }
                            }
                        }
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
            .sheet(isPresented: $showEditName) {
                EditDisplayNameSheet(
                    initialName: store.currentUser.name,
                    onCancel: { showEditName = false },
                    onSave:   { newName in
                        let result = await store.updateDisplayName(newName)
                        if case .success = result { showEditName = false }
                        return result
                    }
                )
                .presentationDetents([.height(280)])
            }
            .sheet(isPresented: $showEditVehicle) {
                EditVehicleSheet(
                    initialPlate: store.currentUser.plateNumber ?? "",
                    initialColor: store.currentUser.carColor ?? "",
                    initialModel: store.currentUser.carModel ?? "",
                    onCancel: { showEditVehicle = false },
                    onSave: { plate, color, model in
                        let result = await store.updateVehicle(plate: plate, color: color, model: model)
                        if case .success = result { showEditVehicle = false }
                        return result
                    }
                )
                .presentationDetents([.height(440)])
            }
            .task { await store.refreshMe() }
            .enableSwipeBack()
        }
    }

    private var identityRow: some View {
        Button {
            showEditName = true
        } label: {
            identityRowContent
        }
        .buttonStyle(.plain)
        .accessibilityHint("Tap to edit your display name")
    }

    private var identityRowContent: some View {
        HStack(spacing: 14) {
            VAvatar(initial: store.currentUser.initial.isEmpty ? "?" : store.currentUser.initial, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(store.currentUser.name.isEmpty ? "Welcome" : store.currentUser.name)
                        .font(.system(size: 20, weight: .heavy)).tracking(-0.4)
                        .foregroundColor(VPalette.text)
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(VPalette.textHint)
                }
                HStack(spacing: 6) {
                    // Honest rating: shows the real number ONLY when
                    // we have enough ratings to be meaningful (≥3).
                    // Otherwise renders "New rider" — replacing the
                    // previous hardcoded "5.0 rating" lie that was
                    // shown to every freshly-installed user.
                    if store.currentUser.hasDisplayableRating, let rating = store.currentUser.rating {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12)).foregroundColor(VPalette.starGold)
                        Text(String(format: "%.1f (%d)", rating, store.currentUser.ratingCount))
                            .font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.textSec)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12)).foregroundColor(VPalette.primary)
                        Text("New rider")
                            .font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.textSec)
                    }
                    Circle().fill(VPalette.textHint).frame(width: 3, height: 3)
                    // Real ride count from completed payments.
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

    /// Two-tile row for the rider's commute lists. Compact entry
    /// points to Favorites (the routes they starred) and My Requests
    /// (the corridors they asked drivers to add). Counts come from
    /// in-memory caches refreshed by AppStore.
    private var myCommuteSection: some View {
        HStack(spacing: 10) {
            commuteTile(
                icon: "star.fill",
                tint: VPalette.starGold,
                title: "Favourites",
                subtitle: store.favoriteRouteIds.isEmpty
                    ? "None saved"
                    : "\(store.favoriteRouteIds.count) saved"
            ) {
                path.append(.favorites)
            }
            commuteTile(
                icon: "hand.raised.fill",
                tint: VPalette.primary,
                title: "My requests",
                subtitle: {
                    let n = store.routeRequests.filter { $0.status == "OPEN" }.count
                    return n == 0 ? "None waiting" : "\(n) waiting"
                }()
            ) {
                path.append(.routeRequestsList)
            }
        }
        .task {
            await store.refreshFavorites()
            await store.refreshRouteRequests()
        }
    }

    private func commuteTile(icon: String, tint: Color, title: String,
                             subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(VPalette.text)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(VPalette.textHint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.border))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var quickStats: some View {
        // Honest 2-stat row: rides taken + how long this account has
        // been active. Replaces the previous 3-stat row whose "Saved
        // RM X" was fabricated (assumed monthly tier × 22 days for
        // every sub) and whose "On-time %" sourced data from the
        // user's own DRIVER routes (always "—" for riders, who are
        // the screen's primary audience).
        Button { path.append(.tripHistory) } label: {
            HStack(spacing: 0) {
                statCell("\(tripsCount)", "Rides")
                Rectangle().fill(VPalette.border).frame(width: 1, height: 32)
                statCell(memberSinceLabel, "Member since")
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var tripsCount: Int {
        store.payments.filter { $0.status == .paid }.count
    }

    /// "Mar 2026" — short month-year for the join date stat. Returns
    /// "Today" until /auth/me hydrates memberSince so we never show
    /// a misleading blank.
    private var memberSinceLabel: String {
        guard let date = store.currentUser.memberSince else { return "Today" }
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: date)
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
                // Notifications row now opens iOS Settings instead of
                // flipping a placebo @AppStorage that did nothing. The
                // previous toggle let users believe they'd disabled
                // pushes; pushes kept arriving regardless — App Store
                // 4.5/5.4 territory. Apple's recommended pattern for
                // notification opt-out is to bounce to iOS Settings.
                row(icon: "bell.fill", color: VPalette.warning, title: "Notifications", chevron: true) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                divider()
                row(icon: "shield.lefthalf.filled", color: VPalette.accent, title: "Privacy & Security", chevron: true) { path.append(.privacy) }
                divider()
                // Payment methods row no longer lies about a default
                // method when no methods are configured. Subtitle is
                // sourced from the wallet (real method count) so it
                // never invents a "DuitNow · TNG" that isn't set.
                row(icon: "creditcard.fill", color: VPalette.primary, title: "Payment methods", trailingText: paymentMethodsSubtitle) { path.append(.wallet) }
                divider()
                // Renamed to "Activity" to disambiguate from the
                // Notifications row above — both used the word
                // "Notifications" and users couldn't tell them apart.
                row(icon: "bell.badge.fill", color: VPalette.secondary, title: "Activity", chevron: true) { path.append(.notifications) }
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

    /// Honest payment-methods trailing text. "Add one" when nothing
    /// is configured (vs the old hardcoded "DuitNow · TNG" lie); the
    /// real count when methods land. Falls back to neutral text in
    /// the dev shortcut where wallet isn't synced.
    private var paymentMethodsSubtitle: String {
        if !store.useOnline { return "Sign in to manage" }
        // Once /users/me/payment-methods lands this hooks into a real
        // count; for now we never claim methods exist when they don't.
        return "Add one"
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
        let hasRoutes = !store.driverDashboards().isEmpty
        return Button {
            // No routes yet → drop straight into the create-route
            // flow so an approved driver isn't bounced through an
            // empty dashboard first.
            path.append(hasRoutes ? .driverDashboard : .createRoute)
        } label: {
            HStack(spacing: 12) {
                VIconBubble(systemName: hasRoutes ? "car.fill" : "plus.circle.fill",
                            color: VPalette.primary, size: 44, iconSize: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasRoutes ? "Driver mode" : "Publish your first route")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(VPalette.text)
                    Text(hasRoutes ? "Manage your routes & earnings" : "Your KYC is approved — start offering seats")
                        .font(.system(size: 11))
                        .foregroundColor(VPalette.textSec)
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

    /// Show driver mode to anyone who is KYC-approved OR already has
    /// at least one published route. Matches the vehicle-card gate so
    /// the two driver-side cards appear/hide together.
    private var shouldShowDriverModeCard: Bool {
        !store.driverDashboards().isEmpty || store.kycStatus == .approved
    }

    /// Show the vehicle card to anyone who's a driver (≥1 published
    /// route) OR is KYC-approved (very likely to become a driver soon
    /// and benefits from filling this in once, not at create-route
    /// time). Riders without either signal don't see it — they have
    /// no use for vehicle fields and the card would be noise.
    private var shouldShowVehicleCard: Bool {
        !store.driverDashboards().isEmpty || store.kycStatus == .approved
    }

    private var vehicleCard: some View {
        Button {
            showEditVehicle = true
        } label: {
            HStack(spacing: 12) {
                VIconBubble(
                    systemName: hasVehicleSet ? "car.side.fill" : "car.side",
                    color: hasVehicleSet ? VPalette.primary : VPalette.warning,
                    size: 44,
                    iconSize: 18
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your vehicle")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(VPalette.text)
                    Text(vehicleSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(VPalette.textSec)
                        .lineLimit(2)
                }
                Spacer()
                if !hasVehicleSet {
                    VBadge(text: "Set up", color: VPalette.warning, container: VPalette.warning.opacity(0.15))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(VPalette.textHint)
                }
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Tap to edit your plate, colour and model")
    }

    private var hasVehicleSet: Bool {
        let plate = (store.currentUser.plateNumber ?? "").trimmingCharacters(in: .whitespaces)
        return !plate.isEmpty
    }

    private var vehicleSubtitle: String {
        let plate = store.currentUser.plateNumber?.trimmingCharacters(in: .whitespaces) ?? ""
        let color = store.currentUser.carColor?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = store.currentUser.carModel?.trimmingCharacters(in: .whitespaces) ?? ""
        if plate.isEmpty {
            return "Set your plate, colour & model so riders can spot you"
        }
        let descriptor = [color, model].filter { !$0.isEmpty }.joined(separator: " ")
        if descriptor.isEmpty { return plate }
        return "\(plate) · \(descriptor)"
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

    /// Subtitle on the wallet shortcut. Only states facts the wallet
    /// can deliver on: credit + payment receipts. We removed the old
    /// "Add a payment method to start" CTA because that flow doesn't
    /// exist yet — implying it does was a lie. Once the saved-payment
    /// endpoint ships we can re-introduce the prompt.
    private var walletSubtitle: String {
        if store.voygoCreditMyr > 0 {
            return Formatters.ringgit(store.voygoCreditMyr) + " credit · view payments"
        }
        if !store.useOnline {
            return "Wallet syncs after sign-in"
        }
        return store.payments.isEmpty ? "No payments yet" : "View payments & receipts"
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

// MARK: - Privacy & Security
//
// Replaces the previous static "security tips" brochure with a real
// controls screen. Required for App Store guideline 5.1.1(v) (account
// deletion must be in-app) and Malaysia PDPA Section 7 (right of
// access / data export). The four sections map directly to the four
// `/users/me/...` endpoints in server.js:
//
//   1. Notifications + phone visibility + marketing → /preferences
//   2. Blocked users                                → /blocks
//   3. Download my data                              → /data-export
//   4. Delete account                                → /delete

struct PrivacySecurityView: View {
    var onBack: () -> Void
    @Environment(AppStore.self) private var store

    @State private var prefs: UserPreferencesDTO? = nil
    @State private var blocks: [BlockedUserDTO] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var infoMessage: String? = nil

    @State private var showDeleteConfirm: Bool = false
    @State private var showDeleteFinal: Bool = false
    @State private var isDeleting: Bool = false
    @State private var deleteResult: DeleteAccountResponse? = nil
    @State private var isRequestingExport: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Privacy & Security", onBack: onBack)
                ScrollView {
                    VStack(spacing: 18) {
                        if isLoading && prefs == nil {
                            ProgressView().padding(.top, 60)
                        } else {
                            preferencesCard
                            blocksCard
                            dataCard
                            deleteCard
                            if let infoMessage {
                                Text(infoMessage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(VPalette.success)
                                    .padding(.horizontal, 16)
                            }
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(VPalette.danger)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, VTabBarLayout.clearance)
                }
            }
        }
        .task { await load() }
        .alert("Delete this account?", isPresented: $showDeleteConfirm) {
            Button("Continue", role: .destructive) { showDeleteFinal = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your account, routes, and subscriptions will be paused immediately. You have 30 days to sign back in to cancel. After that, your data is permanently anonymised.")
        }
        .alert("Really delete?", isPresented: $showDeleteFinal) {
            Button("Yes, delete", role: .destructive) { Task { await deleteAccount() } }
            Button("Keep my account", role: .cancel) { }
        } message: {
            Text("This is your last chance to back out. We'll email a confirmation.")
        }
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VKicker(text: "Preferences").padding(.leading, 4).padding(.bottom, 8)
            VStack(spacing: 0) {
                preferenceToggle(
                    icon: "bell.fill", color: VPalette.warning,
                    title: "Push notifications",
                    subtitle: "Receive ride reminders, chat messages, payment receipts",
                    isOn: Binding(
                        get: { prefs?.pushEnabled ?? true },
                        set: { update(.pushEnabled, $0) }
                    )
                )
                divider()
                preferenceToggle(
                    icon: "phone.fill", color: VPalette.primary,
                    title: "Share phone with subscribers",
                    subtitle: "When OFF, riders see a masked number until pickup",
                    isOn: Binding(
                        get: { prefs?.phoneVisibleToSubscribers ?? true },
                        set: { update(.phoneVisibleToSubscribers, $0) }
                    )
                )
                divider()
                preferenceToggle(
                    icon: "faceid", color: VPalette.accent,
                    title: "Lock wallet with Face ID",
                    subtitle: "Require biometric to view payments + receipts",
                    isOn: Binding(
                        get: { prefs?.biometricLock ?? false },
                        set: { update(.biometricLock, $0) }
                    )
                )
                divider()
                preferenceToggle(
                    icon: "envelope.fill", color: VPalette.secondary,
                    title: "Promotional emails",
                    subtitle: "Optional. Defaults to OFF (PDPA opt-in)",
                    isOn: Binding(
                        get: { prefs?.marketingEmails ?? false },
                        set: { update(.marketingEmails, $0) }
                    )
                )
            }
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func preferenceToggle(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VIconBubble(systemName: icon, color: color, size: 32, iconSize: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                Text(subtitle).font(.system(size: 11)).foregroundColor(VPalette.textSec)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(VPalette.primary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: Blocks

    private var blocksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VKicker(text: "Blocked users")
                Spacer()
                Text("\(blocks.count)/200")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(VPalette.textHint)
            }
            .padding(.leading, 4)
            .padding(.bottom, 8)
            VStack(spacing: 0) {
                if blocks.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 22))
                            .foregroundColor(VPalette.textHint)
                        Text("No blocked users")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(VPalette.textSec)
                        Text("Block a driver from any route detail to stop being matched with them.")
                            .font(.caption2)
                            .foregroundColor(VPalette.textHint)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, b in
                        if idx > 0 { divider() }
                        HStack(spacing: 12) {
                            VAvatar(initial: String(b.displayName.prefix(1)), size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.displayName).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                                if let reason = b.reason, !reason.isEmpty {
                                    Text(reason).font(.caption2).foregroundColor(VPalette.textSec).lineLimit(1)
                                }
                            }
                            Spacer()
                            Button {
                                Task { await unblock(b.userId) }
                            } label: {
                                Text("Unblock")
                                    .font(.caption.weight(.heavy))
                                    .foregroundColor(VPalette.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }
            }
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Data export

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VKicker(text: "Your data").padding(.leading, 4).padding(.bottom, 8)
            Button {
                Task { await requestDataExport() }
            } label: {
                HStack(spacing: 12) {
                    VIconBubble(systemName: "square.and.arrow.down.fill", color: VPalette.primary, size: 32, iconSize: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download my data")
                            .font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                        Text("We'll email a copy of your rides, payments and profile within 7 days (PDPA s.7)")
                            .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if isRequestingExport {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(VPalette.textHint)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isRequestingExport)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Delete account

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VKicker(text: "Danger zone").padding(.leading, 4).padding(.bottom, 8)
            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 12) {
                    VIconBubble(systemName: "trash.fill", color: VPalette.danger, size: 32, iconSize: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete account")
                            .font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.danger)
                        Text("Permanently removes your account after 30 days. Required by App Store + PDPA.")
                            .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if isDeleting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(VPalette.textHint)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .background(VPalette.dangerContainer.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.danger.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func divider() -> some View {
        Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 56)
    }

    // MARK: - Network

    private enum PrefField {
        case pushEnabled, phoneVisibleToSubscribers, biometricLock, marketingEmails
    }

    private func load() async {
        isLoading = true
        async let prefsResult = (try? await VoygoAPIClient.getPreferences())
        async let blocksResult = (try? await VoygoAPIClient.listBlocks()) ?? []
        prefs = await prefsResult
        blocks = await blocksResult
        isLoading = false
        if prefs == nil { errorMessage = "Couldn't load preferences." }
    }

    private func update(_ field: PrefField, _ newValue: Bool) {
        // Optimistic local flip + server PUT. On failure, revert.
        guard var current = prefs else { return }
        let previous = current
        switch field {
        case .pushEnabled:                current.pushEnabled = newValue
        case .phoneVisibleToSubscribers:  current.phoneVisibleToSubscribers = newValue
        case .biometricLock:              current.biometricLock = newValue
        case .marketingEmails:            current.marketingEmails = newValue
        }
        prefs = current
        var patch = UpdatePreferencesRequest.empty
        switch field {
        case .pushEnabled:                patch.pushEnabled = newValue
        case .phoneVisibleToSubscribers:  patch.phoneVisibleToSubscribers = newValue
        case .biometricLock:              patch.biometricLock = newValue
        case .marketingEmails:            patch.marketingEmails = newValue
        }
        Task {
            do {
                try await VoygoAPIClient.updatePreferences(patch)
            } catch {
                await MainActor.run {
                    prefs = previous
                    errorMessage = "Couldn't save preference. Try again."
                }
            }
        }
    }

    private func unblock(_ userId: String) async {
        do {
            try await VoygoAPIClient.removeBlock(userId: userId)
            blocks.removeAll { $0.userId == userId }
            infoMessage = "Unblocked."
        } catch {
            errorMessage = "Couldn't unblock. Try again."
        }
    }

    private func requestDataExport() async {
        guard !isRequestingExport else { return }
        isRequestingExport = true
        defer { isRequestingExport = false }
        do {
            let r = try await VoygoAPIClient.requestDataExport()
            infoMessage = r.message
        } catch {
            errorMessage = "Couldn't queue the export. Try again."
        }
    }

    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await VoygoAPIClient.deleteAccount()
            // Server has soft-deleted the account; clear local session
            // so subsequent requests 401 and the user is bounced back
            // to the auth screen. They can re-sign-in within 30 days
            // to cancel — the next /auth/me will return 410 Gone in
            // that window, which AppStore clears via APIError flow.
            store.logout()
        } catch {
            errorMessage = "Couldn't delete the account. Try again or email support."
        }
    }
}

// Pre-populated patch helper. The struct already has a memberwise
// init that takes all-nil; we just expose a named static accessor
// because writing `UpdatePreferencesRequest(pushEnabled: nil, ...)`
// at every call site is noisy.
private extension UpdatePreferencesRequest {
    static var empty: UpdatePreferencesRequest {
        UpdatePreferencesRequest(pushEnabled: nil, phoneVisibleToSubscribers: nil, biometricLock: nil, marketingEmails: nil)
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
    var onEndTrip: ((_ rideInstanceId: String?, _ routeId: String?, _ driverId: String?, _ driverInitial: String, _ driverName: String, _ summary: String) -> Void)? = nil
    @Environment(AppStore.self) private var store

    @State private var pickupConfirmed = false
    @State private var dropoffConfirmed = false
    @State private var sosPressed = false
    @State private var showSOSAlert = false
    @State private var showShareSheet = false
    @State private var showSOSMessageComposer = false
    /// Live ETA in minutes. Computed from the live driver location +
    /// drop-point distance when a real GPS sample is in. Falls back to
    /// the timer-driven demo countdown until the first sample arrives.
    @State private var etaMinutes: Int = 12
    @State private var etaTask: Task<Void, Never>? = nil
    /// SSE subscription for the driver's live breadcrumbs. Started in
    /// `.onAppear`, cancelled in `.onDisappear` so we don't keep the
    /// connection open after the rider navigates away.
    @State private var liveLocationTask: Task<Void, Never>? = nil
    /// Driver-side foreground push. When the user is the driver and
    /// flips this on, `CLLocationManager` delivers location updates
    /// every ~10s and we POST each one to /rides/:id/location.
    @State private var isSharingLocation: Bool = false
    @State private var driverLocationManager: CLLocationManager? = nil
    @State private var driverLocationDelegate: DriverLocationDelegate? = nil

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

    private var canCallDriver: Bool {
        // The phone is only dialable when the backend revealed the
        // unmasked E.164 — masked stubs like "+60 •• ••• ••23" would
        // sanitize down to "+60••••23" and either fail to open the
        // dialer or dial garbage. Match the server's reveal rule:
        // ACTIVE subscriber or route driver.
        guard let r = route else { return false }
        guard let phone = r.driverPhone, !phone.isEmpty else { return false }
        return r.driverPhoneRevealed
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

                    // GPS dot — animates along the abstract diagram
                    // based on real driver progress when an SSE
                    // sample is in. We compute progress as a 0…1
                    // value from the driver's lat/lng vs. the
                    // route's pickup/drop bounds; idle position is
                    // the previous "47% × 55%" demo midpoint.
                    GeometryReader { geo in
                        let progress = liveProgressFraction()
                        ZStack {
                            Circle().fill(VPalette.primary).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .shadow(color: VPalette.primary.opacity(0.5), radius: 12, y: 4)
                            Image(systemName: "car.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .position(
                            x: geo.size.width  * (0.10 + 0.80 * progress),
                            y: geo.size.height * (0.85 - 0.70 * progress)
                        )
                        .animation(.easeOut(duration: 0.6), value: progress)
                        // "Live" pill when we have a fresh SSE sample.
                        if let live = store.liveLocation(for: tripId),
                           Date().timeIntervalSince(live.recordedAt) < 60 {
                            HStack(spacing: 4) {
                                Circle().fill(VPalette.success).frame(width: 6, height: 6)
                                Text("Live")
                                    .font(.system(size: 9, weight: .black))
                                    .tracking(0.6)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .position(
                                x: geo.size.width  * (0.10 + 0.80 * progress),
                                y: geo.size.height * (0.85 - 0.70 * progress) - 26
                            )
                        }
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
        .onAppear {
            startEtaCountdown()
            // Open the SSE breadcrumb stream as soon as the rider
            // mounts the screen. The store caches the latest sample
            // so the GPS dot has a starting point even if the driver
            // hasn't pushed in the last 30 seconds.
            liveLocationTask?.cancel()
            liveLocationTask = store.streamRideLocation(tripId)
        }
        .onDisappear {
            etaTask?.cancel(); etaTask = nil
            liveLocationTask?.cancel(); liveLocationTask = nil
            // Stop driver-side push if it was running.
            if isSharingLocation { stopDriverLocationPush() }
        }
        .alert("Send SOS?", isPresented: $showSOSAlert) {
            Button("Compose SMS", role: .destructive) {
                sosPressed = true
                // Two channels in parallel:
                //   1. System SMS composer pre-filled — instant for
                //      the rider's own contacts.
                //   2. POST /safety/sos — server records the alert
                //      and (when env-configured) pages on-call ops.
                // Either path delivering value is enough; we don't
                // gate the composer on the network call.
                showSOSMessageComposer = true
                Task { await postSafetyAlert() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Opens Messages with your live trip details so you can send to your emergency contacts. Voygo Safety is also notified.")
        }
        .sheet(isPresented: $showShareSheet) {
            // Share-my-ride: ActivityViewController with a deep link.
            // Until the backend exposes a public `/share/{token}`
            // page, the URL points to the canonical app scheme so a
            // recipient with Voygo installed lands on this trip.
            ActivityShareSheet(items: [shareMessage, shareURL])
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSOSMessageComposer) {
            if MessageComposerView.canSendText {
                MessageComposerView(body: sosMessageBody)
            } else {
                // Fallback: device can't send SMS (e.g. iPad without
                // a paired iPhone). Tell the user honestly instead
                // of presenting an empty sheet.
                VStack(spacing: 16) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 40))
                        .foregroundColor(VPalette.textHint)
                    Text("This device can't send SMS")
                        .font(.system(size: 15, weight: .heavy))
                    Text("Use another device with cellular service to send the SOS message.")
                        .font(.system(size: 13))
                        .foregroundColor(VPalette.textSec)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    VPrimaryButton("OK") { showSOSMessageComposer = false }
                        .padding(.horizontal, 32)
                }
                .padding(32)
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Sharing & SOS message bodies

    private var shareMessage: String {
        "I'm on a Voygo ride: \(routeSummary). Driver: \(driverDisplayName). ETA \(etaMinutes) min."
    }

    private var shareURL: URL {
        URL(string: "voygo://rides/\(tripId)") ?? URL.staticURL("https://voygo.app")
    }

    private var sosMessageBody: String {
        """
        🚨 I need help — I'm on a Voygo carpool ride.

        Driver: \(driverDisplayName)
        Route: \(routeSummary)
        Pickup: \(pickupLabel)
        Drop: \(dropoffLabel)
        ETA: \(etaMinutes) min

        Track me here: \(shareURL.absoluteString)

        Sent automatically from Voygo SOS.
        """
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
                    iconButton("flag.fill",
                               color: VPalette.danger,
                               bg: VPalette.dangerContainer,
                               action: { showSOSAlert = true })
                    iconButton("square.and.arrow.up",
                               color: VPalette.primary,
                               bg: VPalette.primaryContainer,
                               action: { showShareSheet = true })
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
                    // Open `tel://` only when the server revealed the
                    // unmasked phone (caller is the route driver or
                    // an ACTIVE subscriber). A masked stub would have
                    // canCallDriver=false anyway, but check again here
                    // as defense-in-depth before we sanitize + dial.
                    if canCallDriver,
                       let phone = route?.driverPhone,
                       let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(canCallDriver ? VPalette.success : VPalette.textHint)
                        .clipShape(Circle())
                        .shadow(color: canCallDriver ? VPalette.success.opacity(0.5) : .clear, radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(canCallDriver ? "Call driver" : "Driver phone unavailable")
                .disabled(!canCallDriver)
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

            // Driver-only: share live location for the duration of the
            // trip. Foreground only — the toggle copy is honest about
            // the trade-off so a driver doesn't expect background
            // updates while their phone is locked.
            if isDriver {
                Button {
                    if isSharingLocation {
                        stopDriverLocationPush()
                        isSharingLocation = false
                    } else {
                        startDriverLocationPush()
                        isSharingLocation = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isSharingLocation ? "location.fill" : "location")
                            .font(.system(size: 14, weight: .heavy))
                        Text(isSharingLocation ? "Sharing live · keep app open" : "Share live location")
                            .font(.system(size: 13, weight: .black))
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundColor(isSharingLocation ? .white : VPalette.primary)
                    .background(isSharingLocation ? VPalette.primary : VPalette.primaryContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }

            // End Trip is the primary path for a rider — visible on every
            // live trip so they can flow into rating without hunting for
            // the action.
            if let onEndTrip {
                VPrimaryButton("End trip → rate") {
                    onEndTrip(ride?.id, route?.id, route?.driverId, driverInitial, driverDisplayName, routeSummary)
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

    private func iconButton(_ system: String, color: Color, bg: Color, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
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
        if let km = liveDistanceKm() {
            return "Arriving \(Formatters.time(arrival)) · \(String(format: "%.1f", km)) km"
        }
        return "Arriving \(Formatters.time(arrival))"
    }

    /// Demo countdown — kept as a fallback so the ETA stays visible
    /// even if no SSE sample arrives. Once a sample lands,
    /// `recomputeEtaFromLive(_:)` overrides this.
    private func startEtaCountdown() {
        etaTask?.cancel()
        etaTask = Task {
            while !Task.isCancelled && etaMinutes > 0 {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    // Only let the timer drift the ETA when there's
                    // no recent live sample — the live consumer is
                    // the source of truth when present.
                    if let live = store.liveLocation(for: tripId),
                       Date().timeIntervalSince(live.recordedAt) < 90 {
                        return
                    }
                    if etaMinutes > 0 { etaMinutes -= 1 }
                }
            }
        }
    }

    // MARK: - Live progress + ETA helpers

    /// 0…1 progress along the route based on the driver's current
    /// position. `0` = at the route's first pickup point; `1` = at
    /// the route's last drop point. Without geo data we return 0.5
    /// so the dot sits at the diagram's midpoint (matching the
    /// previous demo behaviour).
    private func liveProgressFraction() -> CGFloat {
        guard let live = store.liveLocation(for: tripId),
              let r = route,
              let pickup = r.pickupPoints.first,
              let drop   = r.dropPoints.last else {
            return 0.5
        }
        let total = haversineMeters(
            lat1: pickup.lat, lng1: pickup.lng,
            lat2: drop.lat,   lng2: drop.lng
        )
        guard total > 0 else { return 0.5 }
        let travelled = haversineMeters(
            lat1: pickup.lat, lng1: pickup.lng,
            lat2: live.lat,   lng2: live.lng
        )
        return CGFloat(min(1.0, max(0.0, travelled / total)))
    }

    /// Straight-line distance from the live position to the route's
    /// drop point. Used as the ETA distance for the subtitle when a
    /// sample is in. Returns nil when we have no live data.
    private func liveDistanceKm() -> Double? {
        guard let live = store.liveLocation(for: tripId),
              let drop = route?.dropPoints.last else { return nil }
        let m = haversineMeters(
            lat1: live.lat, lng1: live.lng,
            lat2: drop.lat, lng2: drop.lng
        )
        return m / 1000.0
    }

    private func haversineMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat/2)*sin(dLat/2)
              + cos(lat1 * .pi/180)*cos(lat2 * .pi/180)
              * sin(dLng/2)*sin(dLng/2)
        return R * 2 * atan2(sqrt(a), sqrt(1-a))
    }

    // MARK: - Safety alert post

    /// Best-effort POST to /safety/sos. Failure isn't surfaced to the
    /// user — the SMS composer is the rider's primary lifeline; the
    /// backend persistence is the ops-side double-check.
    private func postSafetyAlert() async {
        let live = store.liveLocation(for: tripId)
        Telemetry.track(TelemetryEvents.liveTripSosTapped, [
            "ride_id": .string(tripId),
            "has_live_location": .bool(live != nil)
        ])
        do {
            _ = try await VoygoAPIClient.reportSafetyAlert(
                rideId: tripId,
                routeId: route?.id,
                lat: live?.lat,
                lng: live?.lng,
                message: sosMessageBody
            )
        } catch {
            // non-fatal
        }
    }

    // MARK: - Driver-side foreground push
    //
    // Only available when this LiveTripView was opened in driver mode
    // (`isDriver: true`). Foreground-only for now — background
    // location requires `Always` permission + a Live Activity / Lock
    // Screen presence to be honest. Adding a "Share location" pill
    // surfaces the trade-off explicitly to the driver.

    fileprivate func startDriverLocationPush() {
        guard isDriver else { return }
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10  // metres; throttles unchanged samples
        let delegate = DriverLocationDelegate(rideId: tripId, store: store)
        manager.delegate = delegate
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        driverLocationManager = manager
        driverLocationDelegate = delegate
    }

    fileprivate func stopDriverLocationPush() {
        driverLocationManager?.stopUpdatingLocation()
        driverLocationManager = nil
        driverLocationDelegate = nil
    }
}

/// CLLocationManager delegate that POSTs each location update to the
/// `/rides/:id/location` endpoint. Lives outside `LiveTripView` so the
/// view stays a struct (delegates need a class).
private final class DriverLocationDelegate: NSObject, CLLocationManagerDelegate {
    let rideId: String
    weak var store: AppStore?

    init(rideId: String, store: AppStore) {
        self.rideId = rideId
        self.store = store
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                      didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude
        let heading = loc.course >= 0 ? loc.course : nil
        let speedMps: Double? = loc.speed >= 0 ? loc.speed : nil
        let id = rideId
        let storeRef = store
        Task { @MainActor in
            await storeRef?.postRideLocation(
                rideId: id, lat: lat, lng: lng,
                heading: heading, speedMps: speedMps
            )
        }
    }
}


private struct _LiveTripDeprecatedHelpers: View {
    var body: some View {
        EmptyView()
    }
}

// MARK: - Edit display name sheet
//
// Two-tap edit-name flow surfaced from the Profile identity row.
// Replaces the auto-generated "User 6789" fallback (derived from
// the last 4 phone digits) with the rider's real name. The sheet's
// `onSave` returns a Result so the caller can render an inline
// error and keep the sheet open until the server accepts.

struct EditDisplayNameSheet: View {
    let initialName: String
    let onCancel: () -> Void
    let onSave:   (String) async -> Result<Void, AppError>

    @State private var name: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isSaving && !trimmed.isEmpty && trimmed.count <= 60 && trimmed != initialName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your name")
                    .font(.system(size: 18, weight: .black))
                    .tracking(-0.3)
                    .foregroundColor(VPalette.text)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(VPalette.textSec)
                        .frame(width: 32, height: 32)
                        .background(VPalette.surfaceHigh)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }

            Text("This is how drivers and riders see you on receipts, chat threads and ride confirmations.")
                .font(.system(size: 12))
                .foregroundColor(VPalette.textSec)

            TextField("e.g. Vishnu Kumar", text: $name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(VPalette.text)
                .tint(VPalette.primary)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(VPalette.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { Task { await save() } }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(VPalette.danger)
            }

            VPrimaryButton("Save", isLoading: isSaving, isEnabled: canSave) {
                Task { await save() }
            }
        }
        .padding(20)
        .onAppear {
            // Pre-fill the auto-generated fallback so the user doesn't
            // have to delete it first. Empty string is fine — the
            // textfield placeholder already gives a visual hint.
            name = initialName.hasPrefix("User ") ? "" : initialName
            nameFocused = true
        }
    }

    private func save() async {
        guard canSave else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        errorMessage = nil
        let result = await onSave(trimmed)
        isSaving = false
        if case .failure(let err) = result {
            errorMessage = err.localizedDescription
        }
    }
}

#Preview("EditDisplayNameSheet") {
    EditDisplayNameSheet(
        initialName: "User 1234",
        onCancel: {},
        onSave: { _ in .success(()) }
    )
}

// MARK: - Edit Vehicle Sheet
//
// Vehicle identity (plate + colour + model) is set ONCE on the driver
// profile and the server reads it back per-route. Surfacing it here
// (not on Create Route) closes the "list plate A, arrive in car B"
// safety hole — a malicious driver can't list a fake plate on a single
// route, because every route they publish reads from this same record.

struct EditVehicleSheet: View {
    let initialPlate: String
    let initialColor: String
    let initialModel: String
    let onCancel: () -> Void
    let onSave:   (String, String, String) async -> Result<Void, AppError>

    @State private var plate: String = ""
    @State private var color: String = ""
    @State private var model: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var focused: Field?

    private enum Field: Hashable { case plate, color, model }

    /// Save when at least one field changed AND the plate is set
    /// (the only required field — a rider with just colour + model is
    /// not actionable). Plate format validation is intentionally
    /// loose — Malaysian plates vary by state/region.
    private var canSave: Bool {
        let p = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = color.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if isSaving || p.isEmpty { return false }
        return p != initialPlate || c != initialColor || m != initialModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your vehicle")
                    .font(.system(size: 18, weight: .black))
                    .tracking(-0.3)
                    .foregroundColor(VPalette.text)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(VPalette.textSec)
                        .frame(width: 32, height: 32)
                        .background(VPalette.surfaceHigh)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }

            Text("Riders use your plate, colour and model to spot the right car at the pickup point. This is set once and applies to every route you publish.")
                .font(.system(size: 12))
                .foregroundColor(VPalette.textSec)

            field(label: "Plate number",
                  placeholder: "PEN 1234",
                  text: $plate,
                  field: .plate,
                  autocaps: .characters)

            HStack(spacing: 10) {
                field(label: "Colour",
                      placeholder: "White",
                      text: $color,
                      field: .color,
                      autocaps: .words)
                field(label: "Model",
                      placeholder: "Myvi",
                      text: $model,
                      field: .model,
                      autocaps: .words)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(VPalette.danger)
            }

            VPrimaryButton("Save", isLoading: isSaving, isEnabled: canSave) {
                Task { await save() }
            }
        }
        .padding(20)
        .onAppear {
            plate = initialPlate
            color = initialColor
            model = initialModel
            focused = .plate
        }
    }

    @ViewBuilder
    private func field(label: String, placeholder: String, text: Binding<String>,
                       field: Field, autocaps: TextInputAutocapitalization) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.heavy))
                .foregroundColor(VPalette.textSec)
            TextField(placeholder, text: text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(VPalette.text)
                .tint(VPalette.primary)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(VPalette.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .textInputAutocapitalization(autocaps)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focused, equals: field)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        let result = await onSave(
            plate.trimmingCharacters(in: .whitespacesAndNewlines),
            color.trimmingCharacters(in: .whitespacesAndNewlines),
            model.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        isSaving = false
        if case .failure(let err) = result {
            errorMessage = err.localizedDescription
        }
    }
}

#Preview("EditVehicleSheet") {
    EditVehicleSheet(
        initialPlate: "",
        initialColor: "",
        initialModel: "",
        onCancel: {},
        onSave: { _, _, _ in .success(()) }
    )
}
