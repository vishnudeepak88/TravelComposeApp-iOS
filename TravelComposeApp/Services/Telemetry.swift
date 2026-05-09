import Foundation
import os.log
import UIKit

// MARK: - Telemetry abstraction.
//
// Closes Engineering gap #9 from the playbook: "We can't make any of the
// pricing/funnel decisions without instrumentation." Thin protocol so we
// can ship today with a console+remote logger and later swap in PostHog
// without touching call sites.

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

// MARK: - Console implementation (always on, useful for dev + TestFlight).

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

// MARK: - Remote implementation: best-effort POST to /telemetry/events.
//
// Buffers events in memory and flushes on a debounce or when the buffer
// reaches `batchSize`. Drops on failure — telemetry must never block UX,
// and the backend treats this endpoint as fire-and-forget (HTTP 204).

actor RemoteTelemetryBuffer {
    /// Each pending entry is the already-JSON-encoded event body. Keeping
    /// the data type out of `Any` lets the actor stay Sendable-clean.
    private var pending: [Data] = []
    private var flushTask: Task<Void, Never>?
    private let batchSize: Int = 25
    private let debounceNanos: UInt64 = 5 * 1_000_000_000  // 5s

    private let endpoint: URL
    private let sessionId: String
    private let appVersion: String
    private let platform: String

    init(endpoint: URL) {
        self.endpoint = endpoint
        self.sessionId = UUID().uuidString
        self.appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        self.platform = "ios"
    }

    func enqueue(eventJson: Data) {
        pending.append(eventJson)
        if pending.count >= batchSize {
            scheduleFlush(immediate: true)
        } else {
            scheduleFlush(immediate: false)
        }
    }

    private func scheduleFlush(immediate: Bool) {
        flushTask?.cancel()
        let delay = immediate ? UInt64(0) : debounceNanos
        flushTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            await self?.flush()
        }
    }

    func flush() async {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll()

        // Build the envelope by hand so we don't have to round-trip the
        // already-encoded event bodies through JSONSerialization.
        var bodyString = "{\"session_id\":\"\(sessionId)\","
        bodyString += "\"app_version\":\"\(appVersion)\","
        bodyString += "\"platform\":\"\(platform)\","
        bodyString += "\"events\":["
        for (i, eventData) in batch.enumerated() {
            if i > 0 { bodyString += "," }
            bodyString += String(data: eventData, encoding: .utf8) ?? "{}"
        }
        bodyString += "]}"
        guard let body = bodyString.data(using: .utf8) else { return }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = SessionStorage.authToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        _ = try? await URLSession.shared.data(for: req)
        // Intentionally swallow errors — telemetry is best-effort.
    }
}

final class RemoteTelemetryClient: TelemetryClient {
    private let buffer: RemoteTelemetryBuffer
    private let console: ConsoleTelemetryClient
    private var userId: String?

    init(baseURL: URL) {
        self.buffer = RemoteTelemetryBuffer(endpoint: baseURL.appendingPathComponent("telemetry/events"))
        self.console = ConsoleTelemetryClient()
    }

    func identify(userId: String, traits: [String: TelemetryValue]) {
        self.userId = userId
        console.identify(userId: userId, traits: traits)
    }

    func track(_ event: TelemetryEvent) {
        console.track(event)
        var props = event.properties.mapValues { $0.jsonValue }
        if let uid = userId { props["user_id"] = uid }
        // Encode synchronously so we never send `Any` across the actor
        // boundary (Swift 6 strict concurrency rejects that).
        let payload: [String: Any] = ["name": event.name, "props": props]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        Task { [buffer] in
            await buffer.enqueue(eventJson: data)
        }
    }

    func reset() {
        userId = nil
        console.reset()
        Task { [buffer] in await buffer.flush() }
    }
}

// MARK: - Shared singleton — init once at app boot.

enum Telemetry {
    nonisolated(unsafe) static var shared: TelemetryClient = RemoteTelemetryClient(baseURL: VoygoAPIClient.baseURL)

    static func track(_ name: String, _ properties: [String: TelemetryValue] = [:]) {
        shared.track(TelemetryEvent(name, properties))
    }
}

// MARK: - Catalog of named events.

enum TelemetryEvents {
    static let appOpened             = "app_opened"
    static let signInStarted         = "sign_in_started"
    static let signInCompleted       = "sign_in_completed"
    static let signedOut             = "signed_out"
    static let homeBookARideTapped   = "home_book_a_ride_tapped"
    static let routeSearched         = "route_searched"
    static let routeViewed           = "route_viewed"
    static let subscribeStarted      = "subscribe_started"
    static let subscriptionCreated   = "subscription_created"
    static let subscriptionPaused    = "subscription_paused"
    static let subscriptionResumed   = "subscription_resumed"
    static let subscriptionCancelled = "subscription_cancelled"
    static let driverRouteCreated    = "driver_route_created"
    static let driverRoutePaused     = "driver_route_paused"
    static let driverRouteResumed    = "driver_route_resumed"
    static let kycSubmitted          = "kyc_submitted"
    static let kycDocUploaded        = "kyc_doc_uploaded"
    static let liveTripSosTapped     = "live_trip_sos_tapped"
    static let messageSent           = "message_sent"
    static let cancellationPenalty   = "cancellation_penalty"
}
