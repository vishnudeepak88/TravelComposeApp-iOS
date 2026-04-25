import Foundation
import Combine

// MARK: - App Store (session + seed data, mirrors Android AppStore)

@MainActor
final class AppStore: ObservableObject {
    @Published var isAuthenticated = false
    @Published var phoneNumber = ""
    @Published var kycStatus: KycStatus = .notStarted
    @Published var currentUser = User(id: "rider-me", name: "You", rating: 4.9)

    // Shared in-memory data (seeded — wire to backend when ready)
    @Published var routes: [RecurringRoute] = []
    @Published var subscriptions: [RouteSubscription] = []
    @Published var rideInstances: [CommuteRideInstance] = []
    @Published var threads: [ChatThread] = []
    @Published var messages: [ChatMessage] = []

    let riderId = "rider-me"
    let driverId = "driver-1"

    init() { seed() }

    func completeSignIn(code: String) {
        guard code.count == 6 else { return }
        isAuthenticated = true
    }

    func logout() {
        isAuthenticated = false
        phoneNumber = ""
    }

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

    func subscribe(routeId: String, pickupId: String, dropId: String, days: Int) -> Result<String, AppError> {
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
        let id = "sub-\(UUID().uuidString)"
        subscriptions.append(RouteSubscription(id: id, routeId: routeId, riderId: riderId, riderName: currentUser.name,
                                               startDate: start, endDate: end, selectedPickupPoint: pickup,
                                               selectedDropPoint: drop, status: .active))
        regenerateRides()
        return .success(id)
    }

    func updateSubscription(id: String, status: RouteSubscriptionStatus) {
        guard let i = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[i].status = status
        regenerateRides()
    }

    func createRoute(startLocation: String, endLocation: String, departureTime: String,
                     seatCount: Int, pricePerSeat: Int, carType: CarType, daysOfWeek: DaysOfWeekFlags,
                     pickupNames: [String], dropNames: [String]) -> Result<String, AppError> {
        guard !startLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !endLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .failure(.message("Start and destination required")) }
        guard parseTime(departureTime) != nil else { return .failure(.message("Invalid time format. Use HH:mm")) }
        guard seatCount > 0 else { return .failure(.message("Seat count must be > 0")) }
        guard pricePerSeat > 0 else { return .failure(.message("Price per seat must be > 0")) }

        let pickups = makePoints(from: pickupNames, prefix: "pk", baseLat: 3.14, baseLng: 101.71)
        let drops   = makePoints(from: dropNames,   prefix: "dp", baseLat: 3.16, baseLng: 101.73)
        let id = "rr-\(UUID().uuidString)"
        routes.append(RecurringRoute(id: id, driverId: driverId, driverName: currentUser.name,
                                     startLocation: startLocation, endLocation: endLocation,
                                     pickupPoints: pickups, dropPoints: drops, departureTime: departureTime,
                                     daysOfWeek: daysOfWeek, seatCount: seatCount, pricePerSeat: pricePerSeat,
                                     carType: carType, activeStatus: .active,
                                     reliability: DriverReliability(onTimeRate: 0.9, cancellationRate: 0.05, repeatRiders: 0, averageRating: 5.0)))
        regenerateRides()
        return .success(id)
    }

    func setRouteActive(routeId: String, active: Bool) {
        guard let i = routes.firstIndex(where: { $0.id == routeId }) else { return }
        routes[i].activeStatus = active ? .active : .paused
        regenerateRides()
    }

    func updateRouteSchedule(routeId: String, departureTime: String, daysOfWeek: DaysOfWeekFlags) -> Result<Void, AppError> {
        guard parseTime(departureTime) != nil else { return .failure(.message("Invalid time format")) }
        guard let i = routes.firstIndex(where: { $0.id == routeId }) else { return .failure(.message("Route not found")) }
        routes[i].departureTime = departureTime
        routes[i].daysOfWeek = daysOfWeek
        regenerateRides()
        return .success(())
    }

    func sendMessage(threadId: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(id: "m-\(UUID())", threadId: threadId, sender: .me, text: trimmed, timestamp: Date()))
        if let i = threads.firstIndex(where: { $0.id == threadId }) {
            threads[i].lastMessage = trimmed
            threads[i].unreadCount = 0
        }
    }

    func messages(for threadId: String) -> [ChatMessage] {
        messages.filter { $0.threadId == threadId }.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Private

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

    private func makePoints(from names: [String], prefix: String, baseLat: Double, baseLng: Double) -> [RoutePoint] {
        let cleaned = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let values = cleaned.isEmpty ? ["Default stop"] : cleaned
        return values.enumerated().map { i, name in
            RoutePoint(id: "\(prefix)-\(UUID())", label: name, clusterId: "cluster-\(prefix)-\(i)",
                       lat: baseLat + Double(i) * 0.01, lng: baseLng + Double(i) * 0.01)
        }
    }

    private func parseTime(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    private func seed() {
        let downtown   = RoutePoint(id: "p1", label: "Downtown Station",   clusterId: "cluster-downtown",  lat: 3.1478, lng: 101.7101)
        let civicCenter = RoutePoint(id: "p2", label: "Civic Centre",       clusterId: "cluster-downtown",  lat: 3.1525, lng: 101.7065)
        let missionHub = RoutePoint(id: "p3", label: "Masjid Jamek Hub",   clusterId: "cluster-central",   lat: 3.1490, lng: 101.6967)
        let klccDrop   = RoutePoint(id: "d1", label: "KLCC Office Park",   clusterId: "cluster-klcc",      lat: 3.1571, lng: 101.7123)
        let midValley  = RoutePoint(id: "d2", label: "Mid Valley Offices", clusterId: "cluster-midvalley", lat: 3.1183, lng: 101.6787)
        let putraJaya  = RoutePoint(id: "p4", label: "Putrajaya Sentral",  clusterId: "cluster-putra",     lat: 2.9291, lng: 101.6967)
        let cerdas     = RoutePoint(id: "d3", label: "Cerdas Tech Hub",    clusterId: "cluster-cerdas",    lat: 3.0880, lng: 101.6890)

        routes = [
            RecurringRoute(id: "rr-1", driverId: driverId, driverName: "Nina Cruz",
                           startLocation: "Damansara", endLocation: "KLCC",
                           pickupPoints: [downtown, civicCenter, missionHub], dropPoints: [klccDrop, midValley],
                           departureTime: "08:15", daysOfWeek: .weekdays, seatCount: 3, pricePerSeat: 8,
                           carType: .sedan, activeStatus: .active,
                           reliability: DriverReliability(onTimeRate: 0.95, cancellationRate: 0.03, repeatRiders: 21, averageRating: 4.8)),
            RecurringRoute(id: "rr-2", driverId: "driver-2", driverName: "Evan Brooks",
                           startLocation: "Putrajaya", endLocation: "Mid Valley",
                           pickupPoints: [putraJaya], dropPoints: [midValley, cerdas],
                           departureTime: "08:00", daysOfWeek: .weekdays, seatCount: 4, pricePerSeat: 7,
                           carType: .ev, activeStatus: .active,
                           reliability: DriverReliability(onTimeRate: 0.91, cancellationRate: 0.05, repeatRiders: 14, averageRating: 4.6))
        ]

        let today = Calendar.current.startOfDay(for: Date())
        subscriptions = [
            RouteSubscription(id: "sub-1", routeId: "rr-1", riderId: riderId, riderName: "You",
                              startDate: Calendar.current.date(byAdding: .day, value: -10, to: today) ?? today,
                              endDate:   Calendar.current.date(byAdding: .month, value: 3, to: today) ?? today,
                              selectedPickupPoint: downtown, selectedDropPoint: klccDrop, status: .active),
            RouteSubscription(id: "sub-2", routeId: "rr-1", riderId: "rider-2", riderName: "Aria",
                              startDate: Calendar.current.date(byAdding: .day, value: -2, to: today) ?? today,
                              endDate:   Calendar.current.date(byAdding: .month, value: 2, to: today) ?? today,
                              selectedPickupPoint: civicCenter, selectedDropPoint: midValley, status: .active)
        ]
        threads = [
            ChatThread(id: "c1", tripId: "rr-1", title: "Commute with Nina", lastMessage: "See you at Downtown Station.", unreadCount: 0),
            ChatThread(id: "c2", tripId: "rr-2", title: "Putrajaya Route",   lastMessage: "Running 5 mins late", unreadCount: 1)
        ]
        messages = [
            ChatMessage(id: "m1", threadId: "c1", sender: .other, text: "Hi, still picking up?",       timestamp: Date().addingTimeInterval(-100_000)),
            ChatMessage(id: "m2", threadId: "c1", sender: .me,    text: "Yes, confirmed.",              timestamp: Date().addingTimeInterval(-90_000)),
            ChatMessage(id: "m3", threadId: "c1", sender: .other, text: "See you at Downtown Station.", timestamp: Date().addingTimeInterval(-87_000)),
            ChatMessage(id: "m4", threadId: "c2", sender: .other, text: "Running 5 mins late",         timestamp: Date().addingTimeInterval(-50_000))
        ]
        regenerateRides()
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
