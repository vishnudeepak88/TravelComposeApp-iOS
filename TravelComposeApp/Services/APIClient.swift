import Foundation

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

    static func updateKyc(status: KycStatus) async throws -> KycResponse {
        let body = UpdateKycRequest(status: status.rawValue)
        return try await put(body, to: baseURL.appendingPathComponent("users/me/kyc"), as: KycResponse.self)
    }

    static func updateDisplayName(_ name: String) async throws {
        let body = UpdateDisplayNameRequest(displayName: name)
        _ = try await putVoid(body, to: baseURL.appendingPathComponent("users/me"))
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

    static func chargeSubscription(
        subscriptionId: String?,
        routeId: String?,
        amountMyr: Int,
        tier: SubscriptionTier
    ) async throws -> PaymentChargeResult {
        let body = ChargeSubscriptionRequest(
            subscriptionId: subscriptionId,
            routeId: routeId,
            amountMyr: amountMyr,
            tier: tier.rawValue
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

    static func bookRide(rideInstanceId: String) async throws -> RideBooking {
        try await post(EmptyRequest(), to: baseURL.appendingPathComponent("trips/\(rideInstanceId)/book"), as: RideBooking.self)
    }

    static func listMyBookings() async throws -> [RideBooking] {
        try await get(baseURL.appendingPathComponent("bookings/me"), as: [RideBooking].self)
    }

    static func submitReview(_ request: RideReviewRequest) async throws -> IdResponse {
        try await post(request, to: baseURL.appendingPathComponent("reviews"), as: IdResponse.self)
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

    // POST /chats/{threadId}/send
    static func sendMessage(threadId: String, text: String) async throws {
        let body = SendMessageRequest(text: text)
        _ = try await postVoid(body, to: baseURL.appendingPathComponent("chats/\(threadId)/send"))
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
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

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
        var req = authedRequest(comps.url!, method: "POST")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = imageData
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decode(KycUploadResponse.self, from: data)
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
        try validate(response)
        return try decode(T.self, from: data)
    }

    private static func post<B: Encodable, R: Decodable>(_ body: B, to url: URL, as type: R.Type) async throws -> R {
        var req = authedRequest(url, method: "POST")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decode(R.self, from: data)
    }

    private static func postVoid<B: Encodable>(_ body: B, to url: URL) async throws {
        var req = authedRequest(url, method: "POST")
        req.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    private static func put<B: Encodable, R: Decodable>(_ body: B, to url: URL, as type: R.Type) async throws -> R {
        var req = authedRequest(url, method: "PUT")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decode(R.self, from: data)
    }

    private static func putVoid<B: Encodable>(_ body: B, to url: URL) async throws {
        var req = authedRequest(url, method: "PUT")
        req.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    /// Bodyless PUT — used for idempotent state flips like
    /// `/notifications/{id}/read` where the URL itself encodes the
    /// intent and the backend returns 204.
    private static func putVoidNoBody(_ url: URL) async throws {
        let req = authedRequest(url, method: "PUT")
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else { throw APIError.serverError(http.statusCode) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decodingError }
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

    var kyc: KycStatus { KycStatus(rawValue: kycStatus) ?? .notStarted }
}

struct UpdateKycRequest: Encodable { var status: String }
struct KycResponse: Decodable { var kycStatus: String }
struct UpdateDisplayNameRequest: Encodable { var displayName: String }
struct EmptyRequest: Encodable {}

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
    var startLocation: String
    var endLocation: String
    var pickupPoints: [RoutePoint]
    var dropPoints: [RoutePoint]
    var departureTime: String
    var daysOfWeek: DaysOfWeekFlags
    var seatCount: Int
    var pricePerSeat: Int
    var carType: CarType?
    var activeStatus: RouteActiveStatus?
    var reliability: DriverReliability?

    func toModel() -> RecurringRoute {
        RecurringRoute(
            id: id, driverId: driverId, driverName: driverName ?? "Driver",
            startLocation: startLocation, endLocation: endLocation,
            pickupPoints: pickupPoints, dropPoints: dropPoints,
            departureTime: departureTime, daysOfWeek: daysOfWeek,
            seatCount: seatCount, pricePerSeat: pricePerSeat,
            carType: carType ?? .sedan, activeStatus: activeStatus ?? .active,
            reliability: reliability ?? DriverReliability(onTimeRate: 0.9, cancellationRate: 0.05, repeatRiders: 0, averageRating: 4.5)
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
    var date: Date
    var routeId: String
    var driverName: String?
    var startLocation: String
    var endLocation: String
    var pickupPoint: RoutePoint
    var dropPoint: RoutePoint
    var rideStatus: CommuteRideStatus

    func toModel() -> CommuteRideCalendarItem {
        CommuteRideCalendarItem(date: date, routeId: routeId, driverName: driverName ?? "Driver",
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
    var subscriptionId: String?
    var routeId: String?
    var amountMyr: Int
    var tier: String
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
