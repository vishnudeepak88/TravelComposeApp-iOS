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
                VPolishedNavBar(title: "This week", kicker: "Driver payouts", onBack: onBack)

                if isLoading && store.payout == nil {
                    LoadingView()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            stripeBanner
                            if let payout = store.payout {
                                HeaderCard(payout: payout)
                                BreakdownCard(payout: payout)
                                ReliabilityCard(payout: payout)
                                FootnoteCard()
                            } else {
                                EmptyStateView(
                                    icon: "banknote",
                                    title: "No earnings yet",
                                    subtitle: "Drive a route this week and your payout will show up here on Tuesday."
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
                    title: "Set up bank payouts",
                    subtitle: "Stripe holds it briefly while your bank verifies. Takes ~3 minutes.",
                    cta: "Continue setup",
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
                    title: "Bank payouts launching soon",
                    subtitle: "We'll notify drivers when Stripe Connect is enabled. Earnings keep accruing in the meantime.",
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
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(VPalette.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(VPalette.textSec)
                    .fixedSize(horizontal: false, vertical: true)
                if let cta, let action {
                    Button(action: action) {
                        Text(cta)
                            .font(.system(size: 12, weight: .heavy))
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
                Text("Week of \(payout.weekStart) → \(payout.weekEnd)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(VoygoTheme.textHint)

                HStack(alignment: .firstTextBaseline) {
                    Text("Net payout")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(VoygoTheme.textSecondary)
                    Spacer()
                    Text("RM \(payout.netMyr)")
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
            return "Paid out · landing in your bank within 24h"
        }
        return "Pays out by Tuesday 5pm"
    }
}

private struct BreakdownCard: View {
    let payout: PayoutStatement

    var body: some View {
        VoygoCard {
            VStack(spacing: 10) {
                row("Rides completed", "\(payout.ridesCount)")
                row("Seats filled", "\(payout.seatsFilled)")
                Divider().background(VoygoTheme.cardBorder)
                row("Gross earnings", "RM \(payout.grossMyr)")
                row("Voygo fee", "−RM \(payout.voygoFeeMyr)", isNegative: true)
                if payout.penaltyMyr > 0 {
                    row("Penalties held", "−RM \(payout.penaltyMyr)", isNegative: true)
                }
                if payout.streakBonusMyr > 0 {
                    row("Streak bonus", "+RM \(payout.streakBonusMyr)", isPositive: true)
                }
                Divider().background(VoygoTheme.cardBorder)
                row("Net payout", "RM \(payout.netMyr)", isBold: true)
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
                    Text("Reliability")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(VoygoTheme.textPrimary)
                    Spacer()
                    Text("\(Int((max(0, min(1, payout.onTimeRate)) * 100).rounded()))% on-time")
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
            return "Top tier. This is what gets riders to renew without thinking about it."
        } else if pct >= 85 {
            return "Solid. A late once in a while is fine — riders see the trend, not the outlier."
        } else {
            return "Below the corridor average. Quick wins: leave 5 minutes earlier and avoid one-message dropouts."
        }
    }
}

private struct FootnoteCard: View {
    var body: some View {
        Text("Voygo's take is 15%, capped at RM 2/seat. Streak bonus of RM 50 kicks in at 20+ on-time rides per week. Penalties from late cancels or no-shows are held from the next payout.")
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
