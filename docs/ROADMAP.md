# Voygo — Roadmap for the deferred v1 gaps

For each item still listed as "deferred" in `docs/UX_AUDIT_AFTER.md`
and `docs/ARCHITECTURE.md`, this doc lays out:

- **What it actually is** in product terms.
- **Why we deferred it** — backend, third-party, or scope.
- **How we'd implement it** — sketched code on the iOS side, the
  backend contract it depends on, and a build order.
- **Honest effort.**

Items are sorted by what's pure-iOS (could ship next session) → mostly
iOS with a thin backend → backend-heavy → external SDK / weeks-long.

---

## 1. AppError UI surface · pure iOS · ~1 day

### Why deferred
We typed `AppError` (`unauthorized / network / validation / server / decoding`) in commit `34aaea9`, but every call site still renders `error.localizedDescription` instead of branching on the case. Surfacing structured error UX across all screens needs a careful per-screen pass.

### How to do it

1. **Add a `VErrorBanner` atom** in `Core/Polished.swift`:

```swift
struct VErrorBanner: View {
    let error: AppError
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(VPalette.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .heavy))
                Text(error.localizedDescription ?? "")
                    .font(.system(size: 12)).foregroundColor(VPalette.textSec)
            }
            Spacer()
            if let onRetry, isRetryable {
                Button("Retry", action: onRetry)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(VPalette.primary)
            }
        }
        .padding(12)
        .background(VPalette.dangerContainer)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var icon: String {
        switch error {
        case .unauthorized: return "lock.slash.fill"
        case .network:      return "wifi.slash"
        case .server:       return "exclamationmark.icloud.fill"
        default:            return "exclamationmark.triangle.fill"
        }
    }
    private var title: String {
        switch error {
        case .unauthorized: return "Sign in again"
        case .network:      return "Offline"
        case .validation:   return "Check your input"
        case .server:       return "Server error"
        case .decoding:     return "Unexpected response"
        case .message:      return "Something went wrong"
        }
    }
    private var isRetryable: Bool {
        if case .unauthorized = error { return false }
        if case .validation   = error { return false }
        return true
    }
}
```

2. **Replace `Text(err.localizedDescription)`** in every screen that consumes a `Result<_, AppError>` with `VErrorBanner(error: err, onRetry: …)`. Wire `.unauthorized` to a "Sign in" CTA that pushes through to `AuthPhoneView`. There are ~15 call sites in AppStore methods that flow into views — `RouteDetailsView`, `MySubscriptionsView`, `KycVerificationView`, `CreateRouteView`, `AuthPhoneView`, `AuthOtpView`, `WalletView` (after refresh).

3. **Add a global "session expired" listener** in `RootView` so any `.unauthorized` from anywhere bounces to login automatically:

```swift
// AppStore-side
private(set) var sessionExpiredTick: Int = 0
private func bounceOnUnauthorized() { sessionExpiredTick &+= 1 }

// RootView
.onChange(of: store.sessionExpiredTick) { _, _ in
    // navigate back to login
}
```

**Effort:** ~1 day mostly grunt work touching ~20 files.

---

## 2. Dynamic Type · pure iOS · ~1 day

### Why deferred
Most fonts use `.font(.system(size: N))` which doesn't scale with iOS Dynamic Type. Migrating to semantic fonts is mechanical but touches every view.

### How to do it

1. **Build a small mapping** in `Core/Polished.swift`:

```swift
extension Font {
    /// Voygo's display ladder. Mirrors the design's exact pixel
    /// sizes at the .large content size, but scales with Dynamic
    /// Type for everything else.
    static let vTitle      = Font.system(.title, design: .default).weight(.black)        // was 28pt
    static let vHeadline   = Font.system(.headline, design: .default).weight(.heavy)     // was 18pt
    static let vBodyHeavy  = Font.system(.body, design: .default).weight(.heavy)         // was 13/14pt
    static let vBody       = Font.system(.body, design: .default)                        // was 12/13pt
    static let vCaption    = Font.system(.caption, design: .default)                     // was 11pt
    static let vMonoSmall  = Font.system(.caption, design: .monospaced).weight(.heavy)
}
```

2. **Replace per-view** with a regex search-and-tame pass:
   - `.font(.system(size: 28, weight: .black))` → `.font(.vTitle)`
   - `.font(.system(size: 13, weight: .heavy))` → `.font(.vBodyHeavy)`
   - …etc.

3. **For `.tracking`** (negative letter-spacing) — keep as a separate modifier; semantic fonts don't carry tracking. The mapping above intentionally drops the bespoke tracking; visually almost identical, accessibility cheaper to maintain.

4. **Test at AX1 / AX5** — most common breakpoint is wallet/trip-history rows where `monospaced` numbers run out of horizontal space. Use `.minimumScaleFactor(0.7)` on those.

**Effort:** ~1 day. Main risk is one-off layouts (the `tracking(-1.4)` on the Wallet hero) breaking; budget time for visual review.

---

## 3. Bahasa Malaysia · pure iOS, needs translator · ~1 day after copy is centralized

### Why deferred
Localization needs `Localizable.strings`, every user-visible string in `Strings.swift`, and an actual translator.

### How to do it

1. **Broaden `Strings.swift`** — currently has ~25 strings, the app uses ~120 visible literals. Sweep every `Text("...")` and `placeholder: "..."` into the enum. Mechanical.

2. **Generate `Localizable.strings`** for `en` and `ms`:

```
"home.bookARide" = "Book a ride";
"home.findRide" = "Find ride";
"home.headingYourWay" = "Heading your way";
…
```

3. **Update `Strings.swift`** to read via `NSLocalizedString`:

```swift
enum S {
    static let homeBookARide = NSLocalizedString("home.bookARide", comment: "Home CTA")
    …
}
```

4. **Add `Localizations` to project settings** (English + Malay), set `CFBundleAllowMixedLocalizations = YES` so users can override per-app.

5. **Translation pass.** In Malay: "Tempah perjalanan", "Cari perjalanan", "Menuju ke arah anda"… Real users in KL can review.

**Effort:** ~1 day after `Strings.swift` is broadened. Can start the broaden + en pass without a translator and invite community translation later.

---

## 4. Wallet + TripHistory skeleton wiring · pure iOS · ~30 min

### Why deferred
Already shipped `VSkeleton` and used it in `RouteDetailsView`. Wallet and TripHistory still spinner-load.

### How to do it

```swift
// WalletView
if isPaymentsLoading && store.payments.isEmpty {
    VStack(spacing: 12) {
        VSkeleton(height: 140, corner: 22)        // hero
        VSkeleton(height: 60,  corner: 16)        // tx row 1
        VSkeleton(height: 60,  corner: 16)        // tx row 2
    }
    .padding(.horizontal, 16)
}

// TripHistoryView — same pattern
```

Track an `@State var isLoading = false` set during `.task` / `refreshable`.

**Effort:** ~30 min.

---

## 5. iPad layout · pure iOS · ~1 week to do well

### Why deferred
Every screen is iPhone-shaped. CLAUDE.md asks for iPad too, but a real iPad layout means rethinking navigation (split view), max widths, multi-column lists.

### How to do it

1. **Replace `MainTabView` on iPad** with `NavigationSplitView`:

```swift
@Environment(\.horizontalSizeClass) private var hSize

if hSize == .compact {
    MainTabView()       // existing
} else {
    NavigationSplitView {
        VoygoSidebar(selectedTab: $selectedTab)   // tab list as sidebar
    } content: {
        switch selectedTab { … }                  // primary content
    } detail: {
        // RouteDetails / Receipt / etc. push into here
    }
}
```

2. **Cap content width** on regular size class so a wide screen doesn't stretch the search card to 1024pt:

```swift
.frame(maxWidth: hSize == .regular ? 720 : .infinity)
```

3. **Multi-column "My subscriptions"** on iPad — `LazyVGrid(columns: [GridItem(.adaptive(minimum: 320))])`.

4. **Multi-pane Inbox** — thread list on the left, conversation on the right (Mail.app pattern).

5. **Test all four orientations** + Stage Manager + multitasking 1/2/3.

**Effort:** ~1 week. Easy to do badly; "iPhone view stretched" is the default and should be avoided.

---

## 6. Telemetry · mostly iOS, thin backend · ~1 day

### Why deferred
`Services/Telemetry.swift` is a stub. We need to pick a vendor and instrument the funnel.

### How to do it

1. **Pick a backend.** Three honest options:
   - **PostHog** (cheap, self-hostable, good iOS SDK).
   - **Amplitude** (richest dashboards, $50+/mo at scale).
   - **MetricKit** (Apple-only, free, but limited to crashes + signposts).

   Recommend PostHog for v1.

2. **Replace the `Telemetry` stub:**

```swift
import PostHog

enum Telemetry {
    static func configure() {
        let config = PostHogConfig(apiKey: AppConfiguration.postHogKey,
                                   host: "https://app.posthog.com")
        PostHogSDK.shared.setup(config)
    }
    static func track(_ event: String, _ properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
    static func identify(userId: String, properties: [String: Any] = [:]) {
        PostHogSDK.shared.identify(userId, userProperties: properties)
    }
}
```

3. **Instrument the funnel** — call `Telemetry.track` at key seams:
   - `home_book_a_ride_tapped`
   - `search_executed { from, to, earliest, latest, results_count }`
   - `route_details_opened { route_id }`
   - `subscribe_started { tier, route_id, amount_myr }`
   - `subscribe_succeeded { booking_id }`
   - `subscribe_failed { reason }`
   - `live_trip_viewed { trip_id }`
   - `live_trip_sos_tapped`
   - `kyc_doc_uploaded { kind }`
   - `chat_message_sent`

4. **Identify the user** on `verifyOtp` success.

5. **Build a funnel dashboard** post-deploy: % of users who tap Book → search → details → subscribe → confirm. That's your activation funnel.

**Effort:** ~1 day (SDK + 10–15 events + identify).

---

## 7. Push notifications · iOS + thin backend · ~3–5 days

### What it is
Native iOS push when a driver accepts a subscription, when a ride is starting in 10 min, when payment fails, etc. Plus the in-app `NotificationsView` reading from a real `/notifications` endpoint.

### How to do it

#### A · Server contract

Backend exposes:

- `POST /devices` — register `{ apns_token, locale }` for the signed-in user.
- `GET /notifications?cursor=…` — paginated list, each row `{ id, kind, title, body, data, created_at, read_at }`.
- `POST /notifications/read` — mark IDs read.
- Backend hits APNs when business events fire.

#### B · iOS register

```swift
// AppDelegate or App init
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
    Task { @MainActor in
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }
}

// AppDelegate
func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    let hex = token.map { String(format: "%02x", $0) }.joined()
    Task { try? await VoygoAPIClient.registerDevice(token: hex) }
}
```

#### C · Notification tap → deep link

```swift
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let routeId = userInfo["route_id"] as? String {
            // Bounce to root → push .routeDetails(routeId:)
            DeepLinkRouter.shared.handle(.routeDetails(routeId: routeId))
        }
        completion()
    }
}
```

#### D · NotificationsView reads from API

Replace the empty placeholder list with:

```swift
@Observable final class NotificationsViewModel {
    var items: [NotificationItem] = []
    var isLoading = false
    var nextCursor: String?

    func load(reset: Bool = false) async {
        isLoading = true; defer { isLoading = false }
        if reset { items = []; nextCursor = nil }
        let page = try? await VoygoAPIClient.notifications(cursor: nextCursor)
        items += page?.items ?? []
        nextCursor = page?.nextCursor
    }
    func markAllRead() async {
        let unread = items.filter { $0.readAt == nil }.map(\.id)
        guard !unread.isEmpty else { return }
        try? await VoygoAPIClient.markRead(ids: unread)
        items = items.map { var x = $0; if x.readAt == nil { x.readAt = .now }; return x }
    }
}
```

#### E · Badge the bell

Add `Notification.Name("voygo.unreadCountChanged")` and have the bell icon on Home read from `store.unreadNotificationsCount`.

**Effort:** ~3–5 days. Server side is half the work; iOS side is the SDK + the deep-link router.

---

## 8. Real driver tracking · iOS + heavy backend · 2–3 weeks

### What it is
LiveTripView's GPS dot moves with the driver's actual location, ETA recomputes from current position.

### How to do it

#### A · Server contract

Two patterns work; pick one:

**Option A — Server-Sent Events (SSE):** simpler, one-direction.
```
GET /rides/{id}/stream  (Accept: text/event-stream)
data: {"lat":3.142,"lng":101.689,"eta_min":11,"status":"en_route"}
```

**Option B — WebSocket:** richer, two-way (driver app + rider app share the channel).
```
wss://api.voygo.app/v1/rides/{id}/ws
```

Recommend SSE for v1: simpler to operate, perfectly fine for one-way push.

#### B · iOS subscriber

```swift
// AppStore extension
func streamRide(_ rideId: String) -> AsyncStream<RideUpdate> {
    AsyncStream { continuation in
        let task = Task {
            let url = AppConfiguration.apiBaseURL.appendingPathComponent("rides/\(rideId)/stream")
            var req = URLRequest(url: url)
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.setValue("Bearer \(SessionStorage.authToken ?? "")", forHTTPHeaderField: "Authorization")
            do {
                let (bytes, _) = try await URLSession.shared.bytes(for: req)
                for try await line in bytes.lines where line.hasPrefix("data:") {
                    let json = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if let data = json.data(using: .utf8),
                       let update = try? JSONDecoder().decode(RideUpdate.self, from: data) {
                        continuation.yield(update)
                    }
                }
            } catch {
                continuation.finish()
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
```

#### C · LiveTripView consumes

```swift
@State private var liveLocation: CLLocationCoordinate2D? = nil
@State private var streamTask: Task<Void, Never>? = nil

.onAppear {
    streamTask = Task {
        for await update in store.streamRide(tripId) {
            liveLocation = .init(latitude: update.lat, longitude: update.lng)
            etaMinutes = update.etaMin
        }
    }
}
.onDisappear { streamTask?.cancel(); streamTask = nil }
```

Then animate the GPS dot's position toward `liveLocation` with `.animation(.easeOut, value: liveLocation)`.

#### D · Driver-side
Driver app sends location every ~5s while a ride is active. We don't have a driver-app codebase yet — it's the same iOS project under a different scheme, or its own. Simplest v1: post `POST /rides/{id}/location { lat, lng }` from a `CLLocationManager.allowsBackgroundLocationUpdates = true` background task.

**Effort:** 2–3 weeks. Half is on the backend (SSE infrastructure, location ingestion); other half is the driver-side app and battery tuning.

---

## 9. Backend `/safety/sos` · iOS-side trivial, backend ~3 days

### What it is
The current SOS opens the SMS composer (good — works without backend). The full loop also pings a backend endpoint that:

- Notifies the rider's saved emergency contacts.
- Notifies Voygo's safety on-call channel.
- Persists the alert with rider, ride, location.
- Optionally calls 999 in MY (PDRM) integration if/when available.

### How to do it

#### Server
```
POST /safety/sos
  Body: { ride_id, lat?, lng?, message }
  Returns: { alert_id, dispatched_to: ["contact:abc", "ops:on_call"] }
```

#### iOS (in addition to the existing SMS composer)
```swift
private func fireSOS() async {
    showSOSMessageComposer = true
    let location = await VoygoLocationService.shared.lastKnownCoordinate()
    Task {
        try? await VoygoAPIClient.fireSOS(
            rideId: tripId,
            lat: location?.latitude,
            lng: location?.longitude,
            message: sosMessageBody
        )
    }
}
```

Both fire in parallel — SMS gets help moving instantly, backend ping closes the ops loop.

**Effort:** 3 days backend (PagerDuty/Twilio integration on the on-call side), 1 hour iOS.

---

## 10. Stripe Connect for driver payouts · iOS-side small, backend ~1 week

### What it is
Today Billplz handles charging. Driver earnings sit in our books; payouts are aspirational. Stripe Connect Express lets drivers onboard once (KYC + bank account), and we trigger payouts via Stripe.

### How to do it

#### Server
- `POST /drivers/{id}/connect-account` → returns Stripe Connect onboarding URL.
- Webhook `account.updated` → mark driver as payout-ready.
- Daily/weekly cron: for each driver with `pending_payout_myr > threshold`, transfer funds via Stripe Connect.
- Store transfer ID; expose in `GET /payouts/me`.

#### iOS
DriverPayoutsView gains a "Set up bank account" CTA when status is not payout-ready:

```swift
if !store.isStripeReady {
    VPrimaryButton("Set up bank account") {
        Task {
            if let url = try? await VoygoAPIClient.connectOnboardURL(),
               let safe = URL(string: url) {
                // Open Stripe-hosted onboarding in SFSafariViewController
                showStripeOnboardURL = safe
            }
        }
    }
}
```

Same SFSafariViewController pattern Billplz uses. Onboarding completes server-side via webhook; client polls `/me` on return.

**Effort:** ~1 week. Stripe Connect Express has all the heavy lifting; the work is webhook handling, scheduling, and reconciliation reports.

---

## 11. Real `/notifications` endpoint · paired with #7

Same backend lift as push. The two ship together — once you have devices registered + APNs sending, the persistent feed is just `GET /notifications` over the same data.

---

## Build order if you wanted to do the lot

If you're serious about closing every gap — ~6 weeks of focused work split client/backend:

| Week | Client | Backend |
|---|---|---|
| 1 | AppError UI surface · Dynamic Type · Wallet/TripHistory skeletons | `/notifications` endpoint design |
| 2 | iPad layout pass | `/safety/sos` + on-call dispatch |
| 3 | Push notifications register + receive | APNs sending pipeline |
| 4 | NotificationsView from API | Driver location ingestion |
| 5 | Live tracking SSE consumer | Live tracking SSE producer |
| 6 | Stripe onboarding link + payout view | Stripe Connect server + webhooks |

Telemetry is per-feature — instrument as you ship.

Bahasa Malaysia is parallel — it just needs the broaden-Strings sweep + a translator week.

---

## What you can ship right now without backend

The pure-iOS items from this list are doable in a single session:

- **AppError UI surface** (~1 day)
- **Dynamic Type** (~1 day)
- **Wallet + TripHistory skeletons** (~30 min)
- **Bahasa Malaysia scaffold** (~half a day to centralize, then translation)

Want me to execute those four in one batch?

— Generated 2026-05-09 against commit `ef7b13e`.
