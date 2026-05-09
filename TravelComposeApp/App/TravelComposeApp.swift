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
                }
                .onOpenURL { url in
                    // Closes the loop opened in `AppStore.startCharge`: when
                    // the rider returns from the Billplz hosted checkout via
                    // `voygo://payments/return?paid=true&id=…`, this fires
                    // and AppStore dismisses the SFSafariViewController +
                    // refreshes payments.
                    store.handlePaymentReturn(url: url)
                }
        }
    }
}
