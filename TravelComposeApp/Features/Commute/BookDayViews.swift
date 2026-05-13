import SwiftUI
import SafariServices

// MARK: - Book a single day
//
// "Schedule" tile on Home → book ONE day on a recurring route at
// 1× the seat price. Fills the gap between:
//   - Subscribe (recurring monthly commit, lower per-ride price)
//   - Solo (2× seat price, locks the whole car)
//
// Two screens, mirroring the Solo flow shape:
//   1. BookDayPickRouteView — list of routes → upcoming dates picker
//   2. BookDayConfirmView   — pulls a server quote (ride still
//                             bookable, real price), Confirm CTA
//
// Backend endpoint: POST /trips/:id/book-day. Same Billplz hosted-
// checkout pattern as solo + long-haul. Doesn't lock the car —
// other riders can still book remaining seats on the same instance.

struct BookDayPickRouteView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onPickRide: (_ rideInstanceId: String) -> Void
    /// Empty-state CTA: fresh user with no cached routes — bounce
    /// them into Search so the screen isn't a dead-end. Defaulted
    /// to a no-op for previews; HomeTab wires the real cross-tab nav.
    var onFindRoutes: () -> Void = {}

    @State private var hasLoaded = false
    @State private var expandedRouteId: String? = nil

    /// Routes the rider can day-book. Mirrors the Solo picker filter:
    /// ACTIVE routes only, sorted by driver name for a stable list.
    /// We surface every route — the rider doesn't need to have a
    /// subscription, that's the whole point of this flow.
    private var pickableRoutes: [RecurringRoute] {
        store.routes
            .filter { $0.activeStatus == .active }
            .sorted { $0.driverName < $1.driverName }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.bookDayPickTitle, onBack: onBack)
                explainerCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                if pickableRoutes.isEmpty && hasLoaded {
                    // Fresh user with zero cached routes. CTA goes to
                    // Search so they can find a route they like and
                    // come back to day-book it.
                    VStack(spacing: 16) {
                        Spacer()
                        EmptyStateView(
                            icon: "magnifyingglass",
                            title: S.bookDayEmptyTitle,
                            subtitle: S.bookDayEmptyBody
                        )
                        VPrimaryButton(S.bookDayBrowseRoutes) {
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
            Image(systemName: "calendar.badge.plus")
                .font(.body.weight(.heavy))
                .foregroundColor(VPalette.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(S.bookDayExplainerTitle)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(VPalette.text)
                Text(S.bookDayExplainerBody)
                    .font(.caption)
                    .foregroundColor(VPalette.textSec)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(VPalette.primaryContainer.opacity(0.5))
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
                // already solo'd. Server re-validates on confirm.
                ride.rideStatus == .scheduled && !ride.isSolo
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
                        // 1× seat price — distinguishes this flow
                        // from Solo's `route.pricePerSeat * 2`.
                        Text("\(route.departureTime) · \(Formatters.ringgit(route.pricePerSeat))/\(S.bookDaySeatSuffix)")
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
                    Text(S.bookDayNoDatesAvailable)
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
                Text(S.bookDayDepartsAt(time))
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

// MARK: - Book Day Confirm

struct BookDayConfirmView: View {
    let rideInstanceId: String
    var onBack: () -> Void
    var onBooked: (_ rideInstanceId: String) -> Void

    @Environment(AppStore.self) private var store

    @State private var isBooking = false
    @State private var errorMessage: String? = nil
    @State private var pendingPaymentURL: URL? = nil
    @State private var bookedRideInstanceId: String? = nil

    /// Local lookup — we don't need a server quote for this flow
    /// because the price is the route's own `pricePerSeat` (1× —
    /// no Solo multiplier, no daily-vs-monthly tier math). Server
    /// re-derives the authoritative amount at book time so the
    /// rider can't manipulate it via stale client state.
    private var ride: CommuteRideInstance? {
        store.rideInstances.first { $0.id == rideInstanceId }
    }
    private var route: RecurringRoute? {
        ride.flatMap { r in store.routes.first { $0.id == r.routeId } }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.bookDayConfirmTitle, onBack: onBack)
                ScrollView {
                    VStack(spacing: 16) {
                        if let route, let ride {
                            detailsCard(route: route, ride: ride)
                            policyCard
                            if let msg = errorMessage {
                                Text(msg)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(VPalette.danger)
                                    .padding(.horizontal, 16)
                            }
                        } else {
                            // Stale link / not in cache — degrade gracefully
                            // instead of rendering a broken page.
                            EmptyStateView(
                                icon: "questionmark.circle",
                                title: S.bookDayLoadFailed,
                                subtitle: S.sessionExpired
                            )
                            .padding(.top, 30)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, VTabBarLayout.clearance)
                }
            }

            if let route {
                VStack {
                    Spacer()
                    VPrimaryButton(
                        S.bookDayConfirmCTA(route.pricePerSeat),
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
        .sheet(item: bindingForCheckout()) { holder in
            BookDaySafariView(url: holder.url) {
                pendingPaymentURL = nil
                Task {
                    await store.refreshAll()
                    if let id = bookedRideInstanceId { onBooked(id) }
                }
            }
        }
    }

    private func bindingForCheckout() -> Binding<BookDayURLHolder?> {
        Binding(
            get: { pendingPaymentURL.map(BookDayURLHolder.init) },
            set: { if $0 == nil { pendingPaymentURL = nil } }
        )
    }

    @ViewBuilder
    private func detailsCard(route: RecurringRoute, ride: CommuteRideInstance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.startLocation)
                        .font(.callout.weight(.heavy))
                        .foregroundColor(VPalette.text)
                    Image(systemName: "arrow.down")
                        .font(.caption2.weight(.black))
                        .foregroundColor(VPalette.textHint)
                    Text(route.endLocation)
                        .font(.callout.weight(.heavy))
                        .foregroundColor(VPalette.text)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(S.bookDayDeparts)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(VPalette.textHint)
                    Text(route.departureTime)
                        .font(.body.weight(.black))
                        .foregroundColor(VPalette.primary)
                    Text(ride.date, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                        .font(.caption2)
                        .foregroundColor(VPalette.textSec)
                }
            }
            Divider().background(VPalette.border)
            HStack {
                Text(S.bookDaySeatPrice)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(VPalette.text)
                Spacer()
                Text(Formatters.ringgit(route.pricePerSeat))
                    .font(.body.weight(.black))
                    .foregroundColor(VPalette.primary)
            }
            if ride.seatAvailability <= 0 {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(VPalette.warning)
                    Text(S.bookDayNoSeatsLeft)
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

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.footnote.weight(.black))
                    .foregroundColor(VPalette.textSec)
                Text(S.bookDayWhatYouGetTitle)
                    .font(.footnote.weight(.black))
                    .foregroundColor(VPalette.text)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("• \(S.bookDayWhatYouGetSeat)")
                Text("• \(S.bookDayWhatYouGetDriver)")
                Text("• \(S.bookDayWhatYouGetNoCommit)")
            }
            .font(.caption)
            .foregroundColor(VPalette.textSec)
        }
        .padding(14)
        .background(VPalette.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func book() async {
        guard !isBooking else { return }
        isBooking = true
        errorMessage = nil
        defer { isBooking = false }
        do {
            let result = try await VoygoAPIClient.bookDay(rideInstanceId: rideInstanceId)
            bookedRideInstanceId = result.rideInstanceId
            switch result.payment.status {
            case .pending:
                if let urlString = result.payment.paymentUrl,
                   let url = URL(string: urlString) {
                    pendingPaymentURL = url
                    // sheet's onDismiss fires onBooked once Billplz returns
                    return
                } else {
                    errorMessage = S.bookDayPaymentCouldntStart
                    return
                }
            case .paid:
                await store.refreshAll()
                onBooked(result.rideInstanceId)
            case .failed, .refunded:
                errorMessage = S.bookDayPaymentDeclined
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Billplz checkout sheet support (mirror of SoloViews)

private struct BookDayURLHolder: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct BookDaySafariView: UIViewControllerRepresentable {
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

#Preview("BookDayPickRouteView (empty)") {
    NavigationStack {
        BookDayPickRouteView(onBack: {}, onPickRide: { _ in })
    }
    .environment(AppStore())
}
