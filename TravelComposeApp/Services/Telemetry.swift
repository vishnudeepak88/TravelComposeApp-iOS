import Foundation
import os.log

// MARK: - Telemetry abstraction.
//
// Closes Engineering gap #9 from the playbook: "We can't make any of the
// pricing/funnel decisions without instrumentation." This is a thin protocol
// so we can ship today with a console logger and later swap in PostHog,
// Amplitude, or a homegrown ingest endpoint without touching call sites.

protocol TelemetryClient {
    func track(_ event: TelemetryEvent)
    func identify(userId: String, traits: [String: TelemetryValue])
    func reset()
}

struct TelemetryEvent {
    var name: String
    var properties: [String: TelemetryValue]

    init(_ name: String, _ properties: [String: TelemetryValue] = [:]) {
        self.name = name
        self.properties = properties
    }
}

/// Closed-shape value type so events stay JSON-encodable end-to-end.
enum TelemetryValue {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var jsonValue: Any {
        switch self {
        case .string(let s): return s
        case .int(let i):    return i
        case .double(let d): return d
        case .bool(let b):   return b
        case .null:          return NSNull()
        }
    }
}

extension TelemetryValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .string(value) }
}
extension TelemetryValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self = .int(value) }
}
extension TelemetryValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) { self = .double(value) }
}
extension TelemetryValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

// MARK: - Default implementation: structured os_log.
// Good enough for development and TestFlight builds; swap before public launch.

final class ConsoleTelemetryClient: TelemetryClient {
    private let log = Logger(subsystem: "app.voygo", category: "telemetry")
    private var userId: String?

    func identify(userId: String, traits: [String: TelemetryValue]) {
        self.userId = userId
        log.info("identify user=\(userId, privacy: .private) traits=\(traits.count)")
    }

    func track(_ event: TelemetryEvent) {
        let payload = event.properties.mapValues { $0.jsonValue }
        let serialized = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "{}"
        log.info("event=\(event.name, privacy: .public) user=\(self.userId ?? "anon", privacy: .private) props=\(serialized, privacy: .public)")
    }

    func reset() {
        userId = nil
    }
}

// MARK: - Catalog of named events.
// Putting these in one place keeps the analytics taxonomy honest. If a new
// surface adds an event, it gets a constant here so we don't end up with
// "search_completed" and "searchCompleted" both in flight.

enum TelemetryEvents {
    static let appOpened             = "app_opened"
    static let signInStarted         = "sign_in_started"
    static let signInCompleted       = "sign_in_completed"
    static let signedOut             = "signed_out"
    static let routeSearched         = "route_searched"
    static let routeViewed           = "route_viewed"
    static let subscriptionCreated   = "subscription_created"
    static let subscriptionPaused    = "subscription_paused"
    static let subscriptionResumed   = "subscription_resumed"
    static let subscriptionCancelled = "subscription_cancelled"
    static let driverRouteCreated    = "driver_route_created"
    static let driverRoutePaused     = "driver_route_paused"
    static let driverRouteResumed    = "driver_route_resumed"
    static let kycSubmitted          = "kyc_submitted"
    static let messageSent           = "message_sent"
    static let cancellationPenalty   = "cancellation_penalty"
}
