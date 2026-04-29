import Foundation
import Combine

// MARK: - App Store (session + hybrid repository, mirrors Android AppGraph)

enum AppConnectionState: Equatable {
    case idle
    case syncing
    case online
    case offline(String)

    var bannerText: String? {
        switch self {
        case .idle:
            return nil
        case .syncing:
            return "Syncing latest commute data..."
        case .online:
            return nil
        case .offline(let message):
            return message
        }
    }

    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var phoneNumber = ""
    @Published var kycStatus: KycStatus = .notStarted
    @Published var currentUser = User(id: "", name: "", rating: 5.0)
    @Published private(set) var riderId = ""
    @Published private(set) var driverId = ""
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncError: String? = nil
    @Published private(set) var connectionState: AppConnectionState = .idle

    /// When the backend echoes a dev-mode OTP (no SMS provider configured), the
    /// OTP screen reads it from here to pre-fill the field so testing is painless.
    @Published var devOtpCode: String? = nil

    @Published var routes: [RecurringRoute] = []
    @Published var subscriptions: [RouteSubscription] = []
    @Published var rideInstances: [CommuteRideInstance] = []
    @Published var threads: [ChatThread] = []
    @Published var messages: [ChatMessage] = []

    /// Driver weekly payout statement. Populated by `refreshPayout()` from
    /// `/payouts/me`. Stays nil until the first sync (or if the call fails),
    /// in which case DriverPayoutsView falls back to its empty state.
    @Published var payout: PayoutStatement? = nil

    /// Recent payment history; populated by `refreshPayments()`.
    @Published var payments: [PaymentRecord] = []

    /// KYC document submissions for the signed-in user.
    @Published var kycDocuments: [KycDocument] = []

    /// Local mirror of cancellation events. The server is the source of truth
    /// (penalty math runs there too), but we cache reported ones so the
    /// rider's calendar can mark them and the driver's reliability bar can
    /// show pending penalties in the same session.
    @Published private(set) var cancellationRecords: [CancellationRecord] = []

    /// Last `PaymentChargeResult` returned from `startCharge`, kept so any
    /// downstream view can show a hosted-checkout URL or "PAID in mock
    /// mode" banner without the AppStore having to broadcast a new state.
    @Published private(set) var lastChargeResult: PaymentChargeResult? = nil

    /// Monotonic counter that views observe to know when to dismiss the
    /// in-app Billplz checkout. Bumped from `handlePaymentReturn(url:)`.
    /// A counter (vs a Bool) avoids a race where two checkouts in quick
    /// succession both observe the same true→true transition.
    @Published private(set) var checkoutDismissalSignal: Int = 0

    var useOnline = true

    /// True when the user entered via the DEBUG-only dev shortcut. Two
    /// effects: refresh methods skip server calls (`useOnline` is false),
    /// and `clearSession()` is a no-op so a stray 401 from any
    /// not-yet-gated method can't bounce the dev user back to the login
    /// screen. Cleared by the explicit `logout()` flow.
    private var isDevSession = false

    private enum SessionKeys {
        // Non-sensitive identifiers stay in UserDefaults so the UI can render
        // immediately on launch. The auth token itself lives in the Keychain.
        static let phone = "voygo.session.phone"
        static let displayName = "voygo.session.displayName"
        static let userId = "voygo.session.userId"
        static let kycStatus = "voygo.session.kycStatus"
    }

    init() {
        loadSession()
    }

    // MARK: - Auth

    func requestOtp(phone: String) async -> Result<Void, AppError> {
        let normalized = normalizePhone(phone)
        guard !normalized.isEmpty else { return .failure(.message("Enter your phone number")) }
        phoneNumber = normalized
        UserDefaults.standard.set(normalized, forKey: SessionKeys.phone)
        do {
            let response = try await VoygoAPIClient.requestOtp(phone: normalized)
            devOtpCode = response.devCode
            return .success(())
        } catch let error as APIError {
            return .failure(.message(error.localizedDescription))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    func verifyOtp(code: String) async -> Result<Void, AppError> {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 6 else { return .failure(.message("Enter the 6-digit code")) }
        guard !phoneNumber.isEmpty else { return .failure(.message("Phone number missing — go back and re-enter")) }
        do {
            let response = try await VoygoAPIClient.verifyOtp(phone: phoneNumber, code: trimmed)
            SessionStorage.authToken = response.token
            applyAuthenticatedUser(response.user)
            persistSession()
            isAuthenticated = true
            devOtpCode = nil
            await refreshAll()
            return .success(())
        } catch let error as APIError {
            return .failure(.message(error.localizedDescription))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    func logout() {
        // Explicit user action — bypass the dev-session guard so the user
        // can leave the dev shortcut state cleanly.
        isDevSession = false
        useOnline = true
        clearSession()
    }

#if DEBUG
    /// Development shortcut — bypasses the OTP round-trip and drops the app
    /// straight into the authenticated home screen. Only compiled into
    /// debug builds; the release binary cannot reach this code.
    ///
    /// The session is offline-only by design: `useOnline` is set to false so
    /// no refresh hits the backend, and `isDevSession` makes `clearSession()`
    /// a no-op so any stray 401 from a method that doesn't yet check
    /// `useOnline` can't bounce the user back to the login screen.
    func signInForDevelopment() {
        let id = "dev-\(Int.random(in: 1000...9999))"
        isDevSession = true
        useOnline = false
        riderId = id
        driverId = id
        phoneNumber = "+60 12-3456789"
        currentUser = User(id: id, name: "Dev User", rating: 4.9)
        kycStatus = .pending
        SessionStorage.authToken = "DEV"
        UserDefaults.standard.set(id, forKey: SessionKeys.userId)
        UserDefaults.standard.set(currentUser.name, forKey: SessionKeys.displayName)
        UserDefaults.standard.set(phoneNumber, forKey: SessionKeys.phone)
        UserDefaults.standard.set(kycStatus.rawValue, forKey: SessionKeys.kycStatus)
        isAuthenticated = true
        connectionState = .idle
        devOtpCode = nil
        // Seed enough in-memory data so the polished screens have something
        // to show. Keeps demo nav useful even though no backend is reachable.
        seedDevSampleData()
    }

    private func seedDevSampleData() {
        let pickup = RoutePoint(id: "pk-dev-1", label: "USJ 9 LRT", clusterId: "cluster-usj", lat: 3.0444, lng: 101.5860)
        let drop   = RoutePoint(id: "dp-dev-1", label: "KLCC Tower B", clusterId: "cluster-klcc", lat: 3.1571, lng: 101.7123)
        let route = RecurringRoute(
            id: "rr-dev-1",
            driverId: driverId,
            driverName: currentUser.name,
            startLocation: "Subang Jaya",
            endLocation: "KLCC, Kuala Lumpur",
            pickupPoints: [pickup],
            dropPoints: [drop],
            departureTime: "07:42",
            daysOfWeek: .weekdays,
            seatCount: 3,
            pricePerSeat: 14,
            carType: .ev,
            activeStatus: .active,
            reliability: DriverReliability(onTimeRate: 0.97, cancellationRate: 0.02, repeatRiders: 28, averageRating: 4.9)
        )
        routes = [route]
        let today = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 30, to: today) ?? today
        subscriptions = [
            RouteSubscription(
                id: "sub-dev-1", routeId: route.id, riderId: riderId, riderName: currentUser.name,
                startDate: today, endDate: end,
                selectedPickupPoint: pickup, selectedDropPoint: drop, status: .active
            )
        ]
        threads = [
            ChatThread(id: "thr-dev-1", tripId: route.id, title: "\(currentUser.name) · Subang → KLCC",
                       lastMessage: "See you at USJ 9 in 4 min", unreadCount: 0)
        ]
        regenerateRides()
    }
#endif

    /// Pulls the driver's current-week payout snapshot. Leaves `payout`
    /// untouched on error (DriverPayoutsView shows the cached value or its
    /// empty state).
    func refreshPayout() async {
        guard isAuthenticated else { return }
        do {
            payout = try await VoygoAPIClient.getMyPayout()
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // Non-fatal — keep last known payout if any.
        }
    }

    func refreshPayments() async {
        guard isAuthenticated else { return }
        do {
            payments = try await VoygoAPIClient.listMyPayments(limit: 30)
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // Non-fatal.
        }
    }

    /// Charges the rider for a subscription tier and returns the result so
    /// callers can either show a hosted-checkout sheet (Billplz live) or
    /// proceed straight to confirmation (mock mode). Result is also cached
    /// in `lastChargeResult` so peripheral views (Wallet hero, BookingConfirmed
    /// banner) can react without re-binding the in-flight task.
    func startCharge(
        subscriptionId: String?,
        routeId: String?,
        amountMyr: Int,
        tier: SubscriptionTier
    ) async -> Result<PaymentChargeResult, AppError> {
        guard isAuthenticated else { return .failure(.message("Sign in first")) }
        do {
            let result = try await VoygoAPIClient.chargeSubscription(
                subscriptionId: subscriptionId,
                routeId: routeId,
                amountMyr: amountMyr,
                tier: tier
            )
            lastChargeResult = result
            await refreshPayments()
            return .success(result)
        } catch APIError.unauthorized {
            clearSession()
            return .failure(.message("Your session has expired. Please sign in again."))
        } catch let error as APIError {
            return .failure(.message(error.localizedDescription))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    // MARK: - Cancellations

    /// Reports a cancellation to the backend and mirrors the resulting
    /// record locally. Penalty math runs server-side using the same policy
    /// engine; we just store what the server returns so views don't need a
    /// second round-trip to read it.
    @discardableResult
    func reportCancellation(
        rideInstanceId: String?,
        routeId: String,
        subscriptionId: String?,
        actor: CancellationActor,
        kind: CancellationKind,
        notes: String? = nil
    ) async -> Result<CancellationRecord, AppError> {
        guard isAuthenticated else { return .failure(.message("Sign in first")) }
        do {
            let payload = CancellationReportPayload(
                rideInstanceId: rideInstanceId,
                subscriptionId: subscriptionId,
                routeId: routeId,
                actor: actor.rawValue,
                kind: kind.rawValue,
                notes: notes
            )
            let response = try await VoygoAPIClient.reportCancellation(payload: payload)
            let record = CancellationRecord(
                id: response.id,
                rideInstanceId: rideInstanceId ?? "",
                subscriptionId: subscriptionId,
                routeId: routeId,
                actor: actor,
                kind: kind,
                reportedAt: Date(),
                resolvedAt: nil,
                penaltyAmount: response.penaltyMyr,
                notes: notes
            )
            cancellationRecords.append(record)
            // The penalty + status implications affect both the rider's
            // calendar and the driver's payout — kick off a sync so callers
            // see fresh data without orchestrating it themselves.
            Task {
                await refreshAll()
                await refreshPayout()
            }
            return .success(record)
        } catch APIError.unauthorized {
            clearSession()
            return .failure(.message("Your session has expired. Please sign in again."))
        } catch let error as APIError {
            return .failure(.message(error.localizedDescription))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    // MARK: - Payment return deep link

    /// Called by the app's `onOpenURL` handler when the rider returns from
    /// the Billplz hosted checkout via `voygo://payments/return?...`. Closes
    /// the loop opened in `startCharge`: dismisses any in-app checkout sheet,
    /// refreshes payments, and surfaces a success/failure banner. The actual
    /// PAID flip happens server-side via the Billplz webhook; this routine
    /// just brings the iOS state up to date eagerly.
    func handlePaymentReturn(url: URL) {
        guard url.scheme?.lowercased() == "voygo" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let paid = (items.first { $0.name == "paid" }?.value ?? "").lowercased() == "true"

        // Bump the dismissal counter so any presented checkout sheet observes
        // a transition and tears itself down.
        checkoutDismissalSignal &+= 1

        if paid {
            lastSyncError = nil
            connectionState = .online
        } else {
            // Don't classify "incomplete" as offline — the rider is online,
            // they just haven't paid. Keep the existing connection state and
            // surface the message via lastSyncError so the wallet/banner can
            // show it.
            lastSyncError = "Payment not completed. You can retry from the wallet."
        }

        Task { await refreshPayments() }
    }

    // MARK: - KYC

    func refreshKycDocuments() async {
        guard isAuthenticated else { return }
        do {
            kycDocuments = try await VoygoAPIClient.listKycDocuments()
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // Non-fatal.
        }
    }

    /// Uploads (or replaces) a single KYC document. The backend flips
    /// `kycStatus` to `.pending` on first submission so the rest of the UI
    /// reflects "under review" without a separate call.
    func submitKycDocument(kind: KycDocumentKind, storageUrl: String? = nil) async -> Result<Void, AppError> {
        guard isAuthenticated else { return .failure(.message("Sign in first")) }
        do {
            let response = try await VoygoAPIClient.uploadKycDocument(kind: kind, storageUrl: storageUrl)
            if let status = KycStatus(rawValue: response.kycStatus) {
                kycStatus = status
            }
            await refreshKycDocuments()
            return .success(())
        } catch APIError.unauthorized {
            clearSession()
            return .failure(.message("Your session has expired. Please sign in again."))
        } catch let error as APIError {
            return .failure(.message(error.localizedDescription))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    /// Convenience: rider-required vs driver-required completeness for a UI
    /// progress bar. Returns the ratio uploaded / required for the role.
    func kycCompletion(role: KycSubmission.Role) -> (uploaded: Int, required: Int) {
        let required = role == .driver ? KycDocumentKind.driverRequired : KycDocumentKind.riderRequired
        let uploadedKinds = Set(kycDocuments.map(\.kind))
        let uploaded = required.filter { uploadedKinds.contains($0) }.count
        return (uploaded, required.count)
    }

    func refreshMe() async {
        guard isAuthenticated else { return }
        do {
            let user = try await VoygoAPIClient.getMe()
            applyAuthenticatedUser(user)
            persistSession()
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // Non-fatal; leave the cached profile in place.
        }
    }

    func submitKyc(status: KycStatus) async -> Result<Void, AppError> {
        guard isAuthenticated else { return .failure(.message("Sign in first")) }
        do {
            let response = try await VoygoAPIClient.updateKyc(status: status)
            kycStatus = KycStatus(rawValue: response.kycStatus) ?? status
            UserDefaults.standard.set(kycStatus.rawValue, forKey: SessionKeys.kycStatus)
            return .success(())
        } catch APIError.unauthorized {
            clearSession()
            return .failure(.message("Your session has expired. Please sign in again."))
        } catch let error as APIError {
            return .failure(.message(error.localizedDescription))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    // MARK: - Sync

    func refreshAll() async {
        guard useOnline, isAuthenticated else { return }
        connectionState = .syncing
        isSyncing = true
        defer { isSyncing = false }
        do {
            async let driverRoutes = VoygoAPIClient.getDriverRoutes(driverId: driverId)
            async let riderSubscriptions = VoygoAPIClient.getRiderSubscriptions(riderId: riderId)
            async let chatThreads = VoygoAPIClient.getThreads()

            let remoteRoutes = try await driverRoutes.map { $0.toModel() }
            let remoteSubs = try await riderSubscriptions.map { $0.toModel() }
            let remoteThreads = try await chatThreads

            // Replace-on-success: the backend is the source of truth for the
            // logged-in user; merging with stale local state would re-introduce
            // ghost rows whose IDs were already removed server-side.
            var nextRoutes: [String: RecurringRoute] = [:]
            for route in remoteRoutes { nextRoutes[route.id] = route }
            // Subscriptions can reference routes the user doesn't drive; fetch
            // any missing ones so the subscription UI can resolve them.
            for sub in remoteSubs where nextRoutes[sub.routeId] == nil {
                if let route = try? await VoygoAPIClient.getRoute(id: sub.routeId).toModel() {
                    nextRoutes[route.id] = route
                }
            }
            routes = Array(nextRoutes.values)
            subscriptions = remoteSubs
            threads = remoteThreads

            await refreshCalendar()
            // Pull side data — these are best-effort and don't block the
            // primary refresh result.
            await refreshPayout()
            await refreshKycDocuments()
            lastSyncError = nil
            connectionState = .online
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            let message = "Using offline data. \(error.localizedDescription)"
            lastSyncError = message
            connectionState = .offline(message)
        }
    }

    func refreshRouteDetails(routeId: String) async {
        guard useOnline, isAuthenticated else { return }
        do {
            async let route = VoygoAPIClient.getRoute(id: routeId)
            async let routeRides = VoygoAPIClient.getRouteRides(routeId: routeId, fromDate: todayString(), days: 30)
            replaceRoute(try await route.toModel())
            let rides = try await routeRides.map { $0.toModel() }
            rideInstances = rideInstances.filter { $0.routeId != routeId } + rides
            // Subscriptions for routes the user doesn't own require driver auth;
            // the rider-side flow only needs *its* subscription, which is already
            // included in refreshAll.
            lastSyncError = nil
            connectionState = .online
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            lastSyncError = "Route loaded from offline data."
            connectionState = .offline("Route loaded from offline data.")
        }
    }

    func refreshCalendar(routeId: String? = nil) async {
        guard useOnline, isAuthenticated else { return }
        do {
            if let routeId {
                let rides = try await VoygoAPIClient.getRouteRides(routeId: routeId, fromDate: todayString(), days: 30).map { $0.toModel() }
                rideInstances = rideInstances.filter { $0.routeId != routeId } + rides
            } else {
                let items = try await VoygoAPIClient.getRiderCalendar(riderId: riderId, fromDate: todayString(), days: 30)
                for item in items where routes.first(where: { $0.id == item.routeId }) == nil {
                    if let route = try? await VoygoAPIClient.getRoute(id: item.routeId).toModel() {
                        replaceRoute(route)
                    }
                }
                // The /calendar endpoint returns calendar items, not full ride
                // instances — derive the ride list from active subscriptions.
                regenerateRides()
            }
            lastSyncError = nil
            connectionState = .online
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            regenerateRides()
            lastSyncError = "Calendar loaded from offline data."
            connectionState = .offline("Calendar loaded from offline data.")
        }
    }

    // MARK: - Derived selectors

    func mySubscriptions() -> [RouteSubscriptionWithRoute] {
        subscriptions
            .filter { $0.riderId == riderId }
            .compactMap { sub -> RouteSubscriptionWithRoute? in
                guard let route = routes.first(where: { $0.id == sub.routeId }) else { return nil }
                let next = rideInstances
                    .filter { $0.routeId == sub.routeId && $0.confirmedPassengers.contains(riderId) && $0.date >= Calendar.current.startOfDay(for: Date()) }
                    .sorted { $0.date < $1.date }
                    .first?.date
                return RouteSubscriptionWithRoute(subscription: sub, route: route, nextRideDate: next)
            }
    }

    func driverDashboards() -> [DriverRouteDashboard] {
        routes.filter { $0.driverId == driverId }.map { route in
            DriverRouteDashboard(
                route: route,
                subscribedRiders: subscriptions.filter { $0.routeId == route.id && $0.status == .active },
                upcomingRides: upcomingRides(routeId: route.id, days: 21)
            )
        }
    }

    func upcomingRides(routeId: String, days: Int = 30) -> [CommuteRideInstance] {
        let now = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        return rideInstances.filter { $0.routeId == routeId && $0.date >= now && $0.date <= end }.sorted { $0.date < $1.date }
    }

    func calendarItems(routeId: String? = nil) -> [CommuteRideCalendarItem] {
        let now = Calendar.current.startOfDay(for: Date())
        return rideInstances
            .filter { $0.date >= now && (routeId == nil || $0.routeId == routeId) }
            .sorted { $0.date < $1.date }
            .compactMap { ride in
                guard let route = routes.first(where: { $0.id == ride.routeId }) else { return nil }
                let sub = subscriptions.first { $0.routeId == route.id && $0.status == .active && (routeId != nil || $0.riderId == riderId) }
                guard let pickup = sub?.selectedPickupPoint ?? route.pickupPoints.first,
                      let drop   = sub?.selectedDropPoint  ?? route.dropPoints.first else { return nil }
                return CommuteRideCalendarItem(date: ride.date, routeId: route.id, driverName: route.driverName,
                                               startLocation: route.startLocation, endLocation: route.endLocation,
                                               pickupPoint: pickup, dropPoint: drop, rideStatus: ride.rideStatus)
            }
    }

    // MARK: - Mutations

    func findCommuteRoutes(homeLocation: String, officeLocation: String, earliestDeparture: String, latestDeparture: String,
                           homeLat: Double?, homeLng: Double?, officeLat: Double?, officeLng: Double?) async -> [CommuteRouteMatchResult] {
        if useOnline && isAuthenticated {
            do {
                let request = CommuteRouteSearchRequest(
                    riderId: riderId,
                    homeLocation: homeLocation,
                    officeLocation: officeLocation,
                    earliestDeparture: earliestDeparture,
                    latestDeparture: latestDeparture,
                    homeLat: homeLat,
                    homeLng: homeLng,
                    officeLat: officeLat,
                    officeLng: officeLng
                )
                let response = try await VoygoAPIClient.findCommuteRoutes(request: request)
                let matches = response.candidates.map { $0.toModel() }
                for match in matches { replaceRoute(match.route) }
                lastSyncError = nil
                connectionState = .online
                return matches
            } catch APIError.unauthorized {
                clearSession()
                return []
            } catch {
                lastSyncError = "Search used offline matching."
                connectionState = .offline("Search used offline matching.")
            }
        }

        let earliest = parseMinutes(earliestDeparture) ?? 7 * 60
        let latest = parseMinutes(latestDeparture) ?? 9 * 60 + 30
        return CommuteMatchingEngine.matchRoutes(
            riderId: riderId,
            homeLocation: homeLocation,
            officeLocation: officeLocation,
            homeLat: homeLat,
            homeLng: homeLng,
            officeLat: officeLat,
            officeLng: officeLng,
            earliestMinutes: earliest,
            latestMinutes: latest,
            routes: routes,
            subscriptions: subscriptions,
            rideInstances: rideInstances
        )
    }

    func subscribe(routeId: String, pickupId: String, dropId: String, days: Int) async -> Result<String, AppError> {
        guard isAuthenticated else { return .failure(.message("Sign in first")) }
        guard let route = routes.first(where: { $0.id == routeId }) else { return .failure(.message("Route not found")) }
        guard let pickup = route.pickupPoints.first(where: { $0.id == pickupId }) else { return .failure(.message("Pickup not found")) }
        guard let drop   = route.dropPoints.first(where: { $0.id == dropId })    else { return .failure(.message("Drop not found")) }
        let start = Calendar.current.startOfDay(for: Date())
        let end   = Calendar.current.date(byAdding: .day, value: max(days, 1) - 1, to: start) ?? start
        let overlap = subscriptions.contains {
            $0.routeId == routeId && $0.riderId == riderId && $0.status == .active
            && !($0.endDate < start || $0.startDate > end)
        }
        guard !overlap else { return .failure(.message("Already subscribed for these dates")) }
        let request = RouteSubscriptionRequest(
            routeId: routeId,
            riderId: riderId,
            riderName: currentUser.name,
            startDate: start,
            endDate: end,
            selectedPickupPointId: pickupId,
            selectedDropPointId: dropId
        )
        do {
            let response = try await VoygoAPIClient.subscribeToRoute(request: request)
            let id = response.subscriptionId ?? response.id ?? "sub-\(UUID().uuidString)"
            subscriptions.append(RouteSubscription(id: id, routeId: routeId, riderId: riderId, riderName: currentUser.name,
                                                   startDate: start, endDate: end, selectedPickupPoint: pickup,
                                                   selectedDropPoint: drop, status: .active))
            regenerateRides()
            return .success(id)
        } catch APIError.unauthorized {
            clearSession()
            return .failure(.message("Your session has expired. Please sign in again."))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    func updateSubscription(id: String, status: RouteSubscriptionStatus) async -> Result<Void, AppError> {
        guard let i = subscriptions.firstIndex(where: { $0.id == id }) else { return .failure(.message("Subscription not found")) }
        let oldStatus = subscriptions[i].status
        subscriptions[i].status = status
        regenerateRides()
        do {
            try await VoygoAPIClient.updateSubscriptionStatus(id: id, status: status.rawValue)
            lastSyncError = nil
            connectionState = .online
            return .success(())
        } catch APIError.unauthorized {
            subscriptions[i].status = oldStatus
            regenerateRides()
            clearSession()
            return .failure(.message("Your session has expired. Please sign in again."))
        } catch {
            subscriptions[i].status = oldStatus
            regenerateRides()
            connectionState = .offline("Could not update subscription online.")
            return .failure(.message(error.localizedDescription))
        }
    }

    func createRoute(startLocation: String, endLocation: String, departureTime: String,
                     seatCount: Int, pricePerSeat: Int, carType: CarType, daysOfWeek: DaysOfWeekFlags,
                     pickupNames: [String], dropNames: [String]) async -> Result<String, AppError> {
        guard isAuthenticated else { return .failure(.message("Sign in first")) }
        guard !startLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !endLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failure(.message("Start and destination required")) }
        guard parseTime(departureTime) != nil else { return .failure(.message("Invalid time format. Use HH:mm")) }
        guard seatCount > 0 else { return .failure(.message("Seat count must be > 0")) }
        guard pricePerSeat > 0 else { return .failure(.message("Price per seat must be > 0")) }

        let pickups = await makePoints(from: pickupNames, prefix: "pk", baseLat: 3.14, baseLng: 101.71)
        let drops   = await makePoints(from: dropNames,   prefix: "dp", baseLat: 3.16, baseLng: 101.73)
        let routePointInputs = pickups.map { CreateRecurringRouteRequest.RoutePointIn(label: $0.label, lat: $0.lat, lng: $0.lng, clusterId: $0.clusterId) }
        let dropPointInputs = drops.map { CreateRecurringRouteRequest.RoutePointIn(label: $0.label, lat: $0.lat, lng: $0.lng, clusterId: $0.clusterId) }
        let request = CreateRecurringRouteRequest(
            driverId: driverId,
            startLocation: startLocation,
            endLocation: endLocation,
            pickupPoints: routePointInputs,
            dropPoints: dropPointInputs,
            departureTime: departureTime,
            daysOfWeek: daysOfWeek.asDictionary,
            seatCount: seatCount,
            pricePerSeat: pricePerSeat,
            carType: carType.rawValue
        )
        do {
            let response = try await VoygoAPIClient.createRoute(request: request)
            let id = response.routeId ?? response.id ?? "rr-\(UUID().uuidString)"
            replaceRoute(RecurringRoute(id: id, driverId: driverId, driverName: currentUser.name,
                                        startLocation: startLocation, endLocation: endLocation,
                                        pickupPoints: pickups, dropPoints: drops, departureTime: departureTime,
                                        daysOfWeek: daysOfWeek, seatCount: seatCount, pricePerSeat: pricePerSeat,
                                        carType: carType, activeStatus: .active,
                                        reliability: DriverReliability(onTimeRate: 0.9, cancellationRate: 0.05, repeatRiders: 0, averageRating: 5.0)))
            regenerateRides()
            return .success(id)
        } catch APIError.unauthorized {
            clearSession()
            return .failure(.message("Your session has expired. Please sign in again."))
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    func setRouteActive(routeId: String, active: Bool) async -> Result<Void, AppError> {
        guard let i = routes.firstIndex(where: { $0.id == routeId }) else { return .failure(.message("Route not found")) }
        let oldStatus = routes[i].activeStatus
        routes[i].activeStatus = active ? .active : .paused
        regenerateRides()
        do {
            try await VoygoAPIClient.updateRouteStatus(routeId: routeId, active: active)
            lastSyncError = nil
            connectionState = .online
            return .success(())
        } catch APIError.unauthorized {
            routes[i].activeStatus = oldStatus
            regenerateRides()
            clearSession()
            return .failure(.message("Your session has expired. Please sign in again."))
        } catch {
            routes[i].activeStatus = oldStatus
            regenerateRides()
            connectionState = .offline("Could not update route status online.")
            return .failure(.message(error.localizedDescription))
        }
    }

    func updateRouteSchedule(routeId: String, departureTime: String, daysOfWeek: DaysOfWeekFlags) async -> Result<Void, AppError> {
        guard parseTime(departureTime) != nil else { return .failure(.message("Invalid time format")) }
        guard let i = routes.firstIndex(where: { $0.id == routeId }) else { return .failure(.message("Route not found")) }
        let oldTime = routes[i].departureTime
        let oldDays = routes[i].daysOfWeek
        routes[i].departureTime = departureTime
        routes[i].daysOfWeek = daysOfWeek
        regenerateRides()
        do {
            try await VoygoAPIClient.updateRouteSchedule(routeId: routeId, departureTime: departureTime, daysOfWeek: daysOfWeek)
            lastSyncError = nil
            connectionState = .online
            return .success(())
        } catch APIError.unauthorized {
            routes[i].departureTime = oldTime
            routes[i].daysOfWeek = oldDays
            regenerateRides()
            clearSession()
            return .failure(.message("Your session has expired. Please sign in again."))
        } catch {
            routes[i].departureTime = oldTime
            routes[i].daysOfWeek = oldDays
            regenerateRides()
            connectionState = .offline("Could not update schedule online.")
            return .failure(.message(error.localizedDescription))
        }
    }

    func refreshMessages(threadId: String) async {
        guard useOnline, isAuthenticated else { return }
        do {
            let remote = try await VoygoAPIClient.getMessages(threadId: threadId)
            messages.removeAll { $0.threadId == threadId }
            messages.append(contentsOf: remote)
            messages.sort { $0.timestamp < $1.timestamp }
            connectionState = .online
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // Leave cached messages in place.
        }
    }

    func sendMessage(threadId: String, text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(id: "m-\(UUID())", threadId: threadId, sender: .me, text: trimmed, timestamp: Date()))
        if let i = threads.firstIndex(where: { $0.id == threadId }) {
            threads[i].lastMessage = trimmed
            threads[i].unreadCount = 0
        }
        guard useOnline, isAuthenticated else { return }
        do {
            try await VoygoAPIClient.sendMessage(threadId: threadId, text: trimmed)
            lastSyncError = nil
            connectionState = .online
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            lastSyncError = "Message queued locally."
            connectionState = .offline("Message queued locally.")
        }
    }

    func messages(for threadId: String) -> [ChatMessage] {
        messages.filter { $0.threadId == threadId }.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private

    private func applyAuthenticatedUser(_ user: AuthUserDTO) {
        let id = user.id
        riderId = id
        driverId = id
        let displayName = user.displayName.isEmpty ? defaultDisplayName(for: user.phone) : user.displayName
        currentUser = User(id: id, name: displayName, rating: currentUser.rating > 0 ? currentUser.rating : 5.0)
        kycStatus = user.kyc
        if !user.phone.isEmpty {
            phoneNumber = user.phone
        }
    }

    private func clearSession() {
        // Stray 401s from the dev shortcut must not bounce the user back to
        // the login screen. The explicit `logout()` flow flips
        // `isDevSession` to false before calling clearSession, so this
        // guard only protects the auto-clear-on-401 paths.
        if isDevSession { return }

        SessionStorage.authToken = nil
        UserDefaults.standard.removeObject(forKey: SessionKeys.userId)
        UserDefaults.standard.removeObject(forKey: SessionKeys.displayName)
        UserDefaults.standard.removeObject(forKey: SessionKeys.kycStatus)
        UserDefaults.standard.removeObject(forKey: SessionKeys.phone)
        isAuthenticated = false
        phoneNumber = ""
        riderId = ""
        driverId = ""
        currentUser = User(id: "", name: "", rating: 5.0)
        kycStatus = .notStarted
        routes = []
        subscriptions = []
        rideInstances = []
        threads = []
        messages = []
        payments = []
        kycDocuments = []
        cancellationRecords = []
        payout = nil
        lastChargeResult = nil
        checkoutDismissalSignal = 0
        devOtpCode = nil
        connectionState = .idle
        lastSyncError = nil
    }

    private func loadSession() {
        guard let token = SessionStorage.authToken, !token.isEmpty else { return }
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: SessionKeys.userId) ?? ""
        guard !id.isEmpty else { return }
        riderId = id
        driverId = id
        let phone = defaults.string(forKey: SessionKeys.phone) ?? ""
        phoneNumber = phone
        let name = defaults.string(forKey: SessionKeys.displayName) ?? defaultDisplayName(for: phone)
        currentUser = User(id: id, name: name, rating: 5.0)
        if let raw = defaults.string(forKey: SessionKeys.kycStatus),
           let status = KycStatus(rawValue: raw) {
            kycStatus = status
        }
        isAuthenticated = true
    }

    private func persistSession() {
        let defaults = UserDefaults.standard
        defaults.set(riderId, forKey: SessionKeys.userId)
        defaults.set(currentUser.name, forKey: SessionKeys.displayName)
        defaults.set(phoneNumber, forKey: SessionKeys.phone)
        defaults.set(kycStatus.rawValue, forKey: SessionKeys.kycStatus)
    }

    private func replaceRoute(_ route: RecurringRoute) {
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes[index] = route
        } else {
            routes.append(route)
        }
    }

    private func regenerateRides(days: Int = 30) {
        let today = Calendar.current.startOfDay(for: Date())
        var generated: [CommuteRideInstance] = []
        for offset in 0..<days {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: today) else { continue }
            for route in routes where route.activeStatus == .active && route.daysOfWeek.enabled(for: date) {
                let activeSubs = subscriptions.filter {
                    $0.routeId == route.id && $0.status == .active && date >= $0.startDate && date <= $0.endDate
                }
                generated.append(CommuteRideInstance(
                    id: "\(route.id)-\(offset)", routeId: route.id, date: date,
                    seatAvailability: max(0, route.seatCount - activeSubs.count),
                    confirmedPassengers: activeSubs.map(\.riderId), rideStatus: .scheduled
                ))
            }
        }
        rideInstances = generated
    }

    private func makePoints(from names: [String], prefix: String, baseLat: Double, baseLng: Double) async -> [RoutePoint] {
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let values = cleaned.isEmpty ? ["Default stop"] : cleaned
        var points: [RoutePoint] = []
        for (i, name) in values.enumerated() {
            if let resolved = try? await VoygoLocationService.shared.resolveCoordinate(label: name) {
                points.append(RoutePoint(id: "\(prefix)-\(UUID())", label: name, clusterId: resolved.clusterId, lat: resolved.lat, lng: resolved.lng))
            } else {
                points.append(
                    RoutePoint(id: "\(prefix)-\(UUID())", label: name, clusterId: "cluster-\(prefix)-\(i)",
                               lat: baseLat + Double(i) * 0.01, lng: baseLng + Double(i) * 0.01)
                )
            }
        }
        return points
    }

    private func parseMinutes(_ text: String) -> Int? {
        guard let (h, m) = parseTime(text) else { return nil }
        return h * 60 + m
    }

    private func parseTime(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func defaultDisplayName(for phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        let suffix = digits.count >= 4 ? String(digits.suffix(4)) : digits
        return suffix.isEmpty ? "Voygo Rider" : "User \(suffix)"
    }

    private func normalizePhone(_ raw: String) -> String {
        let digits = raw.trimmingCharacters(in: .whitespacesAndNewlines).filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return "" }
        if digits.hasPrefix("+") { return digits }
        let local = digits.drop(while: { $0 == "0" })
        return "+60\(local)"
    }
}

// MARK: - Matching Engine (mirrors Android CommuteMatchingEngine.kt)

enum CommuteMatchingEngine {
    struct Policy {
        var recurringRiderWeight: Double = 0.35
        var minimalDetourWeight: Double  = 0.25
        var pickupClusterWeight: Double  = 0.20
        var reliabilityWeight: Double    = 0.20
    }

    static func matchRoutes(
        riderId: String, homeLocation: String, officeLocation: String,
        homeLat: Double?, homeLng: Double?, officeLat: Double?, officeLng: Double?,
        earliestMinutes: Int, latestMinutes: Int,
        routes: [RecurringRoute], subscriptions: [RouteSubscription], rideInstances: [CommuteRideInstance],
        policy: Policy = Policy()
    ) -> [CommuteRouteMatchResult] {
        let riderSubs = subscriptions.filter { $0.riderId == riderId }
        let riderClusters = Set(riderSubs.map(\.selectedPickupPoint.clusterId))
        let rideByRoute = Dictionary(grouping: rideInstances, by: \.routeId).mapValues { $0.min(by: { $0.date < $1.date }) }

        return routes
            .filter { route -> Bool in
                guard route.activeStatus == .active else { return false }
                guard let (h, m) = parseTime(route.departureTime) else { return false }
                let mins = h * 60 + m
                return mins >= earliestMinutes && mins <= latestMinutes
            }
            .map { route -> CommuteRouteMatchResult in
                let pickupDist = nearestDistance(originLat: homeLat, originLng: homeLng,
                                                  points: route.pickupPoints.map { ($0.lat, $0.lng) })
                               ?? estimateFromText(homeLocation, candidates: route.pickupPoints.map(\.label))
                let dropDist   = nearestDistance(originLat: officeLat, originLng: officeLng,
                                                  points: route.dropPoints.map { ($0.lat, $0.lng) })
                               ?? estimateFromText(officeLocation, candidates: route.dropPoints.map(\.label))
                let overlapScore   = computeOverlap(homeLat: homeLat, homeLng: homeLng,
                                                    officeLat: officeLat, officeLng: officeLng,
                                                    homeText: homeLocation, officeText: officeLocation, route: route)
                let detourMins     = ((pickupDist + dropDist) / 1000.0) * 2.8
                let recurring      = riderSubs.contains { $0.routeId == route.id && $0.status == .active }
                let clusterMatch   = route.pickupPoints.contains { riderClusters.contains($0.clusterId) }
                let reliability    = route.reliability.compositeScore
                let priceScore     = (1 - Double(route.pricePerSeat) / 400.0).clamped(to: 0...1)
                let seats          = rideByRoute[route.id]??.seatAvailability ?? route.seatCount
                let ranking =
                    (recurring ? policy.recurringRiderWeight : 0) +
                    (1 - (detourMins / 45.0).clamped(to: 0...1)) * policy.minimalDetourWeight +
                    (clusterMatch ? 1.0 : 0.0) * policy.pickupClusterWeight +
                    reliability * policy.reliabilityWeight +
                    overlapScore * 0.08 + priceScore * 0.06
                return CommuteRouteMatchResult(route: route, pickupDistanceMeters: pickupDist, reliabilityScore: reliability,
                                               routeOverlapScore: overlapScore, estimatedDetourMinutes: detourMins,
                                               recurringRiderPriority: recurring, availableSeats: seats, rankingScore: ranking)
            }
            .filter { $0.availableSeats > 0 }
            .sorted { lhs, rhs in
                if lhs.recurringRiderPriority != rhs.recurringRiderPriority { return lhs.recurringRiderPriority }
                if lhs.estimatedDetourMinutes != rhs.estimatedDetourMinutes { return lhs.estimatedDetourMinutes < rhs.estimatedDetourMinutes }
                return lhs.rankingScore > rhs.rankingScore
            }
    }

    // MARK: - Geo helpers (Haversine)
    private static func haversine(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat/2)*sin(dLat/2) + cos(lat1 * .pi/180)*cos(lat2 * .pi/180)*sin(dLng/2)*sin(dLng/2)
        return R * 2 * atan2(sqrt(a), sqrt(1-a))
    }
    private static func nearestDistance(originLat: Double?, originLng: Double?, points: [(Double, Double)]) -> Double? {
        guard let lat = originLat, let lng = originLng, !points.isEmpty else { return nil }
        return points.map { haversine(lat, lng, $0.0, $0.1) }.min()
    }
    private static func estimateFromText(_ input: String, candidates: [String]) -> Double {
        let sim = candidates.map { tokenSim(normalize(input), normalize($0)) }.max() ?? 0
        return max(150, 9000 * (1 - sim))
    }
    private static func computeOverlap(homeLat: Double?, homeLng: Double?, officeLat: Double?, officeLng: Double?,
                                        homeText: String, officeText: String, route: RecurringRoute) -> Double {
        if let hLat = homeLat, let hLng = homeLng, let oLat = officeLat, let oLng = officeLng {
            let sd = nearestDistance(originLat: hLat, originLng: hLng, points: route.pickupPoints.map { ($0.lat, $0.lng) }) ?? 9000
            let ed = nearestDistance(originLat: oLat, originLng: oLng, points: route.dropPoints.map { ($0.lat, $0.lng) }) ?? 9000
            return (((1 - (sd / 12000)).clamped(to: 0...1) + (1 - (ed / 12000)).clamped(to: 0...1)) / 2).clamped(to: 0...1)
        }
        let startSim = ([route.startLocation] + route.pickupPoints.map(\.label)).map { tokenSim(normalize(homeText), normalize($0)) }.max() ?? 0
        let endSim   = ([route.endLocation]   + route.dropPoints.map(\.label)).map   { tokenSim(normalize(officeText), normalize($0)) }.max() ?? 0
        return ((startSim + endSim) / 2).clamped(to: 0...1)
    }
    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted).joined(separator: " ")
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static func tokenSim(_ a: String, _ b: String) -> Double {
        let ta = Set(a.split(separator: " ").map(String.init))
        let tb = Set(b.split(separator: " ").map(String.init))
        guard !ta.isEmpty && !tb.isEmpty else { return 0 }
        let intersection = ta.intersection(tb).count
        let union = ta.union(tb).count
        let jaccard = union == 0 ? 0.0 : Double(intersection) / Double(union)
        let lenPenalty = min(abs(a.count - b.count), 30).asDouble / 30.0
        return (jaccard * 0.85 + (1 - lenPenalty) * 0.15).clamped(to: 0...1)
    }
    private static func parseTime(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (h, m)
    }
}

extension Int {
    var asDouble: Double { Double(self) }
}

// MARK: - App Error

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}
