import SwiftUI

// MARK: - Driver weekly payout statement.
//
// Mirrors the playbook §7.5 template literally — same numbers, same labels,
// same "you're at X% on-time" line. The driver opens this from the dashboard
// and sees exactly what we'd email them on Tuesday.

struct DriverPayoutsView: View {
    @EnvironmentObject var store: AppStore
    var onBack: () -> Void

    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "This week", showBack: true, onBack: onBack)
                    .background(VoygoTheme.background)

                if isLoading && store.payout == nil {
                    LoadingView()
                } else if let payout = store.payout {
                    ScrollView {
                        VStack(spacing: 16) {
                            HeaderCard(payout: payout)
                            BreakdownCard(payout: payout)
                            ReliabilityCard(payout: payout)
                            FootnoteCard()
                        }
                        .padding(20)
                    }
                    .refreshable { await store.refreshPayout() }
                } else {
                    EmptyStateView(
                        icon: "banknote",
                        title: "No earnings yet",
                        subtitle: "Drive a route this week and your payout will show up here on Tuesday."
                    )
                }
            }
        }
        .task {
            isLoading = true
            await store.refreshPayout()
            isLoading = false
        }
    }
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
