import CoreSpotlight
import SwiftUI

@main
struct TravelComposeApp: App {
    /// AppDelegate adapter — owns APNs callbacks (push token,
    /// notification tap → deep link). UIKit lifecycle still drives
    /// these in iOS 26; SwiftUI's pure-Scene path doesn't expose them.
    @UIApplicationDelegateAdaptor(VoygoAppDelegate.self) private var appDelegate

    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onAppear {
                    // Make the store available to the AppDelegate so
                    // its APNs callback can hand the token over.
                    VoygoAppDelegate.store = store
                    Telemetry.track(TelemetryEvents.appOpened)
                }
                .onOpenURL { url in
                    // AppStore dispatches: voygo://routes/<id> → posts
                    // .voygoOpenRoute; voygo://payments/return → closes
                    // the Billplz hosted-checkout loop.
                    store.handleDeepLink(url: url)
                }
                // Spotlight tap-through: Voygo routes that the user
                // indexed via CoreSpotlight (in SpotlightIndex.swift)
                // appear as system-wide search results. Tapping one
                // hands control back to us via this activity type,
                // and the helper extracts the routeId + posts the
                // existing voygoOpenRoute notification so the deep
                // link plumbing handles the rest.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    VoygoSpotlight.handleSpotlightActivity(activity)
                }
        }
    }
}
