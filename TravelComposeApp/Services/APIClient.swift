import Foundation
import os.log

/// DEBUG-only diagnostics channel for the HTTP client. Production builds
/// see only the privacy-public fields explicitly emitted; response
/// bodies are gated behind `#if DEBUG` and pass through `errorSnippet`
/// for token redaction.
private let apiLog = Logger(subsystem: "app.voygo", category: "api")

private extension DecodingError {
    /// Compact, single-line description suitable for os_log. We keep
    /// the path + debug description and drop the underlying error
    /// (it tends to be very long and wraps to the prior context).
    var shortDescription: String {
        switch self {
        case .typeMismatch(let type, let ctx):
            return "typeMismatch \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)"
        case .valueNotFound(let type, let ctx):
            return "valueNotFound \(type) at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)"
        case .keyNotFound(let key, let ctx):
            return "keyNotFound \(key.stringValue) at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)"
        case .dataCorrupted(let ctx):
            return "dataCorrupted at \(ctx.codingPath.map(\.stringValue).joined(separator: ".")): \(ctx.debugDescription)"
        @unknown default:
            return "decoding error: \(localizedDescription)"
        }
    }
}

// MARK: - API Client (mirrors Android ApiService.kt)

struct VoygoAPIClient {
    static var baseURL: URL {
        get { AppConfiguration.apiBaseURL }
        set { AppConfiguration.setAPIBaseURLOverride(newValue) }
    }

    private static var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }

    // MARK: - Auth

    static func requestOtp(phone: String) async throws -> RequestOtpResponse {
        let body = RequestOtpRequest(phone: phone)
        return try await post(body, to: baseURL.appendingPathComponent("auth/request-otp"), as: RequestOtpResponse.self)
    }

    static func verifyOtp(phone: String, code: String) async throws -> VerifyOtpResponse {
        let body = VerifyOtpRequest(phone: phone, code: code)
        return try await post(body, to: baseURL.appendingPathComponent("auth/verify-otp"), as: VerifyOtpResponse.self)
    }

    static func getMe() async throws -> AuthUserDTO {
        try await get(baseURL.appendingPathComponent("auth/me"), as: AuthUserDTO.self)
    }

    /// Submits the user's uploaded KYC documents for review. Server
    /// flips status to PENDING; APPROVED/REJECTED are admin-only and
    /// not reachable from this client. Renamed from `updateKyc(status:)`
    /// — the previous name implied the client could pick a target
    /// state (including APPROVED), which it explicitly cannot.
    static func submitKycForReview() async throws -> KycResponse {
        let body = EmptyRequest()
        return try await post(body, to: baseURL.appendingPathComponent("users/me/kyc/submit"), as: KycResponse.self)
    }

    static func updateDisplayName(_ name: String) async throws {
        let body = UpdateDisplayNameRequest(displayName: name)
        _ = try await putVoid(body, to: baseURL.appendingPathComponent("users/me"))
    }

    // MARK: - Privacy & Security
    //
    // Backs the Profile → Privacy & Security screen. All four
    // surfaces required for App Store 5.1.1(v) + Malaysia PDPA:
    //   - read/write toggles (push, phone-visibility, biometric)
    //   - block list (list/add/remove)
    //   - account deletion
    //   - data export request

    static func getPreferences() async throws -> UserPreferencesDTO {
        try await get(baseURL.appendingPathComponent("users/me/preferences"), as: UserPreferencesDTO.self)
    }

    static func updatePreferences(_ patch: UpdatePreferencesRequest) async throws {
        _ = try await putVoid(patch, to: baseURL.appendingPathComponent("users/me/preferences"))
    }

    static func listBlocks() async throws -> [BlockedUserDTO] {
        try await get(baseURL.appendingPathComponent("users/me/blocks"), as: [BlockedUserDTO].self)
    }

    static func addBlock(userId: String, reason: String? = nil) async throws {
        let body = AddBlockRequest(userId: userId, reason: reason)
        _ = try await postVoid(body, to: baseURL.appendingPathComponent("users/me/blocks"))
    }

    static func removeBlock(userId: String) async throws {
        // URL-encode in case targetId ever contains anything unsafe;
        // current ids are UUID strings but defending against future
        // schema changes is cheap.
        let safe = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let url = baseURL.appendingPathComponent("users/me/blocks/\(safe)")
        let req = authedRequest(url, method: "DELETE")
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
    }

    /// Schedules account deletion. Server soft-deletes immediately and
    /// returns a `scheduledFor` 30 days out. iOS clears the JWT after
    /// this call so subsequent requests 401.
    static func deleteAccount() async throws -> DeleteAccountResponse {
        try await post(EmptyRequest(), to: baseURL.appendingPathComponent("users/me/delete"), as: DeleteAccountResponse.self)
    }

    /// PDPA right of access — server queues a data-export email job.
    static func requestDataExport() async throws -> DataExportResponse {
        try await post(EmptyRequest(), to: baseURL.appendingPathComponent("users/me/data-export"), as: DataExportResponse.self)
    }

    /// Sets the driver's vehicle identity on their profile. Returns
    /// the trimmed/saved values so the client can store exactly what
    /// the server persisted (e.g. server may strip trailing spaces).
    /// Empty strings clear the field on the server side.
    static func updateVehicle(plate: String, color: String, model: String) async throws -> UpdateVehicleResponse {
        let body = UpdateVehicleRequest(plateNumber: plate, carColor: color, carModel: model)
        return try await put(body, to: baseURL.appendingPathComponent("users/me/vehicle"), as: UpdateVehicleResponse.self)
    }

    // MARK: - KYC documents (Trust.swift)

    static func listKycDocuments() async throws -> [KycDocument] {
        try await get(baseURL.appendingPathComponent("users/me/kyc-documents"), as: [KycDocument].self)
    }

    static func uploadKycDocument(kind: KycDocumentKind, storageUrl: String?) async throws -> UploadKycDocumentResponse {
        let body = UploadKycDocumentRequest(kind: kind.rawValue, storageUrl: storageUrl)
        return try await post(body, to: baseURL.appendingPathComponent("users/me/kyc-documents"), as: UploadKycDocumentResponse.self)
    }

    // MARK: - Payments + payouts

    /// Charge a subscription. Server derives the amount from the
    /// route × tier × days; the client no longer sends a trusted
    /// `amountMyr`. `days` is optional metadata — backend falls back
    /// to the subscription's date range when omitted.
    static func chargeSubscription(
        subscriptionId: String,
        tier: SubscriptionTier,
        days: Int? = nil
    ) async throws -> PaymentChargeResult {
        let body = ChargeSubscriptionRequest(
            subscriptionId: subscriptionId,
            tier: tier.rawValue,
            days: days
        )
        return try await post(body, to: baseURL.appendingPathComponent("payments/charge"), as: PaymentChargeResult.self)
    }

    static func listMyPayments(limit: Int = 20) async throws -> [PaymentRecord] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("payments/me"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        return try await get(comps.url!, as: [PaymentRecord].self)
    }

    static func getMyPayout() async throws -> PayoutStatement {
        try await get(baseURL.appendingPathComponent("payouts/me"), as: PayoutStatement.self)
    }

    // MARK: - Cancellations

    /// Reports a ride cancellation. The backend re-runs the policy engine
    /// server-side (driver late-cancel count from cancellation_records) and
    /// returns the authoritative penalty so a malicious client can't downplay
    /// its own driver's no-show fee.
    static func reportCancellation(payload: CancellationReportPayload) async throws -> CancellationReportResponse {
        try await post(payload, to: baseURL.appendingPathComponent("cancellations"), as: CancellationReportResponse.self)
    }

    // MARK: - Bookings, reviews

    static func skipRide(rideInstanceId: String) async throws -> SkipRideResponse {
        try await post(EmptyRequest(), to: baseURL.appendingPathComponent("trips/\(rideInstanceId)/skip"), as: SkipRideResponse.self)
    }

    static func bookRide(rideInstanceId: String) async throws -> RideBooking {
        try await post(EmptyRequest(), to: baseURL.appendingPathComponent("trips/\(rideInstanceId)/book"), as: RideBooking.self)
    }

    static func listMyBookings() async throws -> [RideBooking] {
        try await get(baseURL.appendingPathComponent("bookings/me"), as: [RideBooking].self)
    }

    // MARK: - Solo seat
    //
    // "Solo seat" lets a rider pay ~2x the normal seat price to claim
    // the entire car for a specific day's ride. The driver doesn't
    // pick up any other passengers that day. Server is authoritative
    // for price + availability — never compute or trust client price.

    /// Returns whether `rideInstanceId` can be solo-booked + the
    /// server-derived price. Render the confirm sheet using THIS
    /// price, not a locally-multiplied one.
    static func soloQuote(rideInstanceId: String) async throws -> SoloQuoteResponse {
        try await get(
            baseURL.appendingPathComponent("commute/rides/\(rideInstanceId)/solo-quote"),
            as: SoloQuoteResponse.self
        )
    }

    /// Atomically claims the ride + kicks off the charge. Returns the
    /// payment record (BillPlz URL in prod, mock paid in dev/staging).
    static func soloBook(rideInstanceId: String) async throws -> SoloBookResponse {
        try await post(
            EmptyRequest(),
            to: baseURL.appendingPathComponent("commute/rides/\(rideInstanceId)/solo-book"),
            as: SoloBookResponse.self
        )
    }

    /// Cancels the caller's own solo booking. Refund tier is computed
    /// server-side based on hours-to-departure (>=12h full, >=2h half,
    /// otherwise none) — UI surfaces the value from the response, not
    /// a locally-computed estimate.
    static func soloCancel(rideInstanceId: String) async throws -> SoloCancelResponse {
        try await post(
            EmptyRequest(),
            to: baseURL.appendingPathComponent("commute/rides/\(rideInstanceId)/solo-cancel"),
            as: SoloCancelResponse.self
        )
    }

    static func submitReview(_ request: RideReviewRequest) async throws -> IdResponse {
        try await post(request, to: baseURL.appendingPathComponent("reviews"), as: IdResponse.self)
    }

    /// Corridor-aware suggestions — learns from what real drivers
    /// + riders have used as pickups/drops on similar routes. Goes
    /// IN FRONT of MapKit suggestions so the rail self-improves
    /// over time.
    ///
    /// At least one of (origin, dest) coords must be supplied. When
    /// both are supplied, server filters to routes that have a pickup
    /// near origin AND a drop near dest — strongest match. With one
    /// coord, the filter relaxes to "near the known coord".
    static func corridorSuggestions(
        kind: CorridorSuggestionKind,
        originLat: Double?, originLng: Double?,
        destLat: Double?, destLng: Double?
    ) async throws -> [CorridorSuggestion] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("commute/corridor-suggestions"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = [URLQueryItem(name: "kind", value: kind.rawValue)]
        if let lat = originLat, let lng = originLng {
            items.append(URLQueryItem(name: "originLat", value: String(lat)))
            items.append(URLQueryItem(name: "originLng", value: String(lng)))
        }
        if let lat = destLat, let lng = destLng {
            items.append(URLQueryItem(name: "destLat", value: String(lat)))
            items.append(URLQueryItem(name: "destLng", value: String(lng)))
        }
        components.queryItems = items
        return try await get(components.url!, as: [CorridorSuggestion].self)
    }

    // GET /places/autocomplete
    static func autocompletePlaces(query: String, lat: Double?, lon: Double?) async throws -> [PlaceSuggestion] {
        var components = URLComponents(url: baseURL.appendingPathComponent("places/autocomplete"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "8")]
        if let lat { items.append(URLQueryItem(name: "lat", value: String(lat))) }
        if let lon { items.append(URLQueryItem(name: "lon", value: String(lon))) }
        components.queryItems = items
        return try await get(components.url!, as: [PlaceSuggestion].self)
    }

    // POST /commute/search
    static func findCommuteRoutes(request: CommuteRouteSearchRequest) async throws -> CommuteRouteMatchResponse {
        try await post(request, to: baseURL.appendingPathComponent("commute/search"), as: CommuteRouteMatchResponse.self)
    }

    // GET /commute/routes/{id}
    static func getRoute(id: String) async throws -> RecurringRouteDTO {
        try await get(baseURL.appendingPathComponent("commute/routes/\(id)"), as: RecurringRouteDTO.self)
    }

    // GET /commute/routes/{id}/subscriptions
    static func getRouteSubscriptions(routeId: String) async throws -> [RouteSubscriptionDTO] {
        try await get(baseURL.appendingPathComponent("commute/routes/\(routeId)/subscriptions"), as: [RouteSubscriptionDTO].self)
    }

    // GET /commute/routes/{id}/rides
    static func getRouteRides(routeId: String, fromDate: String, days: Int) async throws -> [CommuteRideInstanceDTO] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("commute/routes/\(routeId)/rides"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "fromDate", value: fromDate), URLQueryItem(name: "days", value: String(days))]
        return try await get(comps.url!, as: [CommuteRideInstanceDTO].self)
    }

    // POST /commute/subscriptions
    static func subscribeToRoute(request: RouteSubscriptionRequest) async throws -> IdResponse {
        try await post(request, to: baseURL.appendingPathComponent("commute/subscriptions"), as: IdResponse.self)
    }

    // PUT /commute/subscriptions/{id}/status
    static func updateSubscriptionStatus(id: String, status: String) async throws {
        let body = UpdateSubscriptionStatusRequest(status: status)
        _ = try await putVoid(body, to: baseURL.appendingPathComponent("commute/subscriptions/\(id)/status"))
    }

    // GET /commute/subscriptions/rider/{riderId}
    static func getRiderSubscriptions(riderId: String) async throws -> [RouteSubscriptionDTO] {
        try await get(baseURL.appendingPathComponent("commute/subscriptions/rider/\(riderId)"), as: [RouteSubscriptionDTO].self)
    }

    // GET /commute/riders/{riderId}/calendar
    static func getRiderCalendar(riderId: String, fromDate: String, days: Int) async throws -> [CommuteRideCalendarItemDTO] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("commute/riders/\(riderId)/calendar"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "fromDate", value: fromDate), URLQueryItem(name: "days", value: String(days))]
        return try await get(comps.url!, as: [CommuteRideCalendarItemDTO].self)
    }

    // GET /commute/routes/driver/{driverId}
    static func getDriverRoutes(driverId: String) async throws -> [RecurringRouteDTO] {
        try await get(baseURL.appendingPathComponent("commute/routes/driver/\(driverId)"), as: [RecurringRouteDTO].self)
    }

    // POST /commute/routes
    static func createRoute(request: CreateRecurringRouteRequest) async throws -> IdResponse {
        try await post(request, to: baseURL.appendingPathComponent("commute/routes"), as: IdResponse.self)
    }

    // PUT /commute/routes/{id}/status
    static func updateRouteStatus(routeId: String, active: Bool) async throws {
        let body = UpdateRouteActiveStatusRequest(activeStatus: active)
        _ = try await putVoid(body, to: baseURL.appendingPathComponent("commute/routes/\(routeId)/status"))
    }

    // PUT /commute/routes/{id}/schedule
    static func updateRouteSchedule(routeId: String, departureTime: String, daysOfWeek: DaysOfWeekFlags) async throws {
        let body = UpdateRouteScheduleRequest(departureTime: departureTime, daysOfWeek: daysOfWeek.asDictionary)
        _ = try await putVoid(body, to: baseURL.appendingPathComponent("commute/routes/\(routeId)/schedule"))
    }

    // GET /chats/threads
    static func getThreads() async throws -> [ChatThread] {
        try await get(baseURL.appendingPathComponent("chats/threads"), as: [ChatThread].self)
    }

    // GET /chats/{threadId}
    static func getMessages(threadId: String) async throws -> [ChatMessage] {
        try await get(baseURL.appendingPathComponent("chats/\(threadId)"), as: [ChatMessage].self)
    }

    // POST /chats/{threadId}/send. Server now returns the persisted
    // ChatMessage so callers can reconcile their optimistic local row
    // with the server-assigned id and timestamp.
    static func sendMessage(threadId: String, text: String) async throws -> ChatMessage {
        let body = SendMessageRequest(text: text)
        return try await post(body, to: baseURL.appendingPathComponent("chats/\(threadId)/send"), as: ChatMessage.self)
    }

    // POST /chats/{threadId}/read — flips the caller's unread_count
    // for this thread to 0. Called when the user opens a chat so the
    // inbox kicker and per-row badge actually clear.
    static func markChatThreadRead(threadId: String) async throws {
        let body = EmptyRequest()
        _ = try await postVoid(body, to: baseURL.appendingPathComponent("chats/\(threadId)/read"))
    }

    // MARK: - Notifications

    /// GET /notifications/me — most-recent first, defaults to 30 rows.
    static func listNotifications(limit: Int = 30) async throws -> [NotificationDTO] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("notifications/me"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        return try await get(comps.url!, as: [NotificationDTO].self)
    }

    /// PUT /notifications/{id}/read — idempotent. Server returns 204 with
    /// no body, so the client side just needs to validate the response.
    static func markNotificationRead(id: String) async throws {
        let url = baseURL.appendingPathComponent("notifications/\(id)/read")
        try await putVoidNoBody(url)
    }

    // MARK: - Live ride location

    /// POST /rides/{rideId}/location — driver-side breadcrumb push.
    /// Server validates that the caller drives the route attached to
    /// the ride; rider-side calls return 403.
    static func postRideLocation(rideId: String,
                                  lat: Double,
                                  lng: Double,
                                  heading: Double? = nil,
                                  speedMps: Double? = nil) async throws {
        let body = RideLocationPushBody(lat: lat, lng: lng, heading: heading, speedMps: speedMps)
        let url = baseURL.appendingPathComponent("rides/\(rideId)/location")
        var req = authedRequest(url, method: "POST")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
    }

    // MARK: - Favorites + Route requests + Saved search

    static func favoriteRoute(_ routeId: String) async throws {
        _ = try await postVoid(EmptyRequest(),
            to: baseURL.appendingPathComponent("commute/routes/\(routeId)/favorite"))
    }

    static func unfavoriteRoute(_ routeId: String) async throws {
        let url = baseURL.appendingPathComponent("commute/routes/\(routeId)/favorite")
        var req = authedRequest(url, method: "DELETE")
        req.httpBody = nil
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
    }

    static func myFavorites() async throws -> [RecurringRouteDTO] {
        try await get(baseURL.appendingPathComponent("commute/routes/favorites/me"),
                      as: [RecurringRouteDTO].self)
    }

    static func postRouteRequest(_ request: RouteRequestPayload) async throws -> IdResponse {
        try await post(request,
                       to: baseURL.appendingPathComponent("commute/route-requests"),
                       as: IdResponse.self)
    }

    static func myRouteRequests() async throws -> [RouteRequest] {
        try await get(baseURL.appendingPathComponent("commute/route-requests/me"),
                      as: [RouteRequest].self)
    }

    static func deleteRouteRequest(_ id: String) async throws {
        let url = baseURL.appendingPathComponent("commute/route-requests/\(id)")
        let req = authedRequest(url, method: "DELETE")
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
    }

    static func routeRequestDemand() async throws -> [RouteRequestDemand] {
        try await get(baseURL.appendingPathComponent("commute/route-requests/demand"),
                      as: [RouteRequestDemand].self)
    }

    static func putSavedSearch(_ payload: SavedSearchPayload) async throws {
        var req = authedRequest(baseURL.appendingPathComponent("commute/saved-search"), method: "PUT")
        req.httpBody = try encoder.encode(payload)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: req.url ?? baseURL)
    }

    static func getSavedSearch() async throws -> SavedSearchPayload? {
        let url = baseURL.appendingPathComponent("commute/saved-search")
        let req = authedRequest(url, method: "GET")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 404 { return nil }
        try validate(response, data: data, url: url)
        return try decode(SavedSearchPayload.self, from: data, url: url)
    }

    // MARK: - Long-haul

    static func listLongHaulTrips(origin: String? = nil,
                                  destination: String? = nil,
                                  fromDate: Date? = nil) async throws -> [LongHaulTrip] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("longhaul/trips"),
                                  resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let o = origin?.trimmingCharacters(in: .whitespaces), !o.isEmpty {
            items.append(URLQueryItem(name: "origin", value: o))
        }
        if let d = destination?.trimmingCharacters(in: .whitespaces), !d.isEmpty {
            items.append(URLQueryItem(name: "destination", value: d))
        }
        if let date = fromDate {
            items.append(URLQueryItem(name: "fromDate", value: longHaulIsoFormatter.string(from: date)))
        }
        if !items.isEmpty { comps.queryItems = items }
        return try await get(comps.url!, as: [LongHaulTrip].self)
    }

    static func getLongHaulTrip(id: String) async throws -> LongHaulTrip {
        try await get(baseURL.appendingPathComponent("longhaul/trips/\(id)"),
                      as: LongHaulTrip.self)
    }

    static func createLongHaulTrip(origin: String, destination: String,
                                   departAt: Date, seatsTotal: Int,
                                   pricePerSeatMyr: Int, notes: String) async throws -> IdResponse {
        let body = CreateLongHaulTripRequest(
            origin: origin, destination: destination,
            departAt: longHaulIsoFormatter.string(from: departAt),
            seatsTotal: seatsTotal, pricePerSeatMyr: pricePerSeatMyr,
            notes: notes
        )
        return try await post(body, to: baseURL.appendingPathComponent("longhaul/trips"),
                              as: IdResponse.self)
    }

    static func bookLongHaulTrip(tripId: String, seats: Int) async throws -> LongHaulBookingResponse {
        let body = BookLongHaulTripRequest(seats: seats)
        return try await post(body,
                              to: baseURL.appendingPathComponent("longhaul/trips/\(tripId)/book"),
                              as: LongHaulBookingResponse.self)
    }

    static func myLongHaulBookings() async throws -> [LongHaulBooking] {
        try await get(baseURL.appendingPathComponent("longhaul/bookings/me"),
                      as: [LongHaulBooking].self)
    }

    static func myDriverLongHaulTrips() async throws -> [LongHaulTrip] {
        try await get(baseURL.appendingPathComponent("longhaul/trips/driver/me"),
                      as: [LongHaulTrip].self)
    }

    /// Long-haul `departAt` is a wall-clock ISO datetime, NOT the
    /// y-m-d format `isoDateFormatter` emits. Local helper so we
    /// don't piggy-back on the global encoder/decoder for this case.
    nonisolated(unsafe) private static let longHaulIsoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Pilot-blocker plumbing

    /// POST /users/me/kyc-documents/upload — uploads raw image bytes
    /// to durable storage. Returns the `storageUri` the existing
    /// `uploadKycDocument(kind:storageUrl:)` should be called with so
    /// the kyc_documents row is linked to the actual file. The two-
    /// step is intentional: we want a chance to surface upload
    /// failures distinctly from kyc-row failures.
    static func uploadKycDocument(kind: KycDocumentKind, imageData: Data) async throws -> KycUploadResponse {
        var comps = URLComponents(url: baseURL.appendingPathComponent("users/me/kyc-documents/upload"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "kind", value: kind.rawValue)]
        let url = comps.url!
        var req = authedRequest(url, method: "POST")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = imageData
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
        return try decode(KycUploadResponse.self, from: data, url: url)
    }

    /// POST /safety/sos — persists the alert to the on-call queue.
    /// Real dispatchers (Twilio / PagerDuty) are env-gated; the
    /// response always includes the alert id so the iOS side can
    /// reference it in support flows.
    static func reportSafetyAlert(rideId: String?, routeId: String?,
                                   lat: Double?, lng: Double?,
                                   message: String) async throws -> SafetyAlertResponse {
        let body = SafetyAlertRequest(
            rideId: rideId, routeId: routeId,
            lat: lat, lng: lng, message: message
        )
        return try await post(body, to: baseURL.appendingPathComponent("safety/sos"),
                              as: SafetyAlertResponse.self)
    }

    /// POST /devices — registers an APNs token for the signed-in
    /// user. Idempotent on (user, token) so repeat calls are safe.
    static func registerDevice(apnsToken: String, locale: String?, appVersion: String?) async throws {
        let body = RegisterDeviceRequest(
            apnsToken: apnsToken, platform: "iOS",
            locale: locale, appVersion: appVersion
        )
        try await postVoid(body, to: baseURL.appendingPathComponent("devices"))
    }

    /// GET /drivers/me/connect-account — returns the Stripe Connect
    /// onboarding URL when payouts aren't enabled yet, or
    /// `state: "READY"` once the account is verified.
    static func driverConnectAccount() async throws -> DriverConnectAccountResponse {
        try await get(baseURL.appendingPathComponent("drivers/me/connect-account"),
                      as: DriverConnectAccountResponse.self)
    }

    /// GET /rides/{rideId}/stream — SSE feed of live driver
    /// breadcrumbs. Yields the latest cached location first, then
    /// each subsequent push from the driver. Cancellation of the
    /// returned task drops the connection cleanly.
    static func streamRideLocation(rideId: String) -> AsyncStream<RideLocationDTO> {
        AsyncStream { continuation in
            let url = baseURL.appendingPathComponent("rides/\(rideId)/stream")
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            if let token = SessionStorage.authToken, !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            // SSE connections live for the duration of the ride.
            // Default URLSession timeouts (60s) would close the
            // stream prematurely.
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 600     // 10 min idle
            config.timeoutIntervalForResource = 60 * 60 * 6 // 6 hours total
            let session = URLSession(configuration: config)

            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: req)
                    if let http = response as? HTTPURLResponse,
                       !(200..<300).contains(http.statusCode) {
                        continuation.finish()
                        return
                    }
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    decoder.dateDecodingStrategy = .iso8601
                    for try await line in bytes.lines {
                        // SSE framing: only `data:` lines are payload;
                        // we ignore comments (`:`) and event names.
                        guard line.hasPrefix("data:") else { continue }
                        let json = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard let data = json.data(using: .utf8),
                              let update = try? decoder.decode(RideLocationDTO.self, from: data) else {
                            continue
                        }
                        continuation.yield(update)
                    }
                } catch {
                    // network drop / cancellation — finish the stream
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // GET /health
    static func health() async throws -> Bool {
        let _: HealthResponse = try await get(baseURL.appendingPathComponent("health"), as: HealthResponse.self)
        return true
    }

    // MARK: - Private HTTP helpers

    private static func authedRequest(_ url: URL, method: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if method != "GET" {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = SessionStorage.authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private static func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let req = authedRequest(url, method: "GET")
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
        return try decode(T.self, from: data, url: url)
    }

    private static func post<B: Encodable, R: Decodable>(_ body: B, to url: URL, as type: R.Type) async throws -> R {
        var req = authedRequest(url, method: "POST")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
        return try decode(R.self, from: data, url: url)
    }

    private static func postVoid<B: Encodable>(_ body: B, to url: URL) async throws {
        var req = authedRequest(url, method: "POST")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
    }

    private static func put<B: Encodable, R: Decodable>(_ body: B, to url: URL, as type: R.Type) async throws -> R {
        var req = authedRequest(url, method: "PUT")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
        return try decode(R.self, from: data, url: url)
    }

    private static func putVoid<B: Encodable>(_ body: B, to url: URL) async throws {
        var req = authedRequest(url, method: "PUT")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
    }

    /// Bodyless PUT — used for idempotent state flips like
    /// `/notifications/{id}/read` where the URL itself encodes the
    /// intent and the backend returns 204.
    private static func putVoidNoBody(_ url: URL) async throws {
        let req = authedRequest(url, method: "PUT")
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data, url: url)
    }

    private static func validate(_ response: URLResponse, data: Data, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            // Surface the server's error body so we can debug 4xx/5xx
            // cases. Keep it short and DEBUG-only — production logs
            // shouldn't carry response payloads, and we never log the
            // Authorization header (only the URL path is included).
            #if DEBUG
            let snippet = errorSnippet(from: data)
            apiLog.debug("HTTP \(http.statusCode, privacy: .public) \(http.url?.path ?? url.path, privacy: .public) — body: \(snippet, privacy: .public)")
            #endif
            throw APIError.serverError(http.statusCode)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data, url: URL) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch let decodingError as DecodingError {
            // Preserve the structured DecodingError context so the
            // caller can see *what* failed to decode, not just that
            // something did. DEBUG-only logging keeps response bodies
            // out of production. The thrown APIError stays opaque so
            // user-facing copy doesn't leak server schema.
            #if DEBUG
            let snippet = errorSnippet(from: data)
            apiLog.debug("decode \(String(describing: T.self), privacy: .public) failed at \(url.path, privacy: .public): \(decodingError.shortDescription, privacy: .public) — body: \(snippet, privacy: .public)")
            #endif
            throw APIError.decodingError
        } catch {
            #if DEBUG
            apiLog.debug("decode \(String(describing: T.self), privacy: .public) threw \(error.localizedDescription, privacy: .public)")
            #endif
            throw APIError.decodingError
        }
    }

    /// Truncated, secret-scrubbed string view of a response body for
    /// DEBUG logs. We cap at 512 bytes and strip anything that looks
    /// like a bearer token to be defensive — the backend shouldn't
    /// echo tokens, but a future endpoint might.
    private static func errorSnippet(from data: Data) -> String {
        let cap = min(data.count, 512)
        var s = String(data: data.prefix(cap), encoding: .utf8) ?? "<binary \(data.count)B>"
        if data.count > cap { s += "…[+\(data.count - cap)B]" }
        // Defense-in-depth: scrub anything that smells like a JWT or
        // long opaque token before it lands in os_log.
        s = s.replacingOccurrences(
            of: #"(?i)(bearer\s+)[A-Za-z0-9._\-]{16,}"#,
            with: "$1<redacted>",
            options: .regularExpression
        )
        s = s.replacingOccurrences(
            of: #"\"token\"\s*:\s*\"[^\"]{8,}\""#,
            with: "\"token\":\"<redacted>\"",
            options: .regularExpression
        )
        return s
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = isoDateTimeFormatter.date(from: value) { return date }
            if let date = isoDateTimeNoFractionFormatter.date(from: value) { return date }
            if let date = isoDateFormatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return d
    }
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoDateFormatter.string(from: date))
        }
        return e
    }

    nonisolated(unsafe) private static let isoDateTimeFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoDateTimeNoFractionFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

enum APIError: LocalizedError {
    case invalidResponse, serverError(Int), decodingError, networkError, unauthorized
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response."
        case .serverError(let code): return "Server error \(code)."
        case .decodingError: return "Could not read server data."
        case .networkError: return "Network unavailable."
        case .unauthorized: return "Your session has expired. Please sign in again."
        }
    }
}

// MARK: - Auth DTOs

struct RequestOtpRequest: Encodable { var phone: String }

struct RequestOtpResponse: Decodable {
    var sent: Bool
    var expiresAt: String?
    var devCode: String?
}

struct VerifyOtpRequest: Encodable {
    var phone: String
    var code: String
}

struct VerifyOtpResponse: Decodable {
    var token: String
    var user: AuthUserDTO
}

struct AuthUserDTO: Decodable {
    var id: String
    var phone: String
    var displayName: String
    var kycStatus: String
    /// Vehicle identity lives on the driver, not per-route. Optional
    /// because non-drivers and freshly-signed-up drivers haven't set
    /// theirs yet — Profile shows a CTA in that case.
    var plateNumber: String?
    var carColor: String?
    var carModel: String?
    /// Real average rating + how many ratings back it. Both nil until
    /// the user has ratings. Profile shows "New" until ratingCount
    /// >= 3 to avoid the previous "fake 5.0 for everyone" trap.
    var averageRating: Double?
    var ratingCount: Int?
    /// Account creation date (ISO-8601). Drives the "Member since"
    /// stat that replaced the old fake on-time/savings columns.
    var memberSince: String?

    var kyc: KycStatus { KycStatus(rawValue: kycStatus) ?? .notStarted }
}

/// Driver vehicle identity. The server stores plate + colour + model
/// on the user row; iOS sends this whole struct to PUT /users/me/vehicle
/// and reads it back from /auth/me.
struct UpdateVehicleRequest: Encodable {
    var plateNumber: String
    var carColor: String
    var carModel: String
}

struct UpdateVehicleResponse: Decodable {
    var plateNumber: String?
    var carColor: String?
    var carModel: String?
}

// `UpdateKycRequest` was removed — the server no longer accepts a
// client-supplied target status. Submission is `POST /users/me/kyc/submit`
// with an empty body and always lands on PENDING.
struct KycResponse: Decodable { var kycStatus: String }
struct UpdateDisplayNameRequest: Encodable { var displayName: String }

// MARK: - Privacy & Security DTOs

/// Whitelisted toggles for `/users/me/preferences`. Server merges these
/// into the user's JSONB preferences column — fields you don't supply
/// stay as they were. Defaults at the iOS side mirror the server-side
/// defaults so the UI never lies before the first GET completes.
struct UserPreferencesDTO: Decodable {
    var pushEnabled: Bool
    var phoneVisibleToSubscribers: Bool
    var biometricLock: Bool
    var marketingEmails: Bool
}

struct UpdatePreferencesRequest: Encodable {
    var pushEnabled: Bool?
    var phoneVisibleToSubscribers: Bool?
    var biometricLock: Bool?
    var marketingEmails: Bool?
}

struct BlockedUserDTO: Decodable, Identifiable, Equatable {
    /// Compound id is fine — combo of user id + (no createdAt-changes
    /// after first block) makes the SwiftUI ForEach stable.
    var userId: String
    var displayName: String
    var reason: String?
    var createdAt: String?
    var id: String { userId }
}

struct AddBlockRequest: Encodable {
    var userId: String
    var reason: String?
}

struct DeleteAccountResponse: Decodable {
    /// ISO-8601 timestamp 30 days out — when the soft-delete becomes
    /// permanent. iOS surfaces this in the confirmation copy.
    var scheduledFor: String
    var message: String
}

struct DataExportResponse: Decodable {
    var acknowledged: Bool
    var slaDays: Int
    var message: String
}
struct EmptyRequest: Encodable {}

struct CreateLongHaulTripRequest: Encodable {
    var origin: String
    var destination: String
    /// Server expects ISO-8601 datetime; encoded as a string so we
    /// don't go through the global encoder's y-m-d strategy.
    var departAt: String
    var seatsTotal: Int
    var pricePerSeatMyr: Int
    var notes: String
}

struct BookLongHaulTripRequest: Encodable {
    var seats: Int
}

struct SkipRideResponse: Decodable {
    var ok: Bool
    var alreadySkipped: Bool?
}

// MARK: - Solo seat DTOs

/// Quote response — drives the confirm sheet's content. `available`
/// + `reason` tell the UI whether to enable the Confirm CTA and what
/// to display when it can't. NEVER compute the price locally — show
/// `soloPriceMyr` straight from this response.
struct SoloQuoteResponse: Decodable {
    var rideInstanceId: String
    var routeId: String
    var driverName: String?
    var startLocation: String
    var endLocation: String
    var date: String           // YYYY-MM-DD
    var departureTime: String  // HH:mm
    var departAt: String?      // ISO 8601 UTC
    var pricePerSeatMyr: Int
    var soloPriceMyr: Int
    var soloMultiplier: Int
    var available: Bool
    /// One of: ride_not_scheduled, ride_in_past, already_solo_booked,
    /// you_already_solo_booked, other_passengers_already_booked. Used
    /// for messaging only — the UI just shows a human string.
    var reason: String?
    var cancellationPolicy: SoloCancelPolicy
}

struct SoloCancelPolicy: Decodable {
    var fullRefundUntilHours: Int
    var halfRefundUntilHours: Int
}

struct SoloBookResponse: Decodable {
    var rideInstanceId: String
    var routeId: String
    var amountMyr: Int
    var payment: PaymentChargeResult
}

struct SoloCancelResponse: Decodable {
    var cancelled: Bool
    var refundMyr: Int
    var refundFraction: Double
    var refundPaymentId: String?
}

// MARK: - Corridor suggestions

enum CorridorSuggestionKind: String {
    case pickup
    case drop
}

/// A pickup/drop label learned from past route_points on similar
/// corridors. `useCount` drives ranking — chips with higher counts
/// render above MapKit-derived suggestions in the Create Route rail.
struct CorridorSuggestion: Decodable, Equatable {
    var label: String
    var lat: Double
    var lng: Double
    var useCount: Int

    /// Convenience — converts to the PlaceSuggestion shape the
    /// existing pickup/drop rails consume so we can merge without
    /// touching downstream code.
    func toPlaceSuggestion() -> PlaceSuggestion {
        PlaceSuggestion(displayName: label, lat: lat, lon: lng)
    }
}

// MARK: - API DTOs (mirrors Android DTOs)

struct CommuteRouteSearchRequest: Encodable {
    var riderId: String
    var homeLocation: String
    var officeLocation: String
    var earliestDeparture: String // "HH:mm"
    var latestDeparture: String
    var homeLat: Double?
    var homeLng: Double?
    var officeLat: Double?
    var officeLng: Double?
    /// Optional rider-supplied filters. When omitted the backend
    /// returns everything in the time window — matches today's
    /// behaviour. When set, restricts to overlapping days + capped
    /// price.
    var daysOfWeek: [String: Bool]? = nil
    var maxPriceMyr: Int? = nil
}

struct RouteRequestPayload: Encodable {
    var origin: String
    var destination: String
    var originLat: Double? = nil
    var originLng: Double? = nil
    var destLat: Double? = nil
    var destLng: Double? = nil
    var preferredTime: String? = nil
    var daysOfWeek: [String: Bool]? = nil
    var notes: String = ""
}

struct RouteRequest: Decodable, Identifiable {
    var id: String
    var origin: String
    var destination: String
    var preferredTime: String?
    var daysOfWeek: [String: Bool]?
    var notes: String
    var status: String
    var createdAt: Date
}

struct RouteRequestDemand: Decodable, Identifiable {
    var origin: String
    var destination: String
    var riders: Int
    var id: String { "\(origin)::\(destination)" }
}

struct SavedSearchPayload: Codable {
    var originLabel: String
    var destinationLabel: String
    var originLat: Double? = nil
    var originLng: Double? = nil
    var destLat: Double? = nil
    var destLng: Double? = nil
    var earliestTime: String
    var latestTime: String
    var daysOfWeek: [String: Bool]? = nil
    var maxPriceMyr: Int? = nil
}

struct CommuteRouteMatchResponse: Decodable {
    var candidates: [CommuteRouteMatchResultDTO]

    private enum CodingKeys: String, CodingKey {
        case candidates
        case matches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidates = try container.decodeIfPresent([CommuteRouteMatchResultDTO].self, forKey: .candidates)
            ?? container.decodeIfPresent([CommuteRouteMatchResultDTO].self, forKey: .matches)
            ?? []
    }
}

struct CommuteRouteMatchResultDTO: Decodable {
    var route: RecurringRouteDTO
    var pickupDistanceMeters: Double
    var reliabilityScore: Double
    var routeOverlapScore: Double
    var estimatedDetourMinutes: Double
    var recurringRiderPriority: Bool
    var availableSeats: Int
    var rankingScore: Double

    func toModel() -> CommuteRouteMatchResult {
        CommuteRouteMatchResult(
            route: route.toModel(),
            pickupDistanceMeters: pickupDistanceMeters,
            reliabilityScore: reliabilityScore,
            routeOverlapScore: routeOverlapScore,
            estimatedDetourMinutes: estimatedDetourMinutes,
            recurringRiderPriority: recurringRiderPriority,
            availableSeats: availableSeats,
            rankingScore: rankingScore
        )
    }
}

struct RecurringRouteDTO: Decodable {
    var id: String
    var driverId: String
    var driverName: String?
    var driverPhone: String?
    /// True when `driverPhone` is the unmasked E.164. When false the
    /// phone is a display-only stub like "+60 •• ••• ••23" — never
    /// pass it to `tel://`. iOS uses this flag to keep the Call button
    /// disabled until the rider has an ACTIVE subscription (the only
    /// state where the server reveals the full number).
    var driverPhoneRevealed: Bool?
    var startLocation: String
    var endLocation: String
    var pickupPoints: [RoutePoint]
    var dropPoints: [RoutePoint]
    var departureTime: String
    var daysOfWeek: DaysOfWeekFlags
    var seatCount: Int
    var pricePerSeat: Int
    var carType: CarType?
    /// Vehicle identity is server-sourced (from the driver's user
    /// record). Client never writes these back through this DTO —
    /// drivers update their profile via PUT /users/me/vehicle.
    var plateNumber: String?
    var carColor: String?
    var carModel: String?
    var activeStatus: RouteActiveStatus?
    var reliability: DriverReliability?
    var isFavorite: Bool?

    func toModel() -> RecurringRoute {
        RecurringRoute(
            id: id, driverId: driverId, driverName: driverName ?? "Driver",
            driverPhone: driverPhone,
            driverPhoneRevealed: driverPhoneRevealed ?? false,
            startLocation: startLocation, endLocation: endLocation,
            pickupPoints: pickupPoints, dropPoints: dropPoints,
            departureTime: departureTime, daysOfWeek: daysOfWeek,
            seatCount: seatCount, pricePerSeat: pricePerSeat,
            carType: carType ?? .sedan,
            plateNumber: plateNumber, carColor: carColor, carModel: carModel,
            activeStatus: activeStatus ?? .active,
            reliability: reliability ?? DriverReliability(onTimeRate: 0.9, cancellationRate: 0.05, repeatRiders: 0, averageRating: 4.5),
            isFavorite: isFavorite ?? false
        )
    }
}

struct RouteSubscriptionDTO: Decodable {
    var id: String
    var routeId: String
    var riderId: String
    var riderName: String?
    var startDate: Date
    var endDate: Date
    var selectedPickupPoint: RoutePoint
    var selectedDropPoint: RoutePoint
    var status: RouteSubscriptionStatus

    func toModel() -> RouteSubscription {
        RouteSubscription(id: id, routeId: routeId, riderId: riderId, riderName: riderName ?? "Rider",
                          startDate: startDate, endDate: endDate,
                          selectedPickupPoint: selectedPickupPoint, selectedDropPoint: selectedDropPoint, status: status)
    }
}

struct CommuteRideInstanceDTO: Decodable {
    var id: String
    var routeId: String
    var date: Date
    var seatAvailability: Int
    var confirmedPassengers: [String]?
    var rideStatus: CommuteRideStatus

    func toModel() -> CommuteRideInstance {
        CommuteRideInstance(id: id, routeId: routeId, date: date, seatAvailability: seatAvailability,
                            confirmedPassengers: confirmedPassengers ?? [], rideStatus: rideStatus)
    }
}

struct CommuteRideCalendarItemDTO: Decodable {
    var id: String?
    var date: Date
    var routeId: String
    var driverName: String?
    var startLocation: String
    var endLocation: String
    var pickupPoint: RoutePoint
    var dropPoint: RoutePoint
    var rideStatus: CommuteRideStatus

    func toModel() -> CommuteRideCalendarItem {
        CommuteRideCalendarItem(rideInstanceId: id, date: date, routeId: routeId,
                                driverName: driverName ?? "Driver",
                                startLocation: startLocation, endLocation: endLocation,
                                pickupPoint: pickupPoint, dropPoint: dropPoint, rideStatus: rideStatus)
    }
}

struct RouteSubscriptionRequest: Encodable {
    var routeId: String
    var riderId: String
    var riderName: String
    var startDate: Date
    var endDate: Date
    var selectedPickupPointId: String
    var selectedDropPointId: String
    var status: String = "ACTIVE"
}

struct IdResponse: Decodable {
    var id: String?
    var routeId: String?
    var subscriptionId: String?
}

struct UpdateSubscriptionStatusRequest: Encodable { var status: String }
struct UpdateRouteActiveStatusRequest: Encodable { var activeStatus: Bool }
struct UpdateRouteScheduleRequest: Encodable {
    var departureTime: String
    var daysOfWeek: [String: Bool]
}
struct SendMessageRequest: Encodable { var text: String }
struct HealthResponse: Decodable { var status: String }

// MARK: - Notification DTO
//
// Mirrors the row shape from `GET /notifications/me`:
//   id · type · title · body · routeId? · subscriptionId? ·
//   rideInstanceId? · readAt? · createdAt
//
// `type` is intentionally a free-form string from the backend
// (`RIDE_REMINDER`, `PAYMENT_FAILED`, `DRIVER_UPDATE`, …) — the iOS
// side maps known kinds to icons + colors, with a generic fallback
// for anything new the backend introduces. That keeps the iOS build
// forward-compatible with new notification kinds without needing
// an app release.
struct NotificationDTO: Decodable, Equatable {
    var id: String
    var type: String
    var title: String
    var body: String
    var routeId: String?
    var subscriptionId: String?
    var rideInstanceId: String?
    var readAt: Date?
    var createdAt: Date
}

// MARK: - Live ride location DTOs
//
// `RideLocationDTO` is what arrives via SSE on the rider side; the
// push body is `RideLocationPushBody`. Heading is in degrees clockwise
// from north (0…360), speed in metres-per-second; both optional
// because Core Location doesn't always have a confident value.

struct RideLocationDTO: Decodable, Equatable {
    var rideId: String
    var lat: Double
    var lng: Double
    var heading: Double?
    var speedMps: Double?
    var recordedAt: Date
}

struct RideLocationPushBody: Encodable {
    var lat: Double
    var lng: Double
    var heading: Double?
    var speedMps: Double?
}

// MARK: - Pilot-blocker DTOs

struct KycUploadResponse: Decodable, Equatable {
    var id: String
    var storageUri: String
    var byteSize: Int
}

struct SafetyAlertRequest: Encodable {
    var rideId: String?
    var routeId: String?
    var lat: Double?
    var lng: Double?
    var message: String
}

struct SafetyAlertResponse: Decodable, Equatable {
    var alertId: String
    var status: String
    var dispatchedTo: [String]
}

struct RegisterDeviceRequest: Encodable {
    var apnsToken: String
    var platform: String
    var locale: String?
    var appVersion: String?
}

/// `state` ∈ { "UNCONFIGURED", "PENDING", "READY" }. iOS branches
/// on this — UNCONFIGURED shows a coming-soon banner; PENDING opens
/// `onboardingUrl` in SFSafariViewController; READY hides the CTA.
struct DriverConnectAccountResponse: Decodable, Equatable {
    var state: String
    var onboardingUrl: String?
    var payoutsEnabled: Bool
    var detailsSubmitted: Bool
}

struct CreateRecurringRouteRequest: Encodable {
    var driverId: String
    var startLocation: String
    var endLocation: String
    var pickupPoints: [RoutePointIn]
    var dropPoints: [RoutePointIn]
    var departureTime: String
    var daysOfWeek: [String: Bool]
    var seatCount: Int
    var pricePerSeat: Int
    var carType: String
    // plateNumber + carColor intentionally removed — vehicle identity
    // is set once on the driver's profile (PUT /users/me/vehicle) and
    // the server reads it back per-route via a JOIN. A driver who lists
    // one plate on a route and arrives in another car is the exact
    // safety hole we're closing.
    var activeStatus: Bool = true

    struct RoutePointIn: Encodable {
        var label: String
        var lat: Double
        var lng: Double
        var clusterId: String?
    }
}

// MARK: - Payments / KYC DTOs

struct ChargeSubscriptionRequest: Encodable {
    var subscriptionId: String
    var tier: String
    /// Optional — backend computes from the subscription's date range
    /// when nil. `amountMyr` is intentionally NOT in this request:
    /// the server is the only authority on what a charge costs.
    var days: Int?
}

struct UploadKycDocumentRequest: Encodable {
    var kind: String
    var storageUrl: String?
}

struct UploadKycDocumentResponse: Decodable {
    var id: String
    var kind: String
    var storageUrl: String?
    var kycStatus: String
}

struct CancellationReportPayload: Encodable {
    var rideInstanceId: String?
    var subscriptionId: String?
    var routeId: String
    var actor: String        // CancellationActor raw value
    var kind: String         // CancellationKind raw value
    var notes: String?
}

struct CancellationReportResponse: Decodable {
    var id: String
    var penaltyMyr: Int
    var driverId: String?
}

struct RideReviewRequest: Encodable {
    var rideInstanceId: String?
    var routeId: String?
    var driverId: String?
    var rating: Int
    var tags: [String]
    var tipMyr: Int
    var note: String?
}
