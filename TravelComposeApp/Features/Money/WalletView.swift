import SwiftUI

// MARK: - Wallet (mirrors WalletScreen.jsx in the prototype)

struct WalletView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    /// Optional drilldown — when wired by the AppRoute switch, the
    /// "See all" affordance on the Recent section pushes Trip History
    /// onto the nav stack. Nil-defaulted so the preview / older call
    /// sites compile.
    var onOpenTripHistory: (() -> Void)? = nil

    /// Distinguishes "we haven't synced yet" from "you genuinely have RM 0
    /// in credit". Without it the empty state and the API-down state
    /// looked identical.
    @State private var isPaymentsLoading: Bool = false

    private struct Method: Identifiable {
        let id = UUID()
        let brand: String
        let info: String
        let color: Color
        let chip: String
        let isDefault: Bool
    }

    private struct Tx: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let amount: String
        let kind: Kind
        let label: String
        enum Kind { case debit, credit }
    }

    /// Empty until the backend exposes `/users/me/payment-methods`.
    /// Showing fake DuitNow/TNG/Visa rows broke trust on a real
    /// account because the user could see four-digit account numbers
    /// that didn't match anything they owned. The card now renders
    /// an honest "no payment methods yet" state instead.
    private let methods: [Method] = []

    /// Real payment history from `store.payments`. The hardcoded
    /// `sampleTxs` reel is gone — fresh installs render an honest
    /// empty state instead of fake "Subang → KLCC" rows that don't
    /// match any actual route the user has.
    private var txs: [Tx] {
        return store.payments.map { p in
            let isCharge = p.status == .paid || p.status == .pending
            let sign = p.status == .refunded ? "+" : (isCharge ? "−" : "")
            let label: String = {
                switch p.status {
                case .paid:     return S.paymentStatusCharged
                case .pending:  return S.paymentStatusPending
                case .failed:   return S.paymentStatusFailed
                case .refunded: return S.paymentStatusRefunded
                }
            }()
            return Tx(
                title: p.routeId.map { S.walletRouteTitle(String($0.prefix(6))) } ?? S.walletSubscriptionTitle,
                // Localized date (Malay device renders "Mei 12" not
                // "May 12") and tier label ("Bulanan" not "monthly").
                subtitle: S.walletTxSubtitle(formatDate(p.createdAt), S.tierLabel(p.tier)),
                amount: "\(sign)RM \(p.amountMyr)",
                kind: p.status == .refunded ? .credit : .debit,
                label: label
            )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        // Locale-aware: previously a fixed "MMM d" without a locale
        // rendered the device's default (typically en-US) regardless
        // of app language. Binding to Locale.current keeps it in
        // step with the rest of the BM UI.
        f.locale = Locale.current
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// Always renders with two decimal places so "RM 42" doesn't look
    /// uneven next to "RM 42.50" in the same column.
    private var formattedCredit: String {
        String(format: "%.2f", Double(store.voygoCreditMyr))
    }

    private var creditSubtitle: String {
        if isPaymentsLoading && store.payments.isEmpty {
            return S.walletSyncing
        }
        return store.voygoCreditMyr > 0
            ? S.walletAutoApplied
            : S.walletEarnPrompt
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Trailing ↗ "Wallet export" button removed — it
                // popped a coming-soon alert with no real flow behind
                // it. Real CSV/PDF export already lives in Privacy &
                // Security → Data export (PDPA path). The header is
                // cleaner without the placebo button.
                VPolishedNavBar(title: S.walletPageTitle, kicker: S.walletPageKicker, onBack: onBack)

                ScrollView {
                    VStack(spacing: 18) {
                        if isPaymentsLoading && store.payments.isEmpty {
                            // Page-shaped skeleton on first load. Far
                            // more honest than the misleading "RM 0.00"
                            // the hero would otherwise render before
                            // payments arrive.
                            walletSkeleton
                        } else {
                            creditHero
                            paymentMethods
                            recent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    isPaymentsLoading = true
                    await store.refreshPayments()
                    isPaymentsLoading = false
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            isPaymentsLoading = true
            await store.refreshPayments()
            isPaymentsLoading = false
        }
    }

    /// Page-shaped placeholder during the first sync. Mirrors the
    /// real layout (hero · methods card · 3 tx rows) so the screen
    /// fills in instead of popping.
    private var walletSkeleton: some View {
        VStack(spacing: 18) {
            VSkeleton(height: 160, corner: 22)
            VStack(spacing: 0) {
                VSkeleton(height: 60, corner: 0)
                Rectangle().fill(VPalette.border).frame(height: 1)
                VSkeleton(height: 60, corner: 0)
            }
            .background(VPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            VStack(spacing: 12) {
                VSkeleton(height: 50, corner: 14)
                VSkeleton(height: 50, corner: 14)
                VSkeleton(height: 50, corner: 14)
            }
        }
    }

    private var creditHero: some View {
        ZStack(alignment: .topLeading) {
            VPalette.creditGradient
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 180, height: 180)
                .blur(radius: 40)
                .offset(x: 130, y: -60)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        VKicker(text: S.walletHeroLabel, color: .white.opacity(0.8))
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(S.walletHeroPrefix).font(.body.weight(.bold)).foregroundColor(.white.opacity(0.85))
                            // Bind to the live credit derived from payment
                            // history. While the first sync is in flight
                            // we show a skeleton instead of "0.00" — the
                            // empty state and the loading state used to
                            // look identical, which led the user to think
                            // their balance was zero when really we just
                            // hadn't fetched yet.
                            if isPaymentsLoading && store.payments.isEmpty {
                                Text("—")
                                    .font(.largeTitle.weight(.black))
                                    .tracking(-1.4)
                                    .foregroundColor(.white.opacity(0.6))
                                    .accessibilityLabel(S.walletLoadingBalanceA11y)
                            } else {
                                Text(formattedCredit)
                                    .font(.largeTitle.weight(.black))
                                    .tracking(-1.4)
                                    .foregroundColor(.white)
                            }
                        }
                        Text(creditSubtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    Text(S.walletHeroBadge)
                        .font(.caption2.weight(.black))
                        .tracking(0.4)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.white.opacity(0.2))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                // Top-up + Withdraw removed — both opened "Coming soon"
                // alerts with no real flow behind them. Shipping a
                // primary CTA on the hero that does nothing is a
                // trust hit. The card now describes how credit
                // actually flows in today: refunds. When real
                // Billplz FPX top-up / DuitNow IBG withdraw land,
                // restore both buttons.
                Text(S.walletCreditBlurb)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var paymentMethods: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VKicker(text: S.walletPaymentMethods)
                Spacer()
                // "+ Add" removed — pressed a coming-soon alert with
                // no real flow. Until /users/me/payment-methods ships,
                // the empty-state copy below explains how checkout
                // actually works (Billplz host page picks the method).
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if methods.isEmpty {
                    // Honest empty state until backend exposes
                    // `/users/me/payment-methods`. Tapping "+ Add"
                    // surfaces the same coming-soon alert as the
                    // header button.
                    VStack(spacing: 6) {
                        Image(systemName: "creditcard")
                            .font(.title2)
                            .foregroundColor(VPalette.textHint)
                        Text(S.walletPayAtCheckout)
                            .font(.footnote.weight(.heavy))
                            .foregroundColor(VPalette.textSec)
                        // Honest: we use Billplz hosted checkout so
                        // the rider picks DuitNow / FPX / TNG /
                        // GrabPay at pay time. There's no "saved
                        // method" yet — old copy promised one.
                        Text(S.walletCheckoutBlurb)
                            .font(.caption2)
                            .foregroundColor(VPalette.textHint)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                } else {
                    ForEach(Array(methods.enumerated()), id: \.element.id) { idx, m in
                        HStack(spacing: 12) {
                            Text(m.chip)
                                .font(.caption2.weight(.black)).tracking(0.4)
                                .frame(width: 44, height: 30)
                                .foregroundColor(.white)
                                .background(m.color)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.brand).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                                Text(m.info).font(.caption2).foregroundColor(VPalette.textSec)
                            }
                            Spacer()
                            if m.isDefault { VBadge(text: S.walletDefault, color: VPalette.primary, container: VPalette.primaryContainer) }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        if idx < methods.count - 1 {
                            Rectangle().fill(VPalette.border).frame(height: 1)
                        }
                    }
                }
            }
            .background(VPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VKicker(text: S.walletRecentTitle)
                Spacer()
                // "See all" now drills into Trip History when the
                // parent wires the callback. Previously a static Text,
                // a clear false affordance the QA report flagged.
                if let onOpenTripHistory {
                    Button(action: onOpenTripHistory) {
                        Text(S.walletSeeAll)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(VPalette.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(S.tripHistoryTitle)
                } else {
                    Text(S.walletSeeAll)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(VPalette.primary)
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if txs.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundColor(VPalette.textHint)
                        Text(S.walletNoPayments)
                            .font(.footnote.weight(.heavy))
                            .foregroundColor(VPalette.textSec)
                        Text(S.walletNoPaymentsBody)
                            .font(.caption2)
                            .foregroundColor(VPalette.textHint)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                } else {
                    ForEach(Array(txs.enumerated()), id: \.element.id) { idx, tx in
                        HStack(spacing: 12) {
                            Image(systemName: tx.kind == .credit ? "arrow.down" : "arrow.right")
                                .font(.footnote.weight(.bold))
                                .foregroundColor(tx.kind == .credit ? VPalette.success : VPalette.textSec)
                                .frame(width: 32, height: 32)
                                .background(tx.kind == .credit ? VPalette.successContainer : VPalette.surfaceHigh)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.title).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                                Text(tx.subtitle).font(.caption2).foregroundColor(VPalette.textSec)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(tx.amount)
                                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                    .foregroundColor(tx.kind == .credit ? VPalette.success : VPalette.text)
                                VKicker(text: tx.label, size: 9)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        if idx < txs.count - 1 {
                            Rectangle().fill(VPalette.border).frame(height: 1)
                        }
                    }
                }
            }
            .background(VPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        }
    }
}

#Preview("WalletView") {
    WalletView(onBack: {})
        .environment(AppStore())
}
