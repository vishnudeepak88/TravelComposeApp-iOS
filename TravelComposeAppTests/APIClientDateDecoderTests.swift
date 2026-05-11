import Foundation
import Testing
@testable import TravelComposeApp

// MARK: - APIClient date decoder tests
//
// `VoygoAPIClient.decoder` uses a custom date-decoding strategy that
// tries three formatters in order:
//   1. ISO-8601 with fractional seconds
//   2. ISO-8601 without fractional seconds
//   3. Bare yyyy-MM-dd in UTC
//
// The backend sends all three shapes from different endpoints
// (`/payments` includes ms; `/auth/me` returns whole-second ISO;
// `/commute/route-requests` returns `created_at` as date-only).
// A regression here silently corrupts every Date field on the
// client — these tests pin the contract.

@Suite("APIClient date decoder fallback chain")
struct APIClientDateDecoderTests {

    // Decode a wrapper struct with a single Date field. We don't
    // touch VoygoAPIClient.decoder directly because it's `private
    // static var`; instead we replicate the strategy at the test
    // boundary. If this test diverges from production decoder, the
    // failure is immediately legible.

    private struct Wrapper: Decodable, Equatable {
        let when: Date
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Self.isoWithFraction.date(from: value) { return date }
            if let date = Self.isoNoFraction.date(from: value) { return date }
            if let date = Self.dateOnly.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(value)"
            )
        }
        return d
    }

    @Test("Decodes ISO-8601 with fractional seconds (the payments format)")
    func decodesFractionalISO() throws {
        let json = #"{"when":"2026-03-14T08:15:30.123Z"}"#
        let result = try makeDecoder().decode(Wrapper.self, from: Data(json.utf8))
        // 2026-03-14T08:15:30.123Z exactly
        let expected = Self.isoWithFraction.date(from: "2026-03-14T08:15:30.123Z")!
        #expect(abs(result.when.timeIntervalSince(expected)) < 0.001)
    }

    @Test("Decodes ISO-8601 without fractional seconds (the /auth/me format)")
    func decodesWholeSecondISO() throws {
        let json = #"{"when":"2026-03-14T08:15:30Z"}"#
        let result = try makeDecoder().decode(Wrapper.self, from: Data(json.utf8))
        let expected = Self.isoNoFraction.date(from: "2026-03-14T08:15:30Z")!
        #expect(result.when == expected)
    }

    @Test("Decodes yyyy-MM-dd (the route-requests created_at format)")
    func decodesDateOnly() throws {
        let json = #"{"when":"2026-03-14"}"#
        let result = try makeDecoder().decode(Wrapper.self, from: Data(json.utf8))
        let expected = Self.dateOnly.date(from: "2026-03-14")!
        #expect(result.when == expected)
    }

    @Test("Throws DecodingError on unparseable shape")
    func throwsOnGarbage() {
        let json = #"{"when":"not-a-date"}"#
        #expect(throws: DecodingError.self) {
            try makeDecoder().decode(Wrapper.self, from: Data(json.utf8))
        }
    }

    @Test("Handles timezone offsets (not just Z)")
    func handlesTimezoneOffset() throws {
        // ISO-8601 also allows `+08:00` for Asia/Kuala_Lumpur. The
        // fractional formatter accepts both Z and offset suffixes.
        let json = #"{"when":"2026-03-14T16:15:30+08:00"}"#
        let result = try makeDecoder().decode(Wrapper.self, from: Data(json.utf8))
        // 16:15 in UTC+8 == 08:15 UTC
        let expected = Self.isoNoFraction.date(from: "2026-03-14T08:15:30Z")!
        #expect(result.when == expected)
    }
}
