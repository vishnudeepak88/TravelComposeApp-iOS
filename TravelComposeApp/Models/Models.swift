import Foundation

// MARK: - Enums

enum CarType: String, CaseIterable, Identifiable, Codable {
    case sedan = "SEDAN"
    case suv = "SUV"
    case hatch = "HATCH"
    case ev = "EV"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sedan: "Sedan"
        case .suv: "SUV"
        case .hatch: "Hatch"
        case .ev: "EV ⚡"
        }
    }
    var icon: String {
        switch self {
        case .sedan: "car.fill"
        case .suv: "car.2.fill"
        case .hatch: "car.rear.fill"
        case .ev: "bolt.car.fill"
        }
    }

    /// Realistic maximum number of passenger seats per car body — i.e.
    /// excluding the driver. Drives the Create Route seat-count cap
    /// so a driver can't accidentally list 8 seats in a hatchback.
    /// SUV covers the popular 7-seater segment (Honda CR-V, Toyota
    /// Innova, Proton X70 with the third row up).
    var maxPassengerSeats: Int {
        switch self {
        case .sedan: 4
        case .suv:   6
        case .hatch: 4
        case .ev:    4
        }
    }
}

enum RouteActiveStatus: String, Codable { case active = "ACTIVE", paused = "PAUSED" }
enum RouteSubscriptionStatus: String, Codable {
    case active = "ACTIVE", paused = "PAUSED", cancelled = "CANCELLED", completed = "COMPLETED"
    var label: String { rawValue.capitalized }
    var color: String {
        switch self {
        case .active: "green"
        case .paused: "orange"
        case .cancelled: "red"
        case .completed: "blue"
        }
    }
}
enum CommuteRideStatus: String, Codable {
    case scheduled = "SCHEDULED", inProgress = "IN_PROGRESS", completed = "COMPLETED", cancelled = "CANCELLED"
    var label: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}
enum ChatSender: String, Codable { case me = "ME", other = "OTHER", system = "SYSTEM" }
enum KycStatus: String, Codable { case notStarted = "NOT_STARTED", pending = "PENDING", approved = "APPROVED", rejected = "REJECTED" }

// MARK: - Core Models

struct DriverReliability: Codable, Equatable {
    var onTimeRate: Double
    var cancellationRate: Double
    var repeatRiders: Int
    var averageRating: Double

    var compositeScore: Double {
        let onTime = onTimeRate.clamped(to: 0...1) * 0.4
        let cancel = (1 - cancellationRate.clamped(to: 0...1)) * 0.25
        let repeat_ = Double(max(0, repeatRiders)) / 50.0 * 0.15
        let rating = averageRating.clamped(to: 0...5) / 5.0 * 0.2
        return onTime + cancel + repeat_ + rating
    }
}

struct RoutePoint: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var label: String
    var clusterId: String
    var lat: Double
    var lng: Double
}

struct DaysOfWeekFlags: Codable, Equatable {
    var monday: Bool
    var tuesday: Bool
    var wednesday: Bool
    var thursday: Bool
    var friday: Bool
    var saturday: Bool
    var sunday: Bool

    static let weekdays = DaysOfWeekFlags(monday: true, tuesday: true, wednesday: true, thursday: true, friday: true, saturday: false, sunday: false)
    static let allDays  = DaysOfWeekFlags(monday: true, tuesday: true, wednesday: true, thursday: true, friday: true, saturday: true, sunday: true)

    func enabled(for date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        switch weekday {
        case 1: return sunday
        case 2: return monday
        case 3: return tuesday
        case 4: return wednesday
        case 5: return thursday
        case 6: return friday
        default: return saturday
        }
    }

    var shortLabel: String {
        var parts: [String] = []
        if monday    { parts.append("Mon") }
        if tuesday   { parts.append("Tue") }
        if wednesday { parts.append("Wed") }
        if thursday  { parts.append("Thu") }
        if friday    { parts.append("Fri") }
        if saturday  { parts.append("Sat") }
        if sunday    { parts.append("Sun") }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }

    var asDictionary: [String: Bool] {
        ["monday": monday, "tuesday": tuesday, "wednesday": wednesday,
         "thursday": thursday, "friday": friday, "saturday": saturday, "sunday": sunday]
    }
}

struct RecurringRoute: Codable, Equatable, Identifiable {
    var id: String
    var driverId: String
    var driverName: String
    /// Optional E.164 phone number for the in-trip call button. Nil
    /// until the backend exposes it on the route DTO; when nil, the
    /// LiveTrip phone affordance stays disabled (with a real
    /// accessibility label) instead of opening a bad `tel:` URL.
    var driverPhone: String? = nil
    var startLocation: String
    var endLocation: String
    var pickupPoints: [RoutePoint]
    var dropPoints: [RoutePoint]
    var departureTime: String // "HH:mm"
    var daysOfWeek: DaysOfWeekFlags
    var seatCount: Int
    var pricePerSeat: Int
    var carType: CarType
    var activeStatus: RouteActiveStatus
    var reliability: DriverReliability
}

struct RouteSubscription: Codable, Equatable, Identifiable {
    var id: String
    var routeId: String
    var riderId: String
    var riderName: String
    var startDate: Date
    var endDate: Date
    var selectedPickupPoint: RoutePoint
    var selectedDropPoint: RoutePoint
    var status: RouteSubscriptionStatus
    /// Tier the rider chose at subscribe-time. Persisted so that retry-
    /// payment reuses the same discount band instead of defaulting to
    /// monthly. Optional for backwards compatibility with existing rows
    /// that predate this field.
    var tier: String? = nil
    var totalDays: Int? = nil
}

struct CommuteRideInstance: Codable, Equatable, Identifiable {
    var id: String
    var routeId: String
    var date: Date
    var seatAvailability: Int
    var confirmedPassengers: [String]
    var rideStatus: CommuteRideStatus
}

struct RideBooking: Codable, Equatable, Identifiable {
    var id: String
    var rideInstanceId: String
    var routeId: String
    var date: Date?
    var rideStatus: CommuteRideStatus?
    var driverName: String?
    var startLocation: String?
    var endLocation: String?
}

struct RouteSubscriptionWithRoute: Identifiable {
    var id: String { subscription.id }
    var subscription: RouteSubscription
    var route: RecurringRoute
    var nextRideDate: Date?
}

struct NextCommute: Identifiable {
    var id: String { ride.id }
    var subscription: RouteSubscription
    var route: RecurringRoute
    var ride: CommuteRideInstance
    var thread: ChatThread?
}

struct CommuteRouteMatchResult: Identifiable {
    var id: String { route.id }
    var route: RecurringRoute
    var pickupDistanceMeters: Double
    var reliabilityScore: Double
    var routeOverlapScore: Double
    var estimatedDetourMinutes: Double
    var recurringRiderPriority: Bool
    var availableSeats: Int
    var rankingScore: Double
}

struct CommuteRideCalendarItem: Identifiable {
    var id: String { rideInstanceId ?? "\(routeId)-\(date.timeIntervalSince1970)" }
    /// Real `commute_ride_instances.id` when known. Powers the skip-a-day
    /// action; nil for synthesized rows that were generated locally.
    var rideInstanceId: String? = nil
    var date: Date
    var routeId: String
    var driverName: String
    var startLocation: String
    var endLocation: String
    var pickupPoint: RoutePoint
    var dropPoint: RoutePoint
    var rideStatus: CommuteRideStatus
}

struct DriverRouteDashboard: Identifiable {
    var id: String { route.id }
    var route: RecurringRoute
    var subscribedRiders: [RouteSubscription]
    var upcomingRides: [CommuteRideInstance]
}

struct ChatThread: Codable, Equatable, Identifiable {
    var id: String
    var tripId: String
    var title: String
    var lastMessage: String
    var unreadCount: Int
}

/// Local-only status for a chat message. Server payloads omit it
/// (defaults to `.sent`); the iOS optimistic-send path uses `.sending`
/// while the network call is in flight and `.failed` when it errors,
/// so the bubble can render a clock / red retry indicator instead
/// of silently disappearing on the next refresh.
enum ChatMessageDeliveryState: String, Codable, Equatable {
    case sending, sent, failed
}

struct ChatMessage: Codable, Equatable, Identifiable {
    var id: String
    var threadId: String
    var sender: ChatSender
    var text: String
    var timestamp: Date
    /// Local-only status; defaults to `.sent`. Skipped during
    /// (de)serialization because the server doesn't carry it.
    var deliveryState: ChatMessageDeliveryState = .sent

    init(id: String, threadId: String, sender: ChatSender, text: String,
         timestamp: Date, deliveryState: ChatMessageDeliveryState = .sent) {
        self.id = id
        self.threadId = threadId
        self.sender = sender
        self.text = text
        self.timestamp = timestamp
        self.deliveryState = deliveryState
    }

    private enum CodingKeys: String, CodingKey {
        case id, threadId, sender, text, timestamp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.threadId = try c.decode(String.self, forKey: .threadId)
        self.sender = try c.decode(ChatSender.self, forKey: .sender)
        self.text = try c.decode(String.self, forKey: .text)
        // Backend serialises chat timestamps as `timestamp_ms` (Number)
        // rather than the ISO string the global decoder expects. Try
        // ms-since-epoch first, fall back to a Date decoded via the
        // outer decoder's strategy so legacy payloads still parse.
        if let ms = try? c.decode(Double.self, forKey: .timestamp) {
            self.timestamp = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        }
        self.deliveryState = .sent
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(threadId, forKey: .threadId)
        try c.encode(sender, forKey: .sender)
        try c.encode(text, forKey: .text)
        try c.encode(timestamp, forKey: .timestamp)
    }
}

struct User: Equatable {
    var id: String
    var name: String
    var rating: Double
    var initial: String { String(name.prefix(1)).uppercased() }
}

struct PlaceSuggestion: Codable, Identifiable, Equatable {
    var id: String { displayName + String(lat) }
    var displayName: String
    var lat: Double
    var lon: Double

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case lat
        case lon
    }
}

// MARK: - Helpers

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
