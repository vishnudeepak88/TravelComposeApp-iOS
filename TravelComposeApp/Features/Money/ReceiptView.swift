import SwiftUI

// MARK: - Receipt (mirrors ReceiptScreen.jsx)

struct ReceiptView: View {
    let bookingId: String
    var onBack: () -> Void
    @Environment(AppStore.self) private var store
    @State private var showShareSheet = false

    /// Look up the payment record by id (the bookingId we're handed is the
    /// payment id when navigating from Trip History or Wallet). Falls
    /// through to nil if the user navigated here from a stale deep link
    /// or before payments have synced; the view degrades gracefully.
    private var payment: PaymentRecord? {
        store.payments.first { $0.id == bookingId }
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.receiptTitle, onBack: onBack) {
                    Button { showShareSheet = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.callout.weight(.bold))
                            .foregroundColor(VPalette.primary)
                            .frame(width: 40, height: 40)
                            .background(VPalette.primaryContainer)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    VStack(spacing: 14) {
                        // Action buttons removed — "Email PDF" /
                        // "Add to expenses" both popped fake
                        // coming-soon alerts. The toolbar share button
                        // (above) already opens the system share sheet
                        // which exports the receipt text to any app
                        // (Mail, Files, etc.) so the user has a real
                        // export path.
                        receiptCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(items: [receiptShareText])
                .presentationDetents([.medium])
        }
    }

    private var receiptCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Voygo")
                    .font(.title3.weight(.black))
                    .tracking(-0.4)
                    .foregroundColor(VPalette.primary)
                Text(S.receiptHeader(displayBookingId, receiptStatusText))
                    .font(.caption2.weight(.bold)).tracking(0.4)
                    .foregroundColor(VPalette.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(VPalette.primaryContainer)

            DashedLine()

            if let route = resolvedRoute {
                VRouteMapPreview(
                    route: route,
                    height: 140,
                    accent: VPalette.success
                )
                .accessibilityLabel(Text(S.receiptRouteA11y(mapLabel)))
            } else {
                // Some historical payment rows are not tied to a route.
                // Keep a graceful fallback for those receipts only.
                VRouteDiagram(
                    stops: [
                        .init(label: S.routePickupPoint, kind: .origin),
                        .init(label: S.routeDropPoint,   kind: .dest)
                    ],
                    height: 140,
                    accent: VPalette.success
                )
                .accessibilityLabel(Text(S.receiptRouteUnavailableA11y(mapLabel)))
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VRouteGlyph().frame(height: 64)
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 1) {
                            VKicker(text: S.receiptPickupAt(pickupTimeString), color: VPalette.success, size: 10)
                            // Real pickup label from the resolved route;
                            // honest "—" placeholder when the backend
                            // hasn't threaded the address into the
                            // payment row yet.
                            Text(pickupLabel).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            // "Approx. drop" — backend doesn't ship an
                            // exact drop timestamp on the payment, we
                            // estimate by adding a typical commute
                            // window. Labeled clearly so riders aren't
                            // misled by a precise-looking number.
                            VKicker(text: S.receiptApproxDrop(dropTimeString), color: VPalette.primary, size: 10)
                            Text(dropoffLabel).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 18)

                DashedLine().padding(.vertical, 16)

                HStack(spacing: 10) {
                    VAvatar(initial: driverInitial, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(driverDisplayName).font(.caption.weight(.heavy)).foregroundColor(VPalette.text)
                        Text(vehicleLabel).font(.caption2).foregroundColor(VPalette.textSec)
                    }
                    Spacer()
                    if let rating = driverRating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").foregroundColor(VPalette.starGold).font(.caption)
                            Text(String(format: "%.1f", rating))
                                .font(.caption.weight(.bold)).foregroundColor(VPalette.text)
                        }
                    }
                }

                DashedLine().padding(.vertical, 16)

                VKicker(text: S.receiptFareBreakdown)
                    .padding(.bottom, 4)

                lineItem(S.receiptBaseFare(S.tierLabel(payment?.tier)), value: baseFareString)
                if creditApplied > 0 {
                    lineItem(S.receiptVoygoCredit, value: "−RM \(creditApplied).00", color: VPalette.success)
                }
                // "Tolls covered · Included" row removed — backend
                // doesn't ship per-route toll metadata so we were
                // always rendering "Included" regardless of corridor.
                // Re-add when toll info threads through.

                Rectangle().fill(VPalette.border).frame(height: 1).padding(.vertical, 10)

                HStack {
                    Text(S.receiptTotalCharged).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                    Spacer()
                    Text(totalChargedString)
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .tracking(-0.5)
                        .foregroundColor(VPalette.primary)
                }
                Text(paymentMethodString)
                    .font(.caption2).foregroundColor(VPalette.textSec)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                DashedLine().padding(.vertical, 16)

                HStack(alignment: .top, spacing: 12) {
                    QRPlaceholder()
                        .frame(width: 64, height: 64)
                        // Decorative pattern, not a real QR — VoiceOver
                        // would otherwise announce a meaningless "Image".
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        VKicker(text: S.receiptVerification, size: 10)
                        Text(bookingId)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(VPalette.text)
                        Text(S.receiptForExpense)
                            .font(.caption2)
                            .foregroundColor(VPalette.textSec)
                    }
                    Spacer()
                }
            }
            .padding(18)
        }
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border, lineWidth: 1))
    }

    private func lineItem(_ label: String, value: String, color: Color = VPalette.text) -> some View {
        HStack {
            Text(label).font(.footnote).foregroundColor(VPalette.textSec)
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data-driven copy
    //
    // The body of the receipt was previously hardcoded ("USJ 9 LRT", "Tesla
    // Model 3 · VEC 4123", "RM 11.50", etc.) regardless of which booking
    // the user tapped. These computed values bind to the looked-up payment
    // record and degrade gracefully to placeholders when the record isn't
    // in `store.payments` yet (e.g. opened from a stale notification).

    private var displayBookingId: String {
        guard !bookingId.isEmpty else { return "—" }
        // Backend ids are UUIDs; show the first 8 chars so it stays readable.
        return String(bookingId.prefix(8)).uppercased()
    }

    private var receiptStatusText: String {
        guard let p = payment else { return S.receiptStatusFallback }
        switch p.status {
        case .paid:     return S.receiptStatusCompleted
        case .pending:  return S.receiptStatusPending
        case .failed:   return S.receiptStatusFailed
        case .refunded: return S.receiptStatusRefunded
        }
    }

    private var mapLabel: String {
        guard let p = payment else { return S.receiptStatusFallback }
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d MMM"
        return "\(f.string(from: p.createdAt)) · \(S.receiptStatusFallback) \(displayBookingId)"
    }

    private var baseFareString: String {
        guard let p = payment else { return "—" }
        return Formatters.ringgit(Double(p.amountMyr))
    }

    /// Cancellation refunds reduce the rider's bill via Voygo Credit. Until
    /// the backend tracks per-payment credit application separately we show
    /// a credit line only when the payment row is itself a refund (negative
    /// signal).
    private var creditApplied: Int {
        guard let p = payment, p.status == .refunded else { return 0 }
        return p.amountMyr
    }

    private var totalChargedString: String {
        guard let p = payment else { return "—" }
        return Formatters.ringgit(Double(p.amountMyr))
    }

    /// Resolves the route from `payment.routeId`. Nil when the
    /// payment isn't tied to a route (e.g. a cancellation refund) or
    /// the route has been removed from the local store.
    private var resolvedRoute: RecurringRoute? {
        guard let routeId = payment?.routeId else { return nil }
        return store.routes.first { $0.id == routeId }
    }

    private var pickupLabel: String {
        resolvedRoute?.pickupPoints.first?.label ?? "—"
    }

    private var dropoffLabel: String {
        resolvedRoute?.dropPoints.first?.label ?? "—"
    }

    private var driverDisplayName: String {
        let n = resolvedRoute?.driverName.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? S.receiptDriverFallback : n
    }

    private var driverInitial: String {
        String(driverDisplayName.prefix(1)).uppercased()
    }

    /// Vehicle line; reads `carType.label` until the model carries
    /// plate info. Honest "—" when no route was found.
    private var vehicleLabel: String {
        guard let r = resolvedRoute else { return "—" }
        return "\(r.carType.label) · \(S.receiptPlateOnFile)"
    }

    /// Driver's average rating from the route's reliability bundle.
    /// Nil when the route lookup failed; the star row is hidden.
    private var driverRating: Double? {
        let v = resolvedRoute?.reliability.averageRating ?? 0
        return v > 0 ? v : nil
    }

    private var paymentMethodString: String {
        // TODO: Backend doesn't yet thread the payment-method label
        // through to the payment row. Show "Method on file" until the
        // server starts returning the actual method on PaymentRecord;
        // the previous "Voygo Pay · DuitNow / TNG / card" line was
        // fabricated and would mislead riders who actually paid via FPX
        // or a card.
        return S.receiptMethodOnFile
    }

    /// Best-effort pickup time string. We bind to `payment.createdAt` if
    /// the lookup succeeded — the backend doesn't yet store explicit
    /// pickup/drop timestamps on the payment, so the exact times are
    /// approximate. Real implementation would attach them server-side.
    private var pickupTimeString: String {
        guard let p = payment else { return "—" }
        return Formatters.time(p.createdAt)
    }

    private var dropTimeString: String {
        guard let p = payment else { return "—" }
        // Add the typical commute duration (52 min) until the backend
        // ships an explicit drop timestamp on the payment record.
        let drop = p.createdAt.addingTimeInterval(52 * 60)
        return Formatters.time(drop)
    }

    private var receiptShareText: String {
        guard let p = payment else {
            return S.receiptShareTextFallback(bookingId)
        }
        // `mapLabel` is the human-readable "Pickup → Drop" string
        // already computed for the receipt card — reuse it here so
        // the shared text matches what the rider saw on screen.
        return S.receiptShareText(p.id, mapLabel, p.amountMyr, p.status.rawValue)
    }
}

private struct DashedLine: View {
    var body: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
            .foregroundColor(VPalette.border)
    }
}

private struct QRPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(VPalette.text, lineWidth: 2)
            // Pseudo-QR: fixed grid squares for a deterministic, readable look.
            Canvas { ctx, size in
                let cols = 7
                let pad: CGFloat = 6
                let cell = (min(size.width, size.height) - pad * 2) / CGFloat(cols)
                let pattern: [[Int]] = [
                    [1,1,1,0,1,1,1],
                    [1,0,1,1,1,0,1],
                    [1,1,1,0,0,1,1],
                    [0,1,0,1,0,1,0],
                    [1,1,0,0,1,0,1],
                    [1,0,1,1,1,0,1],
                    [1,1,1,0,1,1,0]
                ]
                for r in 0..<cols {
                    for c in 0..<cols where pattern[r][c] == 1 {
                        let rect = CGRect(
                            x: pad + CGFloat(c) * cell,
                            y: pad + CGFloat(r) * cell,
                            width: cell - 1, height: cell - 1
                        )
                        ctx.fill(Path(rect), with: .color(VPalette.text))
                    }
                }
            }
            .padding(2)
        }
    }
}

#Preview("ReceiptView") {
    ReceiptView(bookingId: "demo-123", onBack: {})
        .environment(AppStore())
}
