import SwiftUI
import SafariServices

// MARK: - Long-haul trip detail + book
//
// Shows the trip the rider tapped + a Book CTA that runs the existing
// Billplz pipeline. We re-fetch on appear so the seat counter is
// fresh; without it a rider could be staring at a cached "3 seats"
// row that's been booked out in the meantime.

struct LongHaulTripDetailView: View {
    @Environment(AppStore.self) private var store
    let tripId: String
    var onBack: () -> Void
    var onBooked: () -> Void = {}

    @State private var trip: LongHaulTrip? = nil
    @State private var loadError: String? = nil
    @State private var seats: Int = 1
    @State private var pendingPaymentURL: URL? = nil
    @State private var bookState: BookState = .idle

    enum BookState: Equatable {
        case idle, booking, success, failure(String)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Trip details", onBack: onBack)

                ScrollView {
                    if let trip {
                        VStack(spacing: 14) {
                            corridorCard(trip)
                            driverCard(trip)
                            seatsCard(trip)
                            if !trip.notes.isEmpty {
                                notesCard(trip.notes)
                            }
                            bookCTA(trip)
                            if case .failure(let msg) = bookState {
                                VErrorBanner(message: msg)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    } else if let err = loadError {
                        VErrorBanner(message: err, onRetry: { Task { await load() } })
                            .padding(16)
                    } else {
                        skeleton
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: bindingForCheckout()) { holder in
            SafariView(url: holder.url) {
                pendingPaymentURL = nil
                onBooked()
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    VSkeleton(height: 18)
                    VSkeleton(height: 14)
                }
                .padding(14)
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(16)
    }

    // MARK: Cards

    private func corridorCard(_ trip: LongHaulTrip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "location.north.fill")
                    .font(.caption)
                    .foregroundColor(VPalette.accentAmber)
                Text(formatDeparture(trip.departAt))
                    .font(.caption.weight(.heavy))
                    .foregroundColor(VPalette.textSec)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(trip.origin)
                    .font(.title3.weight(.black))
                    .foregroundColor(VPalette.text)
                Image(systemName: "arrow.right")
                    .font(.title3.weight(.heavy))
                    .foregroundColor(VPalette.textHint)
                Text(trip.destination)
                    .font(.title3.weight(.black))
                    .foregroundColor(VPalette.text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private func driverCard(_ trip: LongHaulTrip) -> some View {
        HStack(spacing: 12) {
            VAvatar(initial: String((trip.driverName ?? "D").prefix(1)), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.driverName ?? "Driver")
                    .font(.subheadline.weight(.heavy))
                    .foregroundColor(VPalette.text)
                if let rating = trip.driverRating, rating > 0 {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(VPalette.warning)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private func seatsCard(_ trip: LongHaulTrip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Seats")
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.text)
                Spacer()
                Text("\(trip.seatsAvailable) available")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(VPalette.textSec)
            }
            HStack(spacing: 16) {
                // CRASH GUARD: `Stepper(value:in:)` crashes if
                // upperBound < lowerBound. When a trip flips to
                // seatsAvailable == 0 between fetch + render (booked
                // out underneath us), `1...min(0, 8)` collapses to
                // `1...0` → ClosedRange precondition failure. The
                // `max(1, ...)` keeps the range valid; the outer
                // `trip.isOpen` gate at the CTA prevents an actual
                // 0-seat booking from being submitted.
                Stepper("Seats: \(seats)", value: $seats, in: 1...max(1, min(trip.seatsAvailable, 8)))
                    .labelsHidden()
                Text("\(seats) seat\(seats == 1 ? "" : "s")")
                    .font(.subheadline.weight(.heavy))
                    .foregroundColor(VPalette.text)
                Spacer()
                Text(Formatters.ringgit(trip.pricePerSeatMyr * seats))
                    .font(.body.weight(.black))
                    .foregroundColor(VPalette.primary)
            }
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("From the driver")
                .font(.caption.weight(.heavy))
                .foregroundColor(VPalette.textHint)
            Text(notes)
                .font(.footnote)
                .foregroundColor(VPalette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private func bookCTA(_ trip: LongHaulTrip) -> some View {
        let label: String = {
            switch bookState {
            case .booking: return "Booking…"
            case .success: return "Booked"
            default:       return "Book \(seats) seat\(seats == 1 ? "" : "s") · \(Formatters.ringgit(trip.pricePerSeatMyr * seats))"
            }
        }()
        return VPrimaryButton(label,
                              icon: "checkmark.seal.fill",
                              isLoading: bookState == .booking,
                              isEnabled: trip.isOpen && bookState != .booking && bookState != .success) {
            Task { await book(trip: trip) }
        }
    }

    // MARK: Actions

    private func load() async {
        loadError = nil
        do {
            trip = try await VoygoAPIClient.getLongHaulTrip(id: tripId)
            // Cap seat picker so we never offer more than the trip has.
            if let trip { seats = min(seats, max(1, min(trip.seatsAvailable, 8))) }
        } catch {
            loadError = AppError.from(error).localizedDescription
        }
    }

    private func book(trip: LongHaulTrip) async {
        // Idempotency guard. The CTA's `isEnabled: bookState != .booking`
        // gates the button visually, but two rapid taps before the
        // state propagates can both reach `book(trip:)` — and the
        // `Task { … }` wrapper is fire-and-forget. Re-entry here
        // is the last line of defense against a double-charge.
        guard bookState != .booking else { return }
        bookState = .booking
        let result = await store.bookLongHaul(tripId: trip.id, seats: seats)
        switch result {
        case .success(let response):
            // Live Billplz returns a hosted-checkout URL with status .pending;
            // mock-mode returns .paid and the checkout URL is nil.
            if let urlString = response.payment.paymentUrl,
               let url = URL(string: urlString),
               response.payment.status == .pending {
                pendingPaymentURL = url
                bookState = .success
            } else {
                bookState = .success
                onBooked()
            }
        case .failure(let err):
            bookState = .failure(err.localizedDescription)
        }
    }

    private func bindingForCheckout() -> Binding<URLHolder?> {
        Binding(
            get: { pendingPaymentURL.map(URLHolder.init) },
            set: { if $0 == nil { pendingPaymentURL = nil } }
        )
    }

    private func formatDeparture(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM · h:mm a"
        return f.string(from: date)
    }
}

private struct URLHolder: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Minimal SFSafariViewController wrapper. The same view also lives
/// in `PaymentCheckout.swift` as a `private struct`, hence this
/// duplicate — promoting it to `internal` is a separate cleanup.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDismiss() }
    }
}

#Preview("LongHaulTripDetailView") {
    LongHaulTripDetailView(tripId: "preview-trip", onBack: {})
        .environment(AppStore())
}
