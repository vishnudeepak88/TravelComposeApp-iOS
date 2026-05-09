import SwiftUI

// MARK: - Wallet (mirrors WalletScreen.jsx in the prototype)

struct WalletView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void

    /// Distinguishes "we haven't synced yet" from "you genuinely have RM 0
    /// in credit". Without it the empty state and the API-down state
    /// looked identical.
    @State private var isPaymentsLoading: Bool = false
    @State private var showComingSoonFor: String? = nil

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
                case .paid:     return "Charged"
                case .pending:  return "Pending"
                case .failed:   return "Failed"
                case .refunded: return "Refunded"
                }
            }()
            return Tx(
                title: p.routeId.map { "Route \($0.prefix(6))" } ?? "Voygo subscription",
                subtitle: "\(formatDate(p.createdAt)) · \(p.tier ?? "Monthly")",
                amount: "\(sign)RM \(p.amountMyr)",
                kind: p.status == .refunded ? .credit : .debit,
                label: label
            )
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
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
            return "Syncing your wallet…"
        }
        return store.voygoCreditMyr > 0
            ? "Auto-applied to next ride"
            : "Earn credit from referrals & cancellations"
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Wallet", kicker: "Payments & credits", onBack: onBack) {
                    Button {} label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(VPalette.text)
                            .frame(width: 40, height: 40)
                            .background(VPalette.surface)
                            .overlay(Circle().stroke(VPalette.border, lineWidth: 1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

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
        .alert(
            "Coming soon",
            isPresented: Binding(
                get: { showComingSoonFor != nil },
                set: { if !$0 { showComingSoonFor = nil } }
            ),
            presenting: showComingSoonFor
        ) { _ in
            Button("OK", role: .cancel) { showComingSoonFor = nil }
        } message: { feature in
            Text("\(feature) is on the roadmap. We'll let you know when it lands.")
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
                        VKicker(text: "Voygo Credit", color: .white.opacity(0.8))
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text("RM").font(.system(size: 18, weight: .bold)).foregroundColor(.white.opacity(0.85))
                            // Bind to the live credit derived from payment
                            // history. While the first sync is in flight
                            // we show a skeleton instead of "0.00" — the
                            // empty state and the loading state used to
                            // look identical, which led the user to think
                            // their balance was zero when really we just
                            // hadn't fetched yet.
                            if isPaymentsLoading && store.payments.isEmpty {
                                Text("—")
                                    .font(.system(size: 40, weight: .black))
                                    .tracking(-1.4)
                                    .foregroundColor(.white.opacity(0.6))
                                    .accessibilityLabel("Loading wallet balance")
                            } else {
                                Text(formattedCredit)
                                    .font(.system(size: 40, weight: .black))
                                    .tracking(-1.4)
                                    .foregroundColor(.white)
                            }
                        }
                        Text(creditSubtitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    Text("VOYGO")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.4)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.white.opacity(0.2))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                HStack(spacing: 8) {
                    Button { showComingSoonFor = "Top-up" } label: {
                        Text("+ Top up")
                            .font(.system(size: 12, weight: .heavy))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(.white.opacity(0.18))
                            .foregroundColor(.white)
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.25)))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }.buttonStyle(.plain)

                    Button { showComingSoonFor = "Withdraw to bank" } label: {
                        Text("Withdraw")
                            .font(.system(size: 12, weight: .heavy))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(.white)
                            .foregroundColor(VPalette.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var paymentMethods: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VKicker(text: "Payment methods")
                Spacer()
                Button { showComingSoonFor = "Add payment method" } label: {
                    Text("+ Add").font(.system(size: 12, weight: .semibold)).foregroundColor(VPalette.primary)
                }.buttonStyle(.plain)
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
                            .font(.system(size: 26))
                            .foregroundColor(VPalette.textHint)
                        Text("No payment methods yet")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(VPalette.textSec)
                        Text("Add a card or e-wallet to subscribe to routes")
                            .font(.system(size: 11))
                            .foregroundColor(VPalette.textHint)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                } else {
                    ForEach(Array(methods.enumerated()), id: \.element.id) { idx, m in
                        HStack(spacing: 12) {
                            Text(m.chip)
                                .font(.system(size: 10, weight: .black)).tracking(0.4)
                                .frame(width: 44, height: 30)
                                .foregroundColor(.white)
                                .background(m.color)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.brand).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                                Text(m.info).font(.system(size: 11)).foregroundColor(VPalette.textSec)
                            }
                            Spacer()
                            if m.isDefault { VBadge(text: "Default", color: VPalette.primary, container: VPalette.primaryContainer) }
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
                VKicker(text: "Recent")
                Spacer()
                Text("See all").font(.system(size: 12, weight: .semibold)).foregroundColor(VPalette.primary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if txs.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.system(size: 26))
                            .foregroundColor(VPalette.textHint)
                        Text("No payments yet")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(VPalette.textSec)
                        Text("Subscribe to a route and your charges appear here")
                            .font(.system(size: 11))
                            .foregroundColor(VPalette.textHint)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                } else {
                    ForEach(Array(txs.enumerated()), id: \.element.id) { idx, tx in
                        HStack(spacing: 12) {
                            Image(systemName: tx.kind == .credit ? "arrow.down" : "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(tx.kind == .credit ? VPalette.success : VPalette.textSec)
                                .frame(width: 32, height: 32)
                                .background(tx.kind == .credit ? VPalette.successContainer : VPalette.surfaceHigh)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.title).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                                Text(tx.subtitle).font(.system(size: 11)).foregroundColor(VPalette.textSec)
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
