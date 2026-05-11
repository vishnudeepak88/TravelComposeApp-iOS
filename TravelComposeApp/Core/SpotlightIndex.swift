import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - Spotlight Indexing
//
// Indexes the user's known carpool routes into iOS Spotlight so they
// appear in system-wide search and Siri Suggestions. A rider typing
// "KLCC" into Spotlight sees their saved KLCC-bound Voygo route as a
// hit, taps it, and lands on the route details screen.
//
// Powered by CoreSpotlight (no entitlement needed — works on Personal
// Team builds). Indexing happens on AppStore.refreshRoutes() and on
// favorites changes; the index updates incrementally rather than
// rebuilding from scratch each time.
//
// Privacy: only the user's OWN routes are indexed (favorites +
// subscriptions). We never index search results or other users'
// route metadata into Spotlight.

enum VoygoSpotlight {
    /// Domain identifier — bucket for all our items so we can purge
    /// them in one call on logout.
    static let routeDomain = "com.voygo.travelcomposeapp.routes"

    /// UTI identifier the items are filed under. UTType.item is the
    /// generic "system thing" identifier; specific types are reserved
    /// for documents/photos.
    private static let routeContentType = UTType.item.identifier

    /// Indexes a single route. Caller passes the minimal identifying
    /// fields; we expand to a CSSearchableItemAttributeSet that
    /// Spotlight understands. Re-indexing the same routeId overwrites
    /// the previous entry.
    static func index(
        routeId: String,
        driverName: String,
        startLocation: String,
        endLocation: String,
        departureTime: String,
        pricePerSeatMyr: Int
    ) {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)
        attrs.title = "\(startLocation) → \(endLocation)"
        attrs.contentDescription = "with \(driverName) · \(departureTime) · RM \(pricePerSeatMyr)/seat"
        // Keywords help Spotlight match partial typing. We seed the
        // common shapes: driver, start, end, the brand.
        attrs.keywords = [
            "Voygo",
            "carpool",
            driverName,
            startLocation,
            endLocation,
            "RM\(pricePerSeatMyr)"
        ]
        // Domain bucket lets us purge all routes on logout.
        let item = CSSearchableItem(
            uniqueIdentifier: "voygo.route.\(routeId)",
            domainIdentifier: routeDomain,
            attributeSet: attrs
        )
        // `expirationDate` matches the Spotlight default (8 days
        // for indexable items) — Spotlight auto-prunes after that
        // so a stale route doesn't haunt Search forever.
        item.expirationDate = Date().addingTimeInterval(7 * 86_400)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                // Indexing failure is non-fatal. The app keeps
                // working; the route just doesn't show up in Spotlight.
                print("[spotlight] index failed: \(error.localizedDescription)")
            }
        }
    }

    /// Indexes a batch of routes in one round-trip. Faster than
    /// calling `index` in a loop when AppStore refreshes all routes.
    static func indexBatch(_ routes: [(id: String, driverName: String, start: String, end: String, time: String, price: Int)]) {
        let items: [CSSearchableItem] = routes.map { r in
            let attrs = CSSearchableItemAttributeSet(contentType: .item)
            attrs.title = "\(r.start) → \(r.end)"
            attrs.contentDescription = "with \(r.driverName) · \(r.time) · RM \(r.price)/seat"
            attrs.keywords = ["Voygo", "carpool", r.driverName, r.start, r.end]
            let item = CSSearchableItem(
                uniqueIdentifier: "voygo.route.\(r.id)",
                domainIdentifier: routeDomain,
                attributeSet: attrs
            )
            item.expirationDate = Date().addingTimeInterval(7 * 86_400)
            return item
        }
        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                print("[spotlight] batch index failed: \(error.localizedDescription)")
            }
        }
    }

    /// Removes all indexed Voygo routes. Called on logout so the
    /// previous user's commute corridors don't leak into Spotlight
    /// for the next user of the device.
    static func clearAll() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [routeDomain]
        ) { error in
            if let error {
                print("[spotlight] purge failed: \(error.localizedDescription)")
            }
        }
    }

    /// Parses a Spotlight tap-through. The user activity comes via
    /// `.onContinueUserActivity(CSSearchableItemActionType)` in the
    /// SwiftUI root. We extract the routeId and post the existing
    /// `.voygoOpenRoute` notification so the app deep-links the same
    /// way it does for share URLs.
    static func handleSpotlightActivity(_ activity: NSUserActivity) {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              id.hasPrefix("voygo.route.") else { return }
        let routeId = String(id.dropFirst("voygo.route.".count))
        NotificationCenter.default.post(
            name: .voygoOpenRoute,
            object: nil,
            userInfo: ["routeId": routeId]
        )
    }
}
