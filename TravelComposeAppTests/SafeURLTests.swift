import Foundation
import Testing
@testable import TravelComposeApp

// MARK: - SafeURL tests
//
// The Apple R&D audit flagged URL force-unwraps as the #1 source of
// production crashes. The `SafeURL.swift` helper replaces them with
// safe constructors. These tests pin the helper's behaviour so a
// future refactor doesn't quietly re-introduce the unwrap pattern.

@Suite("SafeURL helpers")
struct SafeURLTests {

    // MARK: URL.safe(_:)

    @Test("safe(_:) returns Some for well-formed URLs")
    func safeReturnsValidURL() {
        #expect(URL.safe("https://voygo.app") != nil)
        #expect(URL.safe("voygo://routes/abc-123") != nil)
        #expect(URL.safe("tel://+60123456789") != nil)
    }

    @Test("safe(_:) returns nil for empty input")
    func safeReturnsNilOnEmpty() {
        #expect(URL.safe("") == nil)
    }

    // Note: Foundation accepts surprisingly liberal URL strings —
    // for example "not a url" actually parses as a relative URL.
    // We don't pin those edge cases here because they may shift
    // across OS versions; we only pin the happy path + empty-string.

    // MARK: URL.staticURL(_:)
    //
    // In DEBUG, the helper traps via fatalError on bad input — we
    // can't test that path without crashing the test runner. In
    // release builds it returns `data:,` as a fallback. We test the
    // happy path (the only safe path to exercise).

    @Test("staticURL returns the parsed URL when valid")
    func staticURLValid() {
        let url = URL.staticURL("https://api.example.com/v1")
        #expect(url.absoluteString == "https://api.example.com/v1")
    }

    @Test("staticURL preserves voygo:// scheme")
    func staticURLCustomScheme() {
        let url = URL.staticURL("voygo://routes/test")
        #expect(url.scheme == "voygo")
        #expect(url.host == "routes")
    }

    // MARK: URL.withQuery(base:items:)

    @Test("withQuery appends a single item")
    func withQuerySingle() {
        let base = URL(string: "https://api.example.com/users")!
        let result = URL.withQuery(base: base, items: [URLQueryItem(name: "limit", value: "20")])
        #expect(result.query == "limit=20")
        #expect(result.path == "/users")
    }

    @Test("withQuery appends multiple items in order")
    func withQueryMultiple() {
        let base = URL(string: "https://api.example.com/search")!
        let result = URL.withQuery(base: base, items: [
            URLQueryItem(name: "q",     value: "klcc"),
            URLQueryItem(name: "limit", value: "10")
        ])
        #expect(result.query == "q=klcc&limit=10")
    }

    @Test("withQuery returns base URL unchanged when items list is empty")
    func withQueryEmptyItems() {
        let base = URL(string: "https://api.example.com/users")!
        let result = URL.withQuery(base: base, items: [])
        #expect(result.absoluteString == "https://api.example.com/users")
    }

    @Test("withQuery percent-encodes values with reserved characters")
    func withQueryPercentEncoding() {
        let base = URL(string: "https://api.example.com/search")!
        let result = URL.withQuery(base: base, items: [
            URLQueryItem(name: "q", value: "Penang Sentral")
        ])
        // URLComponents handles the encoding; the space becomes %20.
        #expect(result.query == "q=Penang%20Sentral")
    }

    @Test("withQuery handles nil values gracefully")
    func withQueryNilValue() {
        let base = URL(string: "https://api.example.com/search")!
        let result = URL.withQuery(base: base, items: [
            URLQueryItem(name: "filter", value: nil)
        ])
        // URLComponents encodes nil-value query items as bare key.
        #expect(result.query == "filter")
    }
}
