import SwiftUI

// MARK: - Wallet (mirrors WalletScreen.jsx in the prototype)

struct WalletView: View {
    @EnvironmentObject var store: AppStore
    var onBack: () -> Void

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

    private let methods: [Method] = [
        .init(brand: "DuitNow", info: "Maybank ··4221 · default", color: Color(hex: 0xFF6B35), chip: "DN", isDefault: true),
        .init(brand: "Touch 'n Go", info: "eWallet · ··2987",      color: Color(hex: 0x0066B3), chip: "TNG", isDefault: false),
        .init(brand: "Visa",        info: "··· 8412 · expires 09/27", color: Color(hex: 0x1A1F71), chip: "V",   isDefault: false)
    ]

    /// Real payment history from `store.payments` if any, otherwise the
    /// sample reel — preserves the polished demo when the device hasn't
    /// charged anything yet, and switches to live data the moment one row
    /// arrives.
    private var txs: [Tx] {
        if store.payments.isEmpty { return sampleTxs }
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

    private let sampleTxs: [Tx] = [
        .init(title: "Subang → KLCC", subtitle: "Jun 14 · Aiman Z.",        amount: "−RM 14", kind: .debit,  label: "Charged"),
        .init(title: "Voygo Credit",  subtitle: "Jun 13 · Cancellation refund", amount: "+RM 7", kind: .credit, label: "Credited"),
        .init(title: "Subang → KLCC", subtitle: "Jun 13 · Aiman Z.",         amount: "−RM 14", kind: .debit,  label: "Charged"),
        .init(title: "DuitNow top-up", subtitle: "Jun 10 · Maybank",          amount: "+RM 50", kind: .credit, label: "Topped up"),
        .init(title: "Subang → MV",    subtitle: "Jun 10 · Priya S.",         amount: "−RM 11", kind: .debit,  label: "Charged")
    ]

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
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
                        creditHero
                        paymentMethods
                        recent
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .refreshable { await store.refreshPayments() }
            }
        }
        .navigationBarHidden(true)
        .task { await store.refreshPayments() }
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
                            Text("42.50").font(.system(size: 40, weight: .black)).tracking(-1.4).foregroundColor(.white)
                        }
                        Text("Auto-applied to next ride")
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
                    Button {} label: {
                        Text("+ Top up")
                            .font(.system(size: 12, weight: .heavy))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(.white.opacity(0.18))
                            .foregroundColor(.white)
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.25)))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }.buttonStyle(.plain)

                    Button {} label: {
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
                Text("+ Add").font(.system(size: 12, weight: .semibold)).foregroundColor(VPalette.primary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
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
            .background(VPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        }
    }
}
