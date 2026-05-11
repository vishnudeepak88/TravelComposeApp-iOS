import Foundation
import Testing
@testable import TravelComposeApp

// MARK: - AppStore deep-link parsing tests
//
// `AppStore.handleDeepLink(url:)` is the single dispatcher for every
// inbound URL the app sees — share-links, APNs taps, Spotlight
// hand-offs, Billplz checkout returns. A bug here silently breaks the
// most important re-engagement vectors. These tests pin the parser's
// behavior so a future refactor can't quietly regress them.

@Suite("AppStore deep-link parsing")
@MainActor
struct AppStoreDeepLinkTests {

    @Test("voygo://routes/<id> posts .voygoOpenRoute with routeId")
    func routesURLPostsNotification() async {
        let store = AppStore()
        let url = URL(string: "voygo://routes/route-abc-123")!
        await confirmation(expectedCount: 1) { fired in
            let token = NotificationCenter.default.addObserver(
                forName: .voygoOpenRoute, object: nil, queue: .main
            ) { note in
                if let id = note.userInfo?["routeId"] as? String, id == "route-abc-123" {
                    fired()
                }
            }
            defer { NotificationCenter.default.removeObserver(token) }
            store.handleDeepLink(url: url)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @Test("voygo://routes/ with empty id does not crash")
    func routesEmptyIdNoCrash() {
        let store = AppStore()
        // Trailing-slash-with-empty-segment shouldn't crash — at worst
        // it's a no-op. The parser must guard the empty-string case.
        let url = URL(string: "voygo://routes/")!
        store.handleDeepLink(url: url)
        // Reaching here without throw == pass.
    }

    @Test("Non-voygo scheme is ignored")
    func nonVoygoSchemeIgnored() async {
        let store = AppStore()
        let url = URL(string: "https://example.com/routes/abc")!
        // Should not post .voygoOpenRoute; we wait briefly then
        // confirm no fire.
        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: .voygoOpenRoute, object: nil, queue: .main
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }
        store.handleDeepLink(url: url)
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(fired == false)
    }

    @Test("voygo://payments/return triggers checkout dismissal")
    func paymentsReturnDismissesCheckout() async {
        let store = AppStore()
        let before = store.checkoutDismissalSignal
        let url = URL(string: "voygo://payments/return")!
        store.handleDeepLink(url: url)
        // `checkoutDismissalSignal` is a monotonically-incrementing
        // counter view models observe to close the BillPlz sheet.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.checkoutDismissalSignal > before)
    }
}
