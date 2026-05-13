import SwiftUI

// MARK: - Trip History (mirrors TripHistoryScreen.jsx)
//
// Reads from `store.payments` instead of the old hardcoded reel.
// Each PaymentRecord row maps to a Trip; refunded payments display
// as cancelled. Where the backend doesn't yet thread richer fields
// (driver name, duration), we degrade to short placeholders rather
// than inventing data — earlier deep audit flagged hardcoded data
// as the single biggest user-facing risk.

struct TripHistoryView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onOpenReceipt: (String) -> Void

    private struct Trip: Identifiable {
        let id: String
        let dow: String
        let day: String
        let mo: String
        let route: String
        let driver: String
        let price: String
        let dur: String
        let rating: Int
        let cancelled: Bool
        let receiptId: String?
    }

    /// Map a `PaymentRecord` to a display row. Falls back gracefully
    /// when the route lookup fails — we still show the date and amount
    /// so the user has *some* context.
    private var trips: [Trip] {
        store.payments.map { p in
            let route = p.routeId.flatMap { id in store.routes.first { $0.id == id } }
            let routeLabel: String = {
                if let r = route { return "\(shortStop(r.startLocation)) → \(shortStop(r.endLocation)) " }
                return p.tier?.capitalized ?? "Voygo subscription"
            }()
            let driverLabel = route?.driverName.isEmpty == false
                ? route!.driverName
                : "Driver"
            let dow = weekdayShort(p.createdAt).uppercased()
            let day = String(Calendar.current.component(.day, from: p.createdAt))
            let mo  = monthShort(p.createdAt).uppercased()
            let amount = Formatters.ringgit(p.amountMyr)
            let cancelled = p.status == .refunded || p.status == .failed
            return Trip(
                id:       p.id,
                dow:      dow,
                day:      day,
                mo:       mo,
                route:    routeLabel.trimmingCharacters(in: .whitespaces),
                driver:   "\(driverLabel) · \(p.tier?.lowercased() ?? "ride")",
                price:    cancelled ? "—" : amount,
                dur:      "—",
                rating:   0, // No rating storage on the payment row yet.
                cancelled: cancelled,
                receiptId: cancelled ? nil : p.id
            )
        }
    }

    private let filters = ["All", "Completed", "Cancelled"]
    @State private var filter = "All"
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Trip History", kicker: tripsKicker, onBack: onBack)

                summary
                    .padding(.horizontal, 16).padding(.bottom, 12)

                filterRail
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Page-shaped skeleton during first refresh.
                        if isRefreshing && trips.isEmpty {
                            ForEach(0..<5, id: \.self) { _ in
                                VSkeleton(height: 76, corner: 16)
                            }
                            .padding(.horizontal, 0)
                        }
                        ForEach(filteredTrips) { t in
                            // Only completed rows are interactive — cancelled
                            // rows have no receipt to open, so we don't add
                            // the tap handler at all (avoids the false
                            // affordance the QA report flagged).
                            if t.cancelled {
                                tripRow(t)
                                    .opacity(0.7)
                                    .accessibilityLabel("Cancelled trip on \(t.dow) \(t.day) \(t.mo)")
                            } else if let r = t.receiptId {
                                tripRow(t)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onOpenReceipt(r) }
                            } else {
                                tripRow(t)
                            }
                        }
                        if filteredTrips.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray").font(.title).foregroundColor(VPalette.textHint).accessibilityHidden(true)
                                Text(emptyStateTitle)
                                    .font(.footnote.weight(.heavy))
                                    .foregroundColor(VPalette.textSec)
                                if trips.isEmpty {
                                    Text("Your completed and cancelled trips will appear here.")
                                        .font(.caption)
                                        .foregroundColor(VPalette.textHint)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    isRefreshing = true
                    await store.refreshPayments()
                    isRefreshing = false
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            // Pull payments on open so the user sees real data even
            // if the global refresh hasn't fired yet (e.g. they jumped
            // straight to TripHistory from a deep link). Flip
            // `isRefreshing` so the skeleton row count holds the
            // ScrollView shape during the first fetch.
            isRefreshing = true
            await store.refreshPayments()
            isRefreshing = false
        }
    }

    private var emptyStateTitle: String {
        if trips.isEmpty { return "No trips yet" }
        return "No trips match this filter"
    }

    /// Filter chip → predicate. "Receipts" used to live here but was
    /// identical to "Completed" — every completed trip has a receipt —
    /// so the chip was dropped to remove the redundancy.
    private var filteredTrips: [Trip] {
        switch filter {
        case "Completed": return trips.filter { !$0.cancelled }
        case "Cancelled": return trips.filter {  $0.cancelled }
        default:          return trips
        }
    }

    private var summary: some View {
        HStack(spacing: 8) {
            stat("Total",   value: Formatters.ringgit(totalCharged),  color: VPalette.primary)
            stat("Trips",   value: "\(completedCount)",     color: VPalette.success)
            stat("Refunded", value: Formatters.ringgit(totalRefunded), color: VPalette.accent)
        }
    }

    /// Sum of paid + pending charges (i.e. money out of the rider's
    /// wallet over the visible window).
    private var totalCharged: Int {
        store.payments
            .filter { $0.status == .paid || $0.status == .pending }
            .map(\.amountMyr)
            .reduce(0, +)
    }

    private var totalRefunded: Int {
        store.payments
            .filter { $0.status == .refunded }
            .map(\.amountMyr)
            .reduce(0, +)
    }

    private var completedCount: Int {
        store.payments.filter { $0.status == .paid }.count
    }

    /// Honest count for the kicker: actual rows the user is looking at.
    /// Previously hardcoded to "18 trips" regardless of state.
    private var tripsKicker: String {
        let n = trips.count
        switch n {
        case 0: return "No trips yet"
        case 1: return "1 trip"
        default: return "\(n) trips"
        }
    }

    private func shortStop(_ raw: String) -> String {
        let trimmed = raw.split(separator: ",").first.map(String.init) ?? raw
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    private func monthShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_MY")
        f.dateFormat = "MMM"
        return f.string(from: date)
    }

    private func weekdayShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_MY")
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func stat(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            VKicker(text: label, size: 9)
            Text(value).font(.callout.weight(.black)).tracking(-0.3).foregroundColor(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VPalette.border, lineWidth: 1))
    }

    private var filterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters, id: \.self) { f in
                    let on = f == filter
                    Button { filter = f } label: {
                        Text(f)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 13).padding(.vertical, 7)
                            .foregroundColor(on ? .white : VPalette.textSec)
                            .background(on ? VPalette.text : VPalette.surface)
                            .overlay(Capsule().stroke(on ? Color.clear : VPalette.border, lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func tripRow(_ t: Trip) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(t.dow).font(.caption2.weight(.black)).tracking(0.6)
                    .foregroundColor(t.cancelled ? VPalette.textHint : VPalette.primary)
                Text(t.day).font(.body.weight(.black)).tracking(-0.4).lineLimit(1)
                    .foregroundColor(t.cancelled ? VPalette.textHint : VPalette.primary)
                Text(t.mo).font(.caption2.weight(.black)).tracking(0.5)
                    .foregroundColor(t.cancelled ? VPalette.textHint : VPalette.primary)
            }
            .frame(width: 50)
            .padding(.vertical, 8)
            .background(t.cancelled ? VPalette.surfaceHigh : VPalette.primaryContainer)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(t.route)
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.text)
                    .strikethrough(t.cancelled, color: VPalette.textHint)
                Text("\(t.driver) · \(t.dur)")
                    .font(.caption2).foregroundColor(VPalette.textSec)
                if !t.cancelled, t.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(i < t.rating ? VPalette.starGold : VPalette.border)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(t.price)
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundColor(t.cancelled ? VPalette.textHint : VPalette.text)
                if t.cancelled {
                    Text("Cancelled").font(.caption2.weight(.heavy)).foregroundColor(VPalette.danger)
                } else {
                    Text("Receipt ›").font(.caption2.weight(.heavy)).foregroundColor(VPalette.primary)
                }
            }
        }
        .padding(12)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        .opacity(t.cancelled ? 0.7 : 1)
    }
}

#Preview("TripHistoryView") {
    TripHistoryView(onBack: {}, onOpenReceipt: { _ in })
        .environment(AppStore())
}
