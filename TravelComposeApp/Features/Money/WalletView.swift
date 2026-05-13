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

    private struct Tx: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let amount: String
        let kind: Kind
        let label: String
        enum Kind { case debit, credit }
    }

    /// Payment methods Billplz exposes at checkout. Static — these
    /// are the rails the checkout host offers, not "saved" cards
    /// (we don't store cards ourselves). Driving from a literal list
    /// keeps the chips honest: removing or adding a chip requires
    /// editing this file, not a server flip we'd forget to mirror.
    private struct AcceptedMethod: Identifiable {
        let id = UUID()
        let label: String
        let chip: String
        let color: Color
    }
    private let acceptedMethods: [AcceptedMethod] = [
        .init(label: "DuitNow", chip: "DN", color: Color(hex: 0xE60028)),
        .init(label: "FPX",     chip: "FPX", color: Color(hex: 0x0E5BA8)),
        .init(label: "TNG eWallet", chip: "TNG", color: Color(hex: 0x0066A1)),
        .init(label: "GrabPay", chip: "GP", color: Color(hex: 0x00B14F)),
        .init(label: "Visa",    chip: "VISA", color: Color(hex: 0x1A1F71)),
        .init(label: "Mastercard", chip: "MC", color: Color(hex: 0xEB001B))
    ]

    /// Picks the soonest-renewing active subscription so the Next
    /// Charge card has a single deterministic candidate. Paused /
    /// cancelled subs are skipped — they won't be billed.
    private var nextRenewalSub: RouteSubscriptionWithRoute? {
        let now = Date()
        return store.mySubscriptions()
            .filter { $0.subscription.status == .active && $0.subscription.endDate >= now }
            .min(by: { $0.subscription.endDate < $1.subscription.endDate })
    }

    /// Estimates the next-charge amount from the rider's payment
    /// history first (most accurate — matches what they've actually
    /// been billed), falling back to a tier-naïve `pricePerSeat * days`
    /// estimate. We don't reapply tier discounts here because the
    /// server is the source of truth — better to slightly overestimate
    /// than to undersell what the rider sees on the checkout sheet.
    private func nextChargeAmountMyr(for item: RouteSubscriptionWithRoute) -> Int {
        let subId = item.subscription.id
        if let lastPaid = store.payments
            .filter({ $0.subscriptionId == subId && $0.status == .paid })
            .max(by: { $0.createdAt < $1.createdAt }) {
            return lastPaid.amountMyr
        }
        let days = item.subscription.totalDays ?? 30
        return item.route.pricePerSeat * days
    }

    private func formatRenewalDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

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
                            nextChargeSection
                            acceptedMethodsSection
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

    // The old empty "Payment methods" card has been split into two
    // sections that actually carry information:
    //   1. NEXT CHARGE — the soonest renewal amount + date for the
    //      rider's current active sub. Answers "when am I getting
    //      billed and how much?", which used to require digging into
    //      My commutes.
    //   2. ACCEPTED AT CHECKOUT — a chip row showing the rails Billplz
    //      offers (DuitNow / FPX / TNG / GrabPay / Visa / Mastercard).
    //      We don't store cards ourselves, so this replaces the old
    //      "no methods" empty state with something visually scannable.

    private var nextChargeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VKicker(text: S.walletNextChargeTitle)
                Spacer()
            }
            .padding(.horizontal, 4)

            if let item = nextRenewalSub {
                let amount = nextChargeAmountMyr(for: item)
                let amountStr = "RM \(amount)"
                let dateStr   = formatRenewalDate(item.subscription.endDate)
                let routeStr  = "\(item.route.startLocation) → \(item.route.endLocation)"
                let tierStr   = S.tierLabel(item.subscription.tier)
                HStack(spacing: 14) {
                    // Inline calendar pip with the renewal day. Same
                    // visual rhythm as the Upcoming Commutes cards so
                    // the rider can map "this is when I'll be charged"
                    // to "this is when my next ride is".
                    VStack(spacing: 2) {
                        let dayF: DateFormatter = { let d = DateFormatter(); d.dateFormat = "d"; return d }()
                        let monF: DateFormatter = { let d = DateFormatter(); d.locale = Locale.current; d.dateFormat = "MMM"; return d }()
                        Text(dayF.string(from: item.subscription.endDate))
                            .font(.title2.bold())
                            .foregroundColor(VPalette.primary)
                        Text(monF.string(from: item.subscription.endDate))
                            .font(.caption2.bold())
                            .foregroundColor(VPalette.textHint)
                    }
                    .frame(width: 44)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(VPalette.primaryContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(S.walletNextChargeAmountOn(amountStr, dateStr))
                            .font(.footnote.weight(.heavy))
                            .foregroundColor(VPalette.text)
                            .lineLimit(2)
                        Text(S.walletNextChargeRouteTier(routeStr, tierStr))
                            .font(.caption2)
                            .foregroundColor(VPalette.textSec)
                            .lineLimit(1)
                        Text(S.walletNextChargeHint)
                            .font(.caption2)
                            .foregroundColor(VPalette.textHint)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(S.walletNextChargeAmountOn(amountStr, dateStr)). \(routeStr). \(tierStr)."
                )
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2)
                        .foregroundColor(VPalette.textHint)
                    Text(S.walletNextChargeNoneTitle)
                        .font(.footnote.weight(.heavy))
                        .foregroundColor(VPalette.textSec)
                    Text(S.walletNextChargeNoneBody)
                        .font(.caption2)
                        .foregroundColor(VPalette.textHint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            }
        }
    }

    private var acceptedMethodsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VKicker(text: S.walletAcceptedAtCheckout)
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 12) {
                // Two rows of 3 chips so the section reads as a
                // visual fingerprint of the rails — easier to scan
                // than a paragraph of brand names. We pin the grid
                // to two rows (LazyVGrid would let it reflow on
                // dynamic-type changes and clip the brand wordmark).
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(acceptedMethods) { m in
                        HStack(spacing: 8) {
                            Text(m.chip)
                                .font(.caption2.weight(.black))
                                .tracking(0.4)
                                .frame(width: 38, height: 26)
                                .foregroundColor(.white)
                                .background(m.color)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(m.label)
                                .font(.caption2.weight(.heavy))
                                .foregroundColor(VPalette.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(m.label)
                    }
                }
                Text(S.walletPickAtCheckout)
                    .font(.caption2)
                    .foregroundColor(VPalette.textHint)
                    .padding(.horizontal, 2)
            }
            .padding(14)
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
