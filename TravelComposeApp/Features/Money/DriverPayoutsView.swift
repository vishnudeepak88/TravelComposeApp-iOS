import SwiftUI
import SafariServices

// MARK: - Driver weekly payout statement.
//
// Mirrors the playbook §7.5 template literally — same numbers, same labels,
// same "you're at X% on-time" line. The driver opens this from the dashboard
// and sees exactly what we'd email them on Tuesday.

struct DriverPayoutsView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void

    @State private var isLoading = true
    /// Stripe Connect onboarding state. `nil` until the first
    /// `/drivers/me/connect-account` GET resolves; iOS keeps the
    /// banner hidden until then.
    @State private var connectAccount: DriverConnectAccountResponse? = nil
    @State private var stripeURL: URL? = nil

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.driverPayoutsNavTitle, kicker: S.driverPayoutsKicker, onBack: onBack)

                if isLoading && store.payout == nil {
                    LoadingView()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            stripeBanner
                            if let payout = store.payout, payout.ridesCount > 0 {
                                HeaderCard(payout: payout)
                                BreakdownCard(payout: payout)
                                ReliabilityCard(payout: payout)
                                FootnoteCard()
                            } else if store.payout != nil {
                                // Zero-rides week: the full breakdown
                                // is a row of zeros and a 0% on-time
                                // signal. Drop down to the same
                                // empty-state pattern as never-driven
                                // so the page doesn't trip the driver
                                // into thinking something is broken.
                                EmptyStateView(
                                    icon: "banknote",
                                    title: S.driverPayoutsZeroRidesTitle,
                                    subtitle: S.driverPayoutsZeroRidesBody
                                )
                            } else {
                                EmptyStateView(
                                    icon: "banknote",
                                    title: S.driverPayoutsEmptyTitle,
                                    subtitle: S.driverPayoutsEmptyBody
                                )
                            }
                        }
                        .padding(20)
                    }
                    .refreshable {
                        await store.refreshPayout()
                        await refreshConnect()
                    }
                }
            }
        }
        .task {
            isLoading = true
            async let payoutFetch: Void = store.refreshPayout()
            async let connectFetch: Void = refreshConnect()
            _ = await (payoutFetch, connectFetch)
            isLoading = false
        }
        .sheet(item: Binding(
            get: { stripeURL.map { URLBox(url: $0) } },
            set: { _ in stripeURL = nil }
        )) { box in
            // Reuses the same SFSafariViewController pattern as the
            // Billplz checkout sheet.
            ConnectOnboardingSafariSheet(url: box.url)
                .ignoresSafeArea()
        }
    }

    /// Renders one of three banners depending on the response state.
    /// `READY` hides the banner entirely (verified driver doesn't
    /// need a CTA). `PENDING` exposes the onboarding URL. `UNCONFIGURED`
    /// surfaces an honest "coming soon" so we don't blame the driver
    /// for a missing env var.
    @ViewBuilder
    private var stripeBanner: some View {
        if let acc = connectAccount {
            switch acc.state {
            case "PENDING":
                payoutsBanner(
                    icon: "creditcard.fill",
                    title: S.driverPayoutsConnectPendingTitle,
                    subtitle: S.driverPayoutsConnectPendingBody,
                    cta: S.driverPayoutsConnectPendingCTA,
                    color: VPalette.primary,
                    container: VPalette.primaryContainer
                ) {
                    if let urlStr = acc.onboardingUrl, let url = URL(string: urlStr) {
                        stripeURL = url
                    }
                }
            case "UNCONFIGURED":
                payoutsBanner(
                    icon: "clock.arrow.circlepath",
                    title: S.driverPayoutsConnectComingTitle,
                    subtitle: S.driverPayoutsConnectComingBody,
                    cta: nil,
                    color: VPalette.warning,
                    container: VPalette.warningContainer,
                    action: nil
                )
            default: // "READY" or anything else → hide
                EmptyView()
            }
        }
    }

    private func payoutsBanner(icon: String, title: String, subtitle: String,
                                cta: String?, color: Color, container: Color,
                                action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VIconBubble(systemName: icon, color: color, size: 38, iconSize: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(VPalette.textSec)
                    .fixedSize(horizontal: false, vertical: true)
                if let cta, let action {
                    Button(action: action) {
                        Text(cta)
                            .font(.caption.weight(.heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(color)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(container)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func refreshConnect() async {
        do {
            connectAccount = try await VoygoAPIClient.driverConnectAccount()
        } catch {
            // non-fatal — banner just stays hidden
        }
    }
}

// MARK: - Stripe onboarding sheet
//
// Same pattern as `BillplzCheckoutSheet`: hosted page in
// SFSafariViewController, dismissed when the driver returns to
// the app via the return URL or hits Done.

private struct URLBox: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ConnectOnboardingSafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredBarTintColor = UIColor(VPalette.surface)
        vc.preferredControlTintColor = UIColor(VPalette.primary)
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct HeaderCard: View {
    let payout: PayoutStatement

    var body: some View {
        VoygoCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(S.driverPayoutsWeekOf(payout.weekStart, payout.weekEnd))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(VoygoTheme.textHint)

                HStack(alignment: .firstTextBaseline) {
                    Text(S.driverPayoutsNetPayout)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(VoygoTheme.textSecondary)
                    Spacer()
                    Text(Formatters.ringgit(payout.netMyr))
                        // Semantic font scales with Dynamic Type — the
                        // previous hardcoded 36pt would clip mid-character
                        // at AX5.
                        .font(.system(.largeTitle, design: .default).weight(.black))
                        .foregroundStyle(VoygoTheme.primaryGradient)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }

                Text(footerText)
                    .font(.caption)
                    .foregroundColor(VoygoTheme.textHint)
            }
            .padding(18)
        }
    }

    private var footerText: String {
        if payout.status == "PAID" {
            return S.driverPayoutsPaidOut
        }
        return S.driverPayoutsPaysOutBy
    }
}

private struct BreakdownCard: View {
    let payout: PayoutStatement

    var body: some View {
        VoygoCard {
            VStack(spacing: 10) {
                row(S.driverPayoutsRidesCompleted, "\(payout.ridesCount)")
                row(S.driverPayoutsSeatsFilled, "\(payout.seatsFilled)")
                Divider().background(VoygoTheme.cardBorder)
                row(S.driverPayoutsGrossEarnings, Formatters.ringgit(payout.grossMyr))
                row(S.driverPayoutsVoygoFee, Formatters.ringgitSigned(payout.voygoFeeMyr, debit: true), isNegative: true)
                if payout.penaltyMyr > 0 {
                    row(S.driverPayoutsPenaltiesHeld, Formatters.ringgitSigned(payout.penaltyMyr, debit: true), isNegative: true)
                }
                if payout.streakBonusMyr > 0 {
                    row(S.driverPayoutsStreakBonus, Formatters.ringgitSigned(payout.streakBonusMyr, debit: false), isPositive: true)
                }
                Divider().background(VoygoTheme.cardBorder)
                row(S.driverPayoutsNetPayout, Formatters.ringgit(payout.netMyr), isBold: true)
            }
            .padding(16)
        }
    }

    private func row(_ label: String, _ value: String,
                     isNegative: Bool = false, isPositive: Bool = false, isBold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(isBold ? .bold : .regular))
                .foregroundColor(VoygoTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(isBold ? .bold : .semibold))
                .foregroundColor(
                    isNegative ? VoygoTheme.danger
                    : (isPositive ? VoygoTheme.success : VoygoTheme.textPrimary)
                )
        }
    }
}

private struct ReliabilityCard: View {
    let payout: PayoutStatement

    var body: some View {
        VoygoCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(VoygoTheme.success)
                    Text(S.driverPayoutsReliability)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(VoygoTheme.textPrimary)
                    Spacer()
                    Text(S.driverPayoutsOnTimePct(Int((max(0, min(1, payout.onTimeRate)) * 100).rounded())))
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(VoygoTheme.success)
                }
                Text(reliabilityCopy)
                    .font(.caption)
                    .foregroundColor(VoygoTheme.textSecondary)
            }
            .padding(16)
        }
    }

    private var reliabilityCopy: String {
        // Clamp before display — a malformed backend value (1.5, 95) would
        // otherwise render as "150% on-time" or "9500% on-time".
        let pct = Int((max(0, min(1, payout.onTimeRate)) * 100).rounded())
        if pct >= 95 {
            return S.driverPayoutsReliabilityTop
        } else if pct >= 85 {
            return S.driverPayoutsReliabilitySolid
        } else {
            return S.driverPayoutsReliabilityLow
        }
    }
}

private struct FootnoteCard: View {
    var body: some View {
        // Aligned with the LPKP defense brief: Voygo charges a flat
        // per-seat platform fee, not a percentage commission. The
        // previous copy ("15%, capped at RM 2/seat") leaked an old
        // pricing model that contradicts the regulator-facing
        // narrative.
        Text(S.driverPayoutsFootnote)
            .font(.caption2)
            .foregroundColor(VoygoTheme.textHint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

#Preview("DriverPayoutsView") {
    DriverPayoutsView(onBack: {})
        .environment(AppStore())
}
