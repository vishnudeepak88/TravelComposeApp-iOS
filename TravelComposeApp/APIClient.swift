import Foundation
import Combine

// MARK: - API Client (mirrors Android ApiService.kt)

struct VoygoAPIClient {
    static var baseURL: URL = URL(string: "http://10.0.2.2:8000/")! // Update for real device

    private static var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
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

    // GET /health
    static func health() async throws -> Bool {
        let _: HealthResponse = try await get(baseURL.appendingPathComponent("health"), as: HealthResponse.self)
        return true
    }

    // MARK: - Private HTTP helpers

    private static func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try decode(T.self, from: data)
    }

    private static func post<B: Encodable, R: Decodable>(_ body: B, to url: URL, as type: R.Type) async throws -> R {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decode(R.self, from: data)
    }

    private static func postVoid<B: Encodable>(_ body: B, to url: URL) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    private static func putVoid<B: Encodable>(_ body: B, to url: URL) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.serverError(http.statusCode) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decodingError }
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

enum APIError: LocalizedError {
    case invalidResponse, serverError(Int), decodingError, networkError
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response."
        case .serverError(let code): return "Server error \(code)."
        case .decodingError: return "Could not read server data."
        case .networkError: return "Network unavailable."
        }
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
}

struct CommuteRouteMatchResponse: Decodable {
    var candidates: [CommuteRouteMatchResultDTO]
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
