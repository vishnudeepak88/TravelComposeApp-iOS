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
        }
    }
}
