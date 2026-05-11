import SwiftUI

// MARK: - Solo seat
//
// "Solo seat" lets a rider claim the WHOLE car for a specific day's
// ride at 2× the seat price. Same trusted driver, same route, just
// no other passengers. Designed to keep occasional-private revenue
// inside Voygo instead of bouncing the rider to Grab on days they
// want privacy / can't share / are running late.
//
// Two screens:
//   1. SoloPickRouteView   — list of the rider's available routes;
//                            tapping a route drills into upcoming
//                            ride instances. Tap a ride → confirm.
//   2. SoloConfirmView     — pulls a server-authoritative quote and
//                            shows the price + policy + Confirm CTA.
//
// Both views go through AppRoute (.soloPick / .soloConfirm) so they
// pick up the standard nav-stack + tab-bar layout.

struct SoloPickRouteView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onPickRide: (_ rideInstanceId: String) -> Void
    /// Empty-state action: a fresh user with no cached routes
    /// taps "Find a route" → caller switches to Search tab so they
    /// can pick one then come back to book solo. Defaulted to a
    /// no-op for previews; HomeTab wires the real cross-tab nav.
    var onFindRoutes: () -> Void = {}

    @State private var hasLoaded = false
    @State private var expandedRouteId: String? = nil

    /// Routes the rider can solo-book. We surface ACTIVE routes the
    /// app already knows about — riders typically solo-book on routes
    /// they've subscribed to or favourited, so seeding the picker
    /// from the local cache is fast and matches expectation.
    private var pickableRoutes: [RecurringRoute] {
        store.routes
            .filter { $0.activeStatus == .active }
            .sorted { $0.driverName < $1.driverName }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Ride solo", onBack: onBack)
                explainerCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                if pickableRoutes.isEmpty && hasLoaded {
                    // Fresh user with zero cached routes. Send them to
                    // Search — without this CTA the screen is a dead
                    // end and the rider bounces.
                    VStack(spacing: 16) {
                        Spacer()
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: "Find a route first",
                            subtitle: "Solo rides are upgrades on existing carpool routes — find one you like, then book any day exclusively."
                        )
                        VPrimaryButton("Browse routes") {
                            onFindRoutes()
                        }
                        .padding(.horizontal, 32)
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                } else if pickableRoutes.isEmpty {
                    ScrollView { loadingSkeletons }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(pickableRoutes) { route in
                                routeRow(route)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, VTabBarLayout.clearance)
                    }
                    .refreshable { await store.refreshAll() }
                }
            }
        }
        .task {
            await store.refreshAll()
            hasLoaded = true
        }
    }

    private var explainerCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.fill.checkmark")
                .font(.body.weight(.heavy))
                .foregroundColor(VPalette.accentCoral)
            VStack(alignment: .leading, spacing: 4) {
                Text("Book the whole car")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(VPalette.text)
                Text("Pay ~2× the seat price for an exclusive ride. Same trusted driver, no other passengers, no detours.")
                    .font(.caption)
                    .foregroundColor(VPalette.textSec)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(VPalette.accentCoralContainer.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var loadingSkeletons: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    VSkeleton(height: 18)
                    VSkeleton(height: 14)
                }
                .padding(14)
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private func routeRow(_ route: RecurringRoute) -> some View {
        let isExpanded = expandedRouteId == route.id
        let rides = store.upcomingRides(routeId: route.id, days: 14)
            .filter { ride in
                // Only show rides that are still scheduled and not
                // already solo'd / past their depart time. Server
                // re-validates on confirm.
                ride.rideStatus == .scheduled
            }
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    expandedRouteId = isExpanded ? nil : route.id
                }
            } label: {
                HStack(spacing: 12) {
                    VAvatar(initial: String(route.driverName.prefix(1)), size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(route.driverName)
                            .font(.subheadline.weight(.black))
                            .foregroundColor(VPalette.text)
                        Text("\(route.startLocation) → \(route.endLocation)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(VPalette.textSec)
                            .lineLimit(1)
                        Text("\(route.departureTime) · RM \(route.pricePerSeat * 2)/solo")
                            .font(.caption2)
                            .foregroundColor(VPalette.textHint)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.heavy))
                        .foregroundColor(VPalette.textHint)
                }
                .padding(14)
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if isExpanded {
                if rides.isEmpty {
                    Text("No upcoming dates in the next 2 weeks.")
                        .font(.caption)
                        .foregroundColor(VPalette.textHint)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(rides.prefix(7)) { ride in
                            Button { onPickRide(ride.id) } label: {
                                rideDateRow(date: ride.date, time: route.departureTime)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private func rideDateRow(date: Date, time: String) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(date, format: .dateTime.day())
                    .font(.callout.weight(.black))
                    .foregroundColor(VPalette.text)
                Text(date, format: .dateTime.month(.abbreviated))
                    .font(.caption2.weight(.bold))
                    .foregroundColor(VPalette.textHint)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.weekday(.wide))
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(VPalette.text)
                Text("Departs \(time)")
                    .font(.caption2)
                    .foregroundColor(VPalette.textHint)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.heavy))
                .foregroundColor(VPalette.textHint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(VPalette.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 8)
    }
}

// MARK: - Solo Confirm

struct SoloConfirmView: View {
    let rideInstanceId: String
    var onBack: () -> Void
    var onBooked: (_ rideInstanceId: String) -> Void

    @Environment(AppStore.self) private var store

    @State private var loadState: LoadState = .loading
    @State private var quote: SoloQuoteResponse? = nil
    @State private var isBooking = false
    @State private var errorMessage: String? = nil

    enum LoadState { case loading, ready, failed(String) }

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Confirm solo ride", onBack: onBack)
                ScrollView {
                    VStack(spacing: 16) {
                        switch loadState {
                        case .loading:
                            ProgressView()
                                .padding(.top, 60)
                        case .failed(let msg):
                            EmptyStateView(
                                icon: "exclamationmark.triangle",
                                title: "Couldn't load this ride",
                                subtitle: msg
                            )
                            .padding(.top, 30)
                        case .ready:
                            if let q = quote { detailsCard(q) }
                            if let q = quote { policyCard(q.cancellationPolicy) }
                            if let msg = errorMessage {
                                Text(msg)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(VPalette.danger)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, VTabBarLayout.clearance)
                }
            }

            if case .ready = loadState, let q = quote, q.available {
                VStack {
                    Spacer()
                    VPrimaryButton(
                        "Confirm — RM \(q.soloPriceMyr)",
                        isLoading: isBooking,
                        isEnabled: !isBooking
                    ) {
                        Task { await book() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, VTabBarLayout.clearance + 6)
                }
            }
        }
        .task { await loadQuote() }
    }

    @ViewBuilder
    private func detailsCard(_ q: SoloQuoteResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(q.startLocation)
                        .font(.callout.weight(.heavy))
                        .foregroundColor(VPalette.text)
                    Image(systemName: "arrow.down")
                        .font(.caption2.weight(.black))
                        .foregroundColor(VPalette.textHint)
                    Text(q.endLocation)
                        .font(.callout.weight(.heavy))
                        .foregroundColor(VPalette.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Departs")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(VPalette.textHint)
                    Text(q.departureTime)
                        .font(.body.weight(.black))
                        .foregroundColor(VPalette.primary)
                    Text(q.date)
                        .font(.caption2)
                        .foregroundColor(VPalette.textSec)
                }
            }
            Divider().background(VPalette.border)
            HStack {
                Text("Seat price")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(VPalette.textSec)
                Spacer()
                Text("RM \(q.pricePerSeatMyr)")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(VPalette.textSec)
            }
            HStack {
                Text("Solo (×\(q.soloMultiplier))")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(VPalette.text)
                Spacer()
                Text("RM \(q.soloPriceMyr)")
                    .font(.body.weight(.black))
                    .foregroundColor(VPalette.primary)
            }
            if !q.available {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(VPalette.warning)
                    Text(unavailableMessage(for: q.reason ?? ""))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(VPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(VPalette.warning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .background(VPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func policyCard(_ p: SoloCancelPolicy) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.footnote.weight(.black))
                    .foregroundColor(VPalette.textSec)
                Text("Cancellation policy")
                    .font(.footnote.weight(.black))
                    .foregroundColor(VPalette.text)
            }
            policyRow("Cancel ≥ \(p.fullRefundUntilHours)h before depart", "Full refund")
            policyRow("Cancel ≥ \(p.halfRefundUntilHours)h before depart", "50% refund")
            policyRow("Cancel < \(p.halfRefundUntilHours)h before depart", "No refund")
        }
        .padding(14)
        .background(VPalette.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func policyRow(_ left: String, _ right: String) -> some View {
        HStack {
            Text(left)
                .font(.caption)
                .foregroundColor(VPalette.textSec)
            Spacer()
            Text(right)
                .font(.caption.weight(.bold))
                .foregroundColor(VPalette.text)
        }
    }

    private func unavailableMessage(for reason: String) -> String {
        switch reason {
        case "ride_not_scheduled":               return "This ride is no longer scheduled."
        case "ride_in_past":                     return "This ride has already departed."
        case "already_solo_booked":              return "Another rider booked this ride solo."
        case "you_already_solo_booked":          return "You already booked this ride solo."
        case "other_passengers_already_booked":  return "Other riders already booked seats — solo is unavailable for this day."
        default:                                 return "This ride is unavailable for solo booking."
        }
    }

    private func loadQuote() async {
        loadState = .loading
        do {
            let q = try await VoygoAPIClient.soloQuote(rideInstanceId: rideInstanceId)
            quote = q
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func book() async {
        guard let q = quote, q.available, !isBooking else { return }
        isBooking = true
        errorMessage = nil
        defer { isBooking = false }
        do {
            let result = try await VoygoAPIClient.soloBook(rideInstanceId: rideInstanceId)
            // Refresh local state so the calendar reflects the new
            // exclusive booking on next render.
            await store.refreshAll()
            onBooked(result.rideInstanceId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview("SoloPickRouteView (empty)") {
    NavigationStack {
        SoloPickRouteView(onBack: {}, onPickRide: { _ in })
    }
    .environment(AppStore())
}
