import SwiftUI

// MARK: - Trip History (mirrors TripHistoryScreen.jsx)

struct TripHistoryView: View {
    var onBack: () -> Void
    var onOpenReceipt: (String) -> Void

    private struct Trip: Identifiable {
        let id = UUID()
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

    private let trips: [Trip] = [
        .init(dow: "FRI", day: "14", mo: "JUN", route: "Subang → KLCC", driver: "Aiman Z.", price: "RM 14", dur: "52 min", rating: 5, cancelled: false, receiptId: "VG-412-0614"),
        .init(dow: "THU", day: "13", mo: "JUN", route: "KLCC → Subang", driver: "Aiman Z.", price: "RM 14", dur: "1h 02m", rating: 5, cancelled: false, receiptId: "VG-412-0613"),
        .init(dow: "WED", day: "12", mo: "JUN", route: "Subang → KLCC", driver: "Aiman Z.", price: "RM 0",  dur: "—",      rating: 0, cancelled: true,  receiptId: nil),
        .init(dow: "TUE", day: "11", mo: "JUN", route: "Subang → KLCC", driver: "Aiman Z.", price: "RM 14", dur: "58 min", rating: 4, cancelled: false, receiptId: "VG-412-0611"),
        .init(dow: "MON", day: "10", mo: "JUN", route: "Subang → MV",   driver: "Priya S.", price: "RM 11", dur: "36 min", rating: 5, cancelled: false, receiptId: "VG-204-0610")
    ]

    // "Receipts" was identical to "Completed" because every completed
    // row has a receipt — dropped to remove the redundant chip.
    private let filters = ["All", "Completed", "Cancelled"]
    @State private var filter = "All"

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Trip History", kicker: "Last 30 days · 18 trips", onBack: onBack)

                summary
                    .padding(.horizontal, 16).padding(.bottom, 12)

                filterRail
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 8) {
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
                                Image(systemName: "tray").font(.system(size: 32)).foregroundColor(VPalette.textHint)
                                Text("No trips match this filter")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundColor(VPalette.textSec)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
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
            stat("Total", value: "RM 252", color: VPalette.primary)
            stat("Saved", value: "RM 168", color: VPalette.success)
            stat("On-time", value: "94%", color: VPalette.accent)
        }
    }

    private func stat(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            VKicker(text: label, size: 9)
            Text(value).font(.system(size: 16, weight: .black)).tracking(-0.3).foregroundColor(color)
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
                            .font(.system(size: 12, weight: .bold))
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
                Text(t.dow).font(.system(size: 9, weight: .black)).tracking(0.6)
                    .foregroundColor(t.cancelled ? VPalette.textHint : VPalette.primary)
                Text(t.day).font(.system(size: 18, weight: .black)).tracking(-0.4).lineLimit(1)
                    .foregroundColor(t.cancelled ? VPalette.textHint : VPalette.primary)
                Text(t.mo).font(.system(size: 9, weight: .black)).tracking(0.5)
                    .foregroundColor(t.cancelled ? VPalette.textHint : VPalette.primary)
            }
            .frame(width: 50)
            .padding(.vertical, 8)
            .background(t.cancelled ? VPalette.surfaceHigh : VPalette.primaryContainer)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(t.route)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(VPalette.text)
                    .strikethrough(t.cancelled, color: VPalette.textHint)
                Text("\(t.driver) · \(t.dur)")
                    .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                if !t.cancelled, t.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
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
                    Text("Cancelled").font(.system(size: 10, weight: .heavy)).foregroundColor(VPalette.danger)
                } else {
                    Text("Receipt ›").font(.system(size: 10, weight: .heavy)).foregroundColor(VPalette.primary)
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
