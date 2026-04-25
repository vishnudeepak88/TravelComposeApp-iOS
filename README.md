# TravelComposeApp iOS

This is a native SwiftUI/Xcode conversion of the original Android Jetpack Compose Voygo commute app.

Open `TravelComposeApp.xcodeproj` in Xcode, select an iPhone simulator or a connected iPhone, and build the `TravelComposeApp` scheme.

The iOS port includes:

- Phone OTP sign-in flow.
- Commute route search.
- Route detail and subscription flow.
- My subscriptions with pause, resume, and cancel actions.
- Driver route dashboard with schedule and active status controls.
- Upcoming commute calendar.
- Inbox and chat thread.
- Profile, privacy/help, and identity verification screens.
- Reused launcher artwork from the Android project as the iOS app icon.

The backend from the original archive remains Android/backend-side code. This iOS project uses in-memory sample data so it can build and run immediately; wire `AppStore` to your production API when the backend endpoints are ready for iOS.
