---
name: ios-swiftui-bootstrap
description: Stand up a new iOS 26 + Swift 6 + @Observable SwiftUI app with central AppStore, shared AppRoute, custom nav chrome, and design-token plumbing. Use when starting a new SwiftUI app or migrating an existing one onto modern primitives.
---

## When to use

- A fresh SwiftUI app that should match modern iOS conventions out of
  the gate (no ObservableObject + @StateObject + @EnvironmentObject).
- An existing app on iOS 17/Swift 5/legacy patterns you want to bring
  forward to iOS 26 + Swift 6 + `@Observable`.
- Any project that already uses one of: per-tab `Route` enums (each
  defined locally), separate `VoygoNavBar` + `VPolishedNavBar`-style
  duplication, or magic-number bottom paddings for a custom tab bar.

## Prerequisites

- Xcode 16+ (iOS 26 SDK).
- A target you control end-to-end (this skill rewrites the app entry
  point and the nav stack).
- A target deployment of iOS 26 if you want strict `@Observable`;
  iOS 17+ for the same APIs in the older syntax.

## Recipe

### 1 · Build settings

In `project.pbxproj`, both Debug + Release configs:

```
IPHONEOS_DEPLOYMENT_TARGET = 26.0;   // or 17.0 if you must
SWIFT_VERSION = 6.0;
```

Skip `SWIFT_STRICT_CONCURRENCY = complete` for now — Swift 6 default
mode is enough and `complete` surfaces a long tail of Sendable
diagnostics on third-party (Apple-Framework) types.

### 2 · App entry

```swift
import SwiftUI

@main
struct MyApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { url in store.handleDeepLink(url) }
        }
    }
}
```

Note: `@State` + `.environment(store)`, not `@StateObject` +
`.environmentObject`. The store class is `@Observable`.

### 3 · `AppStore` (the central state)

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    private(set) var isAuthenticated = false
    private(set) var currentUser = User(id: "", name: "")
    var routes: [Route] = []
    var subscriptions: [Subscription] = []
    // ... domain collections

    /// Counter that bumps on global refresh so views can react without
    /// diffing arrays themselves.
    private(set) var dataTick: Int = 0

    func refreshAll() async {
        guard isAuthenticated else { return }
        do {
            async let r = APIClient.routes()
            async let s = APIClient.subscriptions()
            routes = try await r
            subscriptions = try await s
            dataTick &+= 1
        } catch APIError.unauthorized {
            clearSession()
        } catch {
            // best-effort
        }
    }
}
```

Consumer views:

```swift
@Environment(AppStore.self) private var store
```

### 4 · Centralized navigation

Define **one** route enum for the whole app, not per-tab:

```swift
enum AppRoute: Hashable {
    case findRides
    case routeDetails(id: String)
    case wallet
    case notifications
    // ...
}
```

Plus a single destination map as a `ViewModifier`:

```swift
struct AppRouteDestinations: ViewModifier {
    @Binding var path: [AppRoute]

    func body(content: Content) -> some View {
        content.navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .findRides: FindView(onBack: pop)
            case .routeDetails(let id): RouteDetailsView(id: id, onBack: pop)
            case .wallet: WalletView(onBack: pop)
            case .notifications: NotificationsView(onBack: pop)
            }
        }
    }
    private func pop() { if !path.isEmpty { path.removeLast() } }
}

extension View {
    func appRouteDestinations(path: Binding<[AppRoute]>) -> some View {
        modifier(AppRouteDestinations(path: path))
    }
}
```

Each tab root just holds its own `[AppRoute]`:

```swift
struct HomeTab: View {
    @State private var path: [AppRoute] = []
    var body: some View {
        NavigationStack(path: $path) {
            HomeView(onTap: { path.append(.findRides) })
                .appRouteDestinations(path: $path)
                .navigationBarHidden(true)
                .enableSwipeBack()  // see ios-system-integrations skill
        }
    }
}
```

### 5 · One nav-bar component

Pick a single custom `NavBar` component (e.g. `VPolishedNavBar`) and
delete any duplicate. Each pushed screen takes an optional `onBack`:

```swift
struct VPolishedNavBar<Trailing: View>: View {
    let title: String
    var kicker: String? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder let trailing: () -> Trailing
    // body: chevron when onBack non-nil, kicker (small caps) above title
}
```

When the screen is a tab root, pass `onBack: nil` so no chevron renders.

### 6 · Tab-bar safe-area helper

One constant, one modifier. Replaces hand-tuned bottom paddings:

```swift
enum VTabBarLayout {
    static let clearance: CGFloat = 110
}

extension View {
    func tabBarClearance() -> some View {
        padding(.bottom, VTabBarLayout.clearance)
    }
}
```

### 7 · One @Observable `ViewModel` per complex screen

```swift
@MainActor
@Observable
final class FindCommuteViewModel {
    var query = ""
    var results: [RouteMatch] = []
    var isSearching = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()
        isSearching = true
        searchTask = Task { /* … */ }
    }
}
```

Use `@ObservationIgnored` on Task properties — they shouldn't trigger
view re-renders.

Consumer:

```swift
struct FindView: View {
    @State private var vm = FindCommuteViewModel()
    var body: some View { /* binds to vm */ }
}
```

### 8 · Typed `AppError`

Don't use `.message(String)` for everything:

```swift
enum AppError: LocalizedError, Equatable {
    case message(String)
    case unauthorized
    case network
    case validation(String)
    case server(code: Int)
    case decoding

    var errorDescription: String? { /* … */ }

    static func from(_ error: Error) -> AppError {
        switch error {
        case APIError.unauthorized:    return .unauthorized
        case APIError.networkError:    return .network
        case let APIError.serverError(c): return .server(code: c)
        case APIError.decodingError:   return .decoding
        case let appErr as AppError:   return appErr
        default: return .message(error.localizedDescription)
        }
    }
}
```

Pair with a `VErrorBanner` atom that branches on the case (see
`ios-design-system-port`).

## Pitfalls

- **`@StateObject` is gone, but `@State` + `@Observable` only works
  if your class is annotated `@Observable`.** A plain class held in
  `@State` won't trigger view updates.
- **`@MainActor @Observable final class` + `@State` initializer.**
  The `@State` initializer evaluates lazily on the main actor in iOS
  17+, so this combo works without a custom DI container.
- **NavigationStack(path: $path) drops state on app-cold-start.**
  If you need restoration, persist your `[AppRoute]` to UserDefaults
  + reload on launch.
- **`.navigationBarHidden(true)` kills swipe-back.** See
  `ios-system-integrations` for the UIKit interop fix.
- **Tab bar overlay covers content.** Always reserve
  `tabBarClearance()` at the bottom of every tab root's ScrollView.

## Adjacent skills

- `ios-design-system-port` — palette + atoms + semantic fonts.
- `backend-ios-pairing` — wire `AppStore` to a real REST API.
- `ios-system-integrations` — swipe-back, share, SMS, photo picker.

## Reference implementation

Voygo at commit `599dd5b`:
- `TravelComposeApp/App/TravelComposeApp.swift` — entry
- `TravelComposeApp/Core/AppStore.swift` — state container
- `TravelComposeApp/App/AppRoute.swift` — shared routes + modifier
- `TravelComposeApp/App/Navigation.swift` — tabs + tab bar
- `TravelComposeApp/Core/Polished.swift` — design system + atoms
