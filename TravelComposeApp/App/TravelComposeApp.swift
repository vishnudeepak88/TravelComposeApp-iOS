import SwiftUI

@main
struct TravelComposeApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
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
