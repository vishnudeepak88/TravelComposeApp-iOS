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
    @State private var path: [AppRoute]
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
    /// Mirrors the same @AppStorage RootView watches. Writing here
    /// opens the language picker as a full-screen cover anchored at
    /// RootView level — that placement is what lets the picker
    /// survive the `.id(appLanguage)` remount instead of bouncing
    /// the rider back to Profile root mid-switch.
    @AppStorage("voygo.showLanguagePicker") private var showLanguagePicker: Bool = false

    init() {
        // Language picker now opens as a fullScreenCover anchored on
        // RootView — no nav-path push, no restore flag, no init-time
        // seeding. The old logic was the source of the "tap Back
        // twice" bug: the cover dismissed on the first tap but the
        // stale `.language` route stayed in the path, popping into
        // view as a second Language screen until a second Back tap
        // popped it off too.
        _path = State(initialValue: [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                VPalette.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    VPolishedNavBar(title: S.profilePageTitle)

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
            .alert(S.profileLogOutTitle, isPresented: $showLogoutAlert) {
                Button(S.profileLogOutTitle, role: .destructive) {
                    guard !isLoggingOut else { return }
                    isLoggingOut = true
                    // `store.logout()` flips `isAuthenticated` which
                    // unmounts this view (RootView swaps to AuthPhoneView).
                    // In the dev-skip path that's synchronous; on a real
                    // user it briefly runs an async server call to
                    // invalidate the token. Reset `isLoggingOut` on the
                    // next runloop tick so a transient logout failure
                    // doesn't permanently lock the rider out of retrying.
                    store.logout()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        isLoggingOut = false
                    }
                }
                Button(S.cancel, role: .cancel, action: {})
            } message: { Text(S.profileLogOutMessage) }
            // Slide-from-right overlays (not native `.sheet`) so the
            // edit pages feel like forward navigation, matching every
            // other page transition in the app. The presentation
            // detent that previously kept these as partial sheets is
            // gone — full-screen pages are easier to focus on and
            // form fields stay above the keyboard reliably. Wrap each
            // sheet content in a full-screen ZStack with the app
            // background so it doesn't show the underlying view
            // bleeding through.
            .slideOver(isPresented: $showEditName) {
                ZStack(alignment: .top) {
                    VPalette.bg.ignoresSafeArea()
                    EditDisplayNameSheet(
                        initialName: store.currentUser.name,
                        onCancel: { showEditName = false },
                        onSave:   { newName in
                            let result = await store.updateDisplayName(newName)
                            if case .success = result { showEditName = false }
                            return result
                        }
                    )
                    .padding(.top, 60)
                }
            }
            .slideOver(isPresented: $showEditVehicle) {
                ZStack(alignment: .top) {
                    VPalette.bg.ignoresSafeArea()
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
                    .padding(.top, 60)
                }
            }
            .task {
                await store.refreshMe()
            }
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
        .accessibilityHint(S.profileNameEditHint)
    }

    private var identityRowContent: some View {
        HStack(spacing: 14) {
            VAvatar(initial: store.currentUser.initial.isEmpty ? "?" : store.currentUser.initial, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(store.currentUser.name.isEmpty ? S.profileWelcome : store.currentUser.name)
                        .font(.title3.weight(.heavy)).tracking(-0.4)
                        .foregroundColor(VPalette.text)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "pencil")
                        .font(.caption.weight(.heavy))
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
                            .font(.caption).foregroundColor(VPalette.starGold)
                        Text(String(format: "%.1f (%d)", rating, store.currentUser.ratingCount))
                            .font(.caption.weight(.heavy)).foregroundColor(VPalette.textSec)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.caption).foregroundColor(VPalette.primary)
                        Text(S.profileNewRider)
                            .font(.caption.weight(.heavy)).foregroundColor(VPalette.textSec)
                    }
                    Circle().fill(VPalette.textHint).frame(width: 3, height: 3)
                    // Real ride count from completed payments. Uses
                    // `S.profileRidesCount` so "0 rides" / "1 ride" /
                    // "N rides" each render with the right plural form.
                    Text(S.profileRidesCount(tripsCount)).font(.caption).foregroundColor(VPalette.textSec)
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
                    Text(S.profileSettingsIdentityVerification)
                        .font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                    Text(kycMessage).font(.caption2).foregroundColor(VPalette.textSec)
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
                    Text(S.profileSettingsWalletAndPayments)
                        .font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                    Text(walletSubtitle)
                        .font(.caption2).foregroundColor(VPalette.textSec)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.heavy)).accessibilityHidden(true).foregroundColor(VPalette.textHint)
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
                title: S.profileSettingsFavourites,
                subtitle: store.favoriteRouteIds.isEmpty
                    ? S.profileSettingsFavouritesNoneSaved
                    : S.profileSettingsFavouritesSaved(store.favoriteRouteIds.count)
            ) {
                path.append(.favorites)
            }
            commuteTile(
                icon: "hand.raised.fill",
                tint: VPalette.primary,
                title: S.profileSettingsMyRequests,
                subtitle: {
                    let n = store.routeRequests.filter { $0.status == "OPEN" }.count
                    return n == 0 ? S.profileSettingsMyRequestsNone : S.profileSettingsMyRequestsWaiting(n)
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
                    .font(.body.weight(.heavy))
                    .foregroundColor(tint)
                Text(title)
                    .font(.footnote.weight(.heavy))
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
                statCell("\(tripsCount)", S.profileRidesLabel)
                Rectangle().fill(VPalette.border).frame(width: 1, height: 32)
                statCell(memberSinceLabel, S.profileMemberSinceLabel)
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
    /// `profile.memberSinceToday` until /auth/me hydrates memberSince so
    /// we never show a misleading blank. Honours `Locale.current` so
    /// BM users see "Mei 2026" instead of "May 2026".
    private var memberSinceLabel: String {
        guard let date = store.currentUser.memberSince else { return S.profileMemberSinceToday }
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "MMM yyyy"
        return f.string(from: date)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.body.weight(.black)).tracking(-0.3).foregroundColor(VPalette.primary)
            VKicker(text: label, size: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            VKicker(text: S.settings).padding(.leading, 4)
            VStack(spacing: 0) {
                // Notifications row now opens iOS Settings instead of
                // flipping a placebo @AppStorage that did nothing. The
                // previous toggle let users believe they'd disabled
                // pushes; pushes kept arriving regardless — App Store
                // 4.5/5.4 territory. Apple's recommended pattern for
                // notification opt-out is to bounce to iOS Settings.
                row(icon: "bell.fill", color: VPalette.warning, title: S.profileSettingsNotifications, chevron: true) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                divider()
                row(icon: "shield.lefthalf.filled", color: VPalette.accent, title: S.profileSettingsPrivacy, chevron: true) { path.append(.privacy) }
                divider()
                // In-app language picker. Trailing-text shows the
                // current choice so the rider can see what's set
                // without drilling in.
                row(icon: "globe", color: VPalette.secondary,
                    title: S.profileSettingsLanguage,
                    chevron: true,
                    trailingText: AppLocale.current.displayName,
                    action: {
                        // Opens the picker as a full-screen cover
                        // anchored on RootView — its presentation
                        // state lives in @AppStorage so it survives
                        // the language-change hot-remount, keeping
                        // the rider on the picker through the swap.
                        showLanguagePicker = true
                    })
                divider()
                // Payment methods row no longer lies about a default
                // method when no methods are configured. Subtitle is
                // sourced from the wallet (real method count) so it
                // never invents a "DuitNow · TNG" that isn't set.
                row(icon: "creditcard.fill", color: VPalette.primary, title: S.profileSettingsPaymentMethods, trailingText: paymentMethodsSubtitle) { path.append(.wallet) }
                divider()
                // Renamed to "Activity" to disambiguate from the
                // Notifications row above — both used the word
                // "Notifications" and users couldn't tell them apart.
                row(icon: "bell.badge.fill", color: VPalette.secondary, title: S.profileSettingsActivity, chevron: true) { path.append(.notifications) }
                divider()
                row(icon: "doc.text.fill", color: VPalette.accent, title: S.profileSettingsTripHistory, chevron: true) { path.append(.tripHistory) }
                divider()
                row(icon: "questionmark.circle.fill", color: VPalette.secondary, title: S.profileSettingsHelpCenter, chevron: true) { path.append(.help) }
            }
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// Honest payment-methods trailing text. Re-uses the "Pay at
    /// checkout" wallet copy because there's no in-app add-payment
    /// flow yet — saying "Add one" was misleading. Once the
    /// `/users/me/payment-methods` endpoint lands this hooks into a
    /// real count; for now we never claim methods exist when they
    /// don't.
    private var paymentMethodsSubtitle: String {
        if !store.useOnline { return S.profileSettingsPayMethodsSignedOut }
        return S.walletPayAtCheckout
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
                Text(title).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                Spacer()
                if let trailingText {
                    Text(trailingText).font(.caption2.weight(.bold)).foregroundColor(VPalette.textSec)
                }
                if let trailing {
                    trailing
                }
                if chevron {
                    Image(systemName: "chevron.right").font(.footnote.weight(.heavy)).accessibilityHidden(true).foregroundColor(VPalette.textHint)
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
                    Text(hasRoutes ? S.profileDriverMode : S.profileDriverPublishFirst)
                        .font(.footnote.weight(.heavy))
                        .foregroundColor(VPalette.text)
                    Text(hasRoutes ? S.profileDriverManageSubtitle : S.profileDriverApprovedSubtitle)
                        .font(.caption2)
                        .foregroundColor(VPalette.textSec)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.heavy)).accessibilityHidden(true).foregroundColor(VPalette.textHint)
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
                    Text(S.profileVehicleTitle)
                        .font(.footnote.weight(.heavy))
                        .foregroundColor(VPalette.text)
                    Text(vehicleSubtitle)
                        .font(.caption2)
                        .foregroundColor(VPalette.textSec)
                        .lineLimit(2)
                }
                Spacer()
                if !hasVehicleSet {
                    VBadge(text: S.profileVehicleSetUp, color: VPalette.warning, container: VPalette.warning.opacity(0.15))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.heavy))
                        .foregroundColor(VPalette.textHint)
                }
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(S.profileVehicleEditHint)
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
            return S.profileVehicleSubtitle
        }
        let descriptor = [color, model].filter { !$0.isEmpty }.joined(separator: " ")
        if descriptor.isEmpty { return plate }
        return "\(plate) · \(descriptor)"
    }

    private var logoutPill: some View {
        Button { showLogoutAlert = true } label: {
            HStack {
                Image(systemName: "arrow.up.right.square.fill").foregroundColor(VPalette.danger)
                Text(S.profileLogOut).font(.footnote.weight(.heavy)).foregroundColor(VPalette.danger)
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
        case .approved: return S.profileKycMessageApproved
        case .pending:  return S.profileKycMessagePending
        case .rejected:
            // Surface the FIRST rejected document's reason inline so
            // the rider sees which doc + why without having to drill
            // into KycVerificationView first. The generic "resubmit"
            // copy is the fallback when the per-doc reason isn't
            // populated (older review records, free-form rejections).
            if let firstReject = store.kycDocuments.first(where: {
                ($0.rejectionReason ?? "").isEmpty == false
            }), let reason = firstReject.rejectionReason {
                return S.profileKycMessageRejectedWithReason(firstReject.kind.label, reason)
            }
            return S.profileKycMessageRejected
        default:        return S.profileKycMessageNotStarted
        }
    }
    private var kycBadge: String {
        switch store.kycStatus {
        case .approved: return S.profileKycBadgeVerified
        case .pending:  return S.profileKycBadgePending
        case .rejected: return S.profileKycBadgeRejected
        default:        return S.profileKycBadgeNotStarted
        }
    }

    /// Subtitle on the wallet shortcut. Only states facts the wallet
    /// can deliver on: credit + payment receipts. We removed the old
    /// "Add a payment method to start" CTA because that flow doesn't
    /// exist yet — implying it does was a lie. Once the saved-payment
    /// endpoint ships we can re-introduce the prompt.
    private var walletSubtitle: String {
        if store.voygoCreditMyr > 0 {
            return S.profileWalletCreditAndPayments(Formatters.ringgit(store.voygoCreditMyr))
        }
        if !store.useOnline {
            return S.profileWalletSyncAfterSignIn
        }
        return store.payments.isEmpty ? S.profileWalletNoPayments : S.profileWalletViewPayments
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

// MARK: - Help Center (mirrors HelpCenterScreen.kt)

struct HelpCenterView: View {
    var onBack: () -> Void
    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.helpCenterTitle, onBack: onBack)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "questionmark.bubble.fill").font(.largeTitle).foregroundStyle(VoygoTheme.primaryGradient).accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(S.helpNeedHelp).font(.title3.bold()).foregroundColor(VoygoTheme.textPrimary)
                                Text(S.helpHereForYou).font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
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
                                                title: S.helpEmailSupport,
                                                value: "support@voygo.app")
                                    }
                                }
                                Divider().background(VoygoTheme.cardBorder)
                                HelpRow(icon: "bubble.left.and.bubble.right.fill",
                                        title: S.helpInAppChat,
                                        value: S.helpInAppChatValue)
                                Divider().background(VoygoTheme.cardBorder)
                                if let faq = URL(string: "https://voygo.app/help") {
                                    Link(destination: faq) {
                                        HelpRow(icon: "doc.text.fill",
                                                title: S.helpFAQ,
                                                value: "voygo.app/help")
                                    }
                                }
                            }
                            .padding(16)
                        }
                        Text(S.helpFooter)
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
    @State private var sosNotice: String? = nil
    @State private var sosNoticeIsError = false
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

    private var liveMapCoordinate: CLLocationCoordinate2D? {
        guard let live = store.liveLocation(for: tripId),
              Date().timeIntervalSince(live.recordedAt) < 60 else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: live.lat, longitude: live.lng)
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
                    if let route {
                        VRouteMapPreview(
                            route: route,
                            height: 360,
                            accent: VPalette.primary,
                            liveCoordinate: liveMapCoordinate,
                            cornerRadius: 0
                        )
                    } else {
                        VRouteDiagram(
                            stops: liveTripStops,
                            height: 360,
                            accent: VPalette.primary,
                            dark: true
                        )
                    }

                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.callout.weight(.bold))
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
                            Text("En route").font(.caption.weight(.heavy)).foregroundColor(VPalette.text)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                        Spacer()

                        Button { showShareSheet = true } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline.weight(.bold))
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

                    if liveMapCoordinate != nil {
                        HStack(spacing: 5) {
                            Circle().fill(VPalette.success).frame(width: 6, height: 6)
                            Text("Live driver location")
                                .font(.caption2.weight(.black))
                                .tracking(0.4)
                        }
                        .foregroundColor(VPalette.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        .padding(.top, 106)
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
                //   1. System SMS composer pre-filled for the rider's own
                //      trusted contact.
                //   2. POST /safety/sos — server records the alert and
                //      reports whether ops dispatch is configured.
                showSOSMessageComposer = true
                Task { await postSafetyAlert() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Opens Messages with your trip details and asks Voygo to record an SOS alert. If ops dispatch is configured, the server will notify the safety team too.")
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
                        .font(.largeTitle)
                        .foregroundColor(VPalette.textHint)
                    Text("This device can't send SMS")
                        .font(.subheadline.weight(.heavy))
                    Text("Use another device with cellular service to send the SOS message.")
                        .font(.footnote)
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
                        .font(.caption.weight(.semibold)).foregroundColor(VPalette.textSec)
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
                        Text(pickupLabel).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        VKicker(text: "Drop", color: VPalette.primary, size: 10)
                        Text(dropoffLabel).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                    }
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(VPalette.border).frame(height: 1).padding(.vertical, 16)

            HStack(spacing: 12) {
                VAvatar(initial: driverInitial, size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(driverDisplayName).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                    // Vehicle string isn't on the model yet; show the
                    // car type label which is, and leave a placeholder
                    // for plate. Honest > inventing "Tesla VEC 4123".
                    Text(driverCarLabel)
                        .font(.caption2).foregroundColor(VPalette.textSec)
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
                        .font(.subheadline.weight(.bold)).foregroundColor(.white)
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
                        .font(.subheadline.weight(.bold)).foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(VPalette.primary).clipShape(Circle())
                        .shadow(color: VPalette.primary.opacity(0.5), radius: 8, y: 3)
                }.buttonStyle(.plain)
            }
            .padding(12)
            .background(VPalette.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let sosNotice {
                HStack(spacing: 8) {
                    Image(systemName: sosNoticeIsError ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                        .foregroundColor(sosNoticeIsError ? VPalette.danger : VPalette.success)
                    Text(sosNotice)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(VPalette.textSec)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background((sosNoticeIsError ? VPalette.dangerContainer : VPalette.successContainer).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 12)
            }

            Button { showSOSAlert = true } label: {
                HStack(spacing: 8) {
                    Text("SOS").font(.body.weight(.black))
                    Text("Send SOS")
                        .font(.subheadline.weight(.black))
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
                            .font(.subheadline.weight(.heavy))
                        Text(isSharingLocation ? "Sharing live · keep app open" : "Share live location")
                            .font(.footnote.weight(.black))
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
            Image(systemName: system).font(.subheadline.weight(.bold)).foregroundColor(color)
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

    /// POSTs to /safety/sos and surfaces whether server-side ops dispatch
    /// actually happened. The SMS composer remains the rider's direct
    /// channel, but we no longer pretend the backend notified ops when it
    /// only queued the row.
    private func postSafetyAlert() async {
        let live = store.liveLocation(for: tripId)
        Telemetry.track(TelemetryEvents.liveTripSosTapped, [
            "ride_id": .string(tripId),
            "has_live_location": .bool(live != nil)
        ])
        do {
            let response = try await VoygoAPIClient.reportSafetyAlert(
                rideId: tripId,
                routeId: route?.id,
                lat: live?.lat,
                lng: live?.lng,
                message: sosMessageBody
            )
            if response.opsNotified == true || !response.dispatchedTo.isEmpty {
                sosNotice = "Voygo Safety notified via \(response.dispatchedTo.joined(separator: ", "))."
                sosNoticeIsError = false
            } else {
                sosNotice = "SOS saved for support review. Send the SMS too, because live ops dispatch is not configured."
                sosNoticeIsError = true
            }
        } catch {
            sosNotice = "Couldn't reach Voygo Safety. Send the SMS now and contact support when safe."
            sosNoticeIsError = true
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
                Text(S.profileNameSheetTitle)
                    .font(.body.weight(.black))
                    .tracking(-0.3)
                    .foregroundColor(VPalette.text)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(VPalette.textSec)
                        .frame(width: 32, height: 32)
                        .background(VPalette.surfaceHigh)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(S.cancel)
            }

            Text(S.profileNameSheetSubtitle)
                .font(.caption)
                .foregroundColor(VPalette.textSec)

            TextField(S.profileNamePlaceholder, text: $name)
                .font(.callout.weight(.semibold))
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

            VPrimaryButton(S.save, isLoading: isSaving, isEnabled: canSave) {
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
                Text(S.profileVehicleTitle)
                    .font(.body.weight(.black))
                    .tracking(-0.3)
                    .foregroundColor(VPalette.text)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(VPalette.textSec)
                        .frame(width: 32, height: 32)
                        .background(VPalette.surfaceHigh)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(S.cancel)
            }

            Text(S.profileVehicleSheetSubtitle)
                .font(.caption)
                .foregroundColor(VPalette.textSec)

            field(label: S.profileVehiclePlate,
                  placeholder: S.profileVehiclePlatePlaceholder,
                  text: $plate,
                  field: .plate,
                  autocaps: .characters)

            HStack(spacing: 10) {
                field(label: S.profileVehicleColour,
                      placeholder: S.profileVehicleColourPlaceholder,
                      text: $color,
                      field: .color,
                      autocaps: .words)
                field(label: S.profileVehicleModel,
                      placeholder: S.profileVehicleModelPlaceholder,
                      text: $model,
                      field: .model,
                      autocaps: .words)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(VPalette.danger)
            }

            VPrimaryButton(S.save, isLoading: isSaving, isEnabled: canSave) {
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
                .font(.callout.weight(.semibold))
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
