# Voygo — Architecture & Function Map

Two parts:

1. **Find-ride flow walk-through** — how a rider's tap on "Book a ride"
   becomes a list of route matches, end to end.
2. **Function map** — every screen/feature, what it does today, and
   what it would do in a fully-featured v1.

Generated 2026-05-09 against commit `2a768cf`.

---

## Part 1 · "Find a ride" — current flow

### High-level pipeline

```
 Home / "Book a ride"  ──► HomeTab(NavigationStack)
                           └─► path.append(.findRides)
                                  ▼
                           AppRouteDestinations switch
                                  ▼
                           FindCommuteRoutesView
                              ├── HomeHero (greeting + menu)
                              ├── ModeRail (Routes / Driver / Create)
                              ├── MapsStyleCommuteSearchPanel
                              │      ├─ From field   ──► MKLocalSearch + /places/autocomplete
                              │      ├─ To field     ──► same
                              │      ├─ Earliest 07:00
                              │      ├─ Latest   09:30
                              │      └─ Search Routes button
                              │
                              └── PolishedRouteCard list (results)
                                       │
                                       └─ tap ──► path.append(.routeDetails(id))
```

### Step-by-step (file:line where it happens)

1. **Tap "Book a ride"** on Home — `HomeView.searchCard` Button calls
   `onSearchTapped`. `HomeTab` ([Features/Home/HomeView.swift:30](TravelComposeApp/Features/Home/HomeView.swift)) appends `.findRides` to its `[AppRoute]` path.

2. **`AppRouteDestinations`** ([App/AppRoute.swift:53](TravelComposeApp/App/AppRoute.swift)) maps `.findRides` to a `FindCommuteRoutesView` instance, with an `onBack` closure pointing at `path.removeLast()` (so the user has a way back to Home).

3. **`FindCommuteRoutesView.body`** mounts a `ScrollView` containing the green Voygo hero, the mode rail (Routes / Driver / Create shortcuts), the `MapsStyleCommuteSearchPanel` (From/To/time fields), then the route-card list. View constructs its own `@Observable` viewmodel `vm = FindCommuteRoutesViewModel()` and assigns `vm.store = store` on `.onAppear`.

4. **Typing in From/To** triggers the VM's `onHomeQueryChange(_:)` / `onOfficeQueryChange(_:)`. These debounce 400ms via `Task.sleep`, then call `VoygoLocationService.shared.lastKnownCoordinate()` to bias the search and `VoygoAPIClient.autocompletePlaces(query:lat:lon:)` to fetch suggestions. Tapping a suggestion calls `vm.selectHome(_:)` / `vm.selectOffice(_:)`, which captures the lat/lon and clears the dropdown.

5. **"Search Routes" CTA** dismisses keyboard and calls `vm.searchRoutes()`. The VM marks `isSearching = true`, clears dropdowns, and awaits `store.findCommuteRoutes(...)`.

6. **`AppStore.findCommuteRoutes`** ([Core/AppStore.swift:601](TravelComposeApp/Core/AppStore.swift)) is the orchestrator:
   - **Online + authenticated path:** builds a `CommuteRouteSearchRequest`, hits `POST /commute/search` via `VoygoAPIClient.findCommuteRoutes(request:)`, maps the response DTOs to `CommuteRouteMatchResult`s, replaces routes in the local cache, and returns.
   - **Offline / dev-shortcut path** (or if the API errored): falls through to `CommuteMatchingEngine.matchRoutes(...)` which does the matching on-device using `store.routes / .subscriptions / .rideInstances`. The user sees `connectionState = .offline("Search used offline matching.")` if the API failed.

7. **`CommuteMatchingEngine.matchRoutes`** ([Core/AppStore.swift:1045](TravelComposeApp/Core/AppStore.swift)) — the on-device fallback. It:
   - Filters routes to those `active` and within the `[earliestMinutes, latestMinutes]` window.
   - For each route, computes:
     - `pickupDist` / `dropDist` via Haversine on lat/lon when present, else token-similarity on labels.
     - `overlapScore` — weighted combination of pickup + drop nearness.
     - `detourMins` — heuristic from total distance.
     - `recurring` — does this rider already have an active subscription on this route?
     - `clusterMatch` — does any pickup point share a cluster with the rider's existing pickups?
     - `reliability` — driver's composite reliability score from the model.
     - `priceScore` — softmax against an arbitrary 400 MYR ceiling.
   - Combines all of those into `rankingScore` with weights from `Policy { recurring 0.35 / detour 0.25 / cluster 0.20 / reliability 0.20 / overlap 0.08 / price 0.06 }`.
   - Filters to seats > 0, sorts by recurring → least-detour → ranking.

8. **VM receives results**, sets `vm.results = results`, `vm.isSearching = false`. The view re-renders. The "Best route matches" header appears with the count, and `PolishedRouteCard`s render for each match.

9. **Tap a card** → `onTap: { onOpenRoute(match.route.id) }` → `HomeTab` (or `CommuteTab`) appends `.routeDetails(routeId:)` → `RouteDetailsView` mounts with the same nav back chevron pattern. From there the rider picks a tier + pickup + drop, taps "Subscribe & pay RM N", which calls `store.subscribe(...)` → `chargeSubscription(...)` → `BillplzCheckoutSheet` → deep-link return → `BookingConfirmedView`.

### Sequence diagram

```
User       HomeView   HomeTab    AppRouteDestinations    FindCommute   FindCommuteVM   AppStore   APIClient   MatchEngine    Backend
 │             │         │              │                    │             │             │           │             │            │
 │ tap Book a  │         │              │                    │             │             │           │             │            │
 │   ride      │         │              │                    │             │             │           │             │            │
 │────────────►│         │              │                    │             │             │           │             │            │
 │             │ onTap   │              │                    │             │             │           │             │            │
 │             │────────►│              │                    │             │             │           │             │            │
 │             │         │ append       │                    │             │             │           │             │            │
 │             │         │ .findRides   │                    │             │             │           │             │            │
 │             │         │─────────────►│                    │             │             │           │             │            │
 │             │         │              │ build view         │             │             │           │             │            │
 │             │         │              │───────────────────►│             │             │           │             │            │
 │             │         │              │                    │ store=Env   │             │           │             │            │
 │             │         │              │                    │────────────►│             │           │             │            │
 │  type from / to + tap Search                              │             │             │           │             │            │
 │──────────────────────────────────────────────────────────►│             │             │           │             │            │
 │             │         │              │                    │ searchRoutes│             │           │             │            │
 │             │         │              │                    │────────────►│             │           │             │            │
 │             │         │              │                    │             │ findCommute │           │             │            │
 │             │         │              │                    │             │────────────►│           │             │            │
 │             │         │              │                    │             │             │ POST      │             │            │
 │             │         │              │                    │             │             │ /search   │             │            │
 │             │         │              │                    │             │             │──────────►│             │            │
 │             │         │              │                    │             │             │           │ HTTP        │            │
 │             │         │              │                    │             │             │           │────────────────────────►│
 │             │         │              │                    │             │             │           │ candidates                │
 │             │         │              │                    │             │             │           │◄────────────────────────│
 │             │         │              │                    │             │             │ matches   │             │            │
 │             │         │              │                    │             │             │◄──────────│             │            │
 │             │         │              │                    │             │ results     │           │             │            │
 │             │         │              │                    │             │◄────────────│           │             │            │
 │             │         │              │                    │ render cards│             │           │             │            │
 │             │         │              │                    │◄────────────│             │           │             │            │
 │  see route cards / tap one                                │             │             │           │             │            │
 │◄──────────────────────────────────────────────────────────│             │             │           │             │            │
                                                                                             ▲ (offline fallback path:
                                                                                                AppStore → CommuteMatchingEngine
                                                                                                instead of APIClient)
```

### Failure modes & how the code handles them

| Scenario | Code path | What user sees |
|---|---|---|
| `useOnline = false` (dev shortcut) | Skip API, run `CommuteMatchingEngine` against in-memory routes | Results from sample data |
| API 401 | `clearSession()` → bounce to AuthPhone | Forced sign-out |
| API timeout / 500 | catch → set `lastSyncError`, fall through to engine | Banner: "Search used offline matching." + offline results |
| Empty results | `vm.results.isEmpty && (!homeQuery.isEmpty \|\| !officeQuery.isEmpty)` | EmptyStateView with `map.fill` icon |

### Data shapes

| Type | Defined | Purpose |
|---|---|---|
| `CommuteRouteSearchRequest` | APIClient.swift | Query payload to `POST /commute/search` |
| `CommuteRouteMatchResponse` | APIClient.swift | Response with candidate list |
| `CommuteRouteMatchResult` | Models.swift | Display row: route + pickup distance + reliability + detour + ranking |
| `RecurringRoute` | Models.swift | The route itself (driver, schedule, pickups, drops, seats, price, reliability) |
| `RoutePoint` | Models.swift | Single pickup or drop with lat/lng + clusterId |
| `DaysOfWeekFlags` | Models.swift | Mon-Sun bool tuple |

### Scoring weights (current default)

```
recurring rider     0.35  ← biggest single factor; sticky riders win
minimal detour      0.25
pickup cluster      0.20
driver reliability  0.20
overlap (start/end) 0.08
price (vs 400 MYR)  0.06
```

These are knobs in `CommuteMatchingEngine.Policy` so a future
A/B test can swap in a different weighting without touching the
scoring code.

---

## Part 2 · Function map — current vs. ideal

For every named feature in the app: what it does today, what's gated
on backend / device permission / out-of-scope work, and what a
"fully-featured v1" looks like.

### 🎯 Auth & onboarding

| Feature | Current (✅ working) | Ideal v1 |
|---|---|---|
| Phone OTP request | Real `/auth/request-otp`, normalizes Malaysian numbers, returns dev OTP code | Real SMS via Twilio/Telnyx; expire codes server-side; rate-limit |
| OTP verify | Real `/auth/verify-otp` → JWT in Keychain, refresh kicks off | Same; add backup channel (email OTP, WhatsApp) |
| Dev shortcut | `#if DEBUG` skip-login button → in-memory dev session | Same — already correct |
| Session restore | UserDefaults for non-sensitive ids + Keychain token | + biometric unlock if user opts in |
| KYC document upload | Submits document **kind**, no file → backend records `pending` | `PHPickerViewController` → S3 presigned upload → store the URL |
| KYC role split | Rider (3 docs) vs Driver (7 docs) with progress bar | Same; add "what to expect next" turnaround on pending state |

### 🏠 Home tab

| Feature | Current | Ideal |
|---|---|---|
| Greeting | Real first-name from `store.currentUser` | + last-pickup nearby suggestion ("3 routes near USJ") |
| **"Book a ride" CTA** | ✅ Pushes `.findRides` | ✅ Same |
| Bell button | ✅ Pushes `.notifications` | + unread badge from `/notifications/unread-count` |
| Service grid: Carpool | ✅ Pushes `.findRides` | ✅ Same |
| Service grid: Ride solo / Schedule / Long-haul | 🟡 Coming-soon alert | Real product surfaces, OR remove until they exist (currently aspirational labels imply features that don't) |
| Promo banner | 🔴 Decorative, no offer code | Real `/promotions` endpoint with redemption tracking |
| "Heading your way" feed | ✅ Reads `store.routes`, falls back to 2 demo rows on fresh install | New `/commute/discover` endpoint that returns real nearby routes for this user |
| Service grid `NEW` pill | 🟢 Decorative | Real new-feature flag from server |

### 🔍 Search tab (formerly Routes)

| Feature | Current | Ideal |
|---|---|---|
| Hero header | 🟡 "12 routes / N active rides / RM local fares" — stats labels hardcoded | Real counts from `store.routes` and `store.subscriptions` |
| From/To autocomplete | ✅ `/places/autocomplete` + MKLocalSearch fallback | + recent destinations under each field |
| Use current location | ✅ `CLLocationManager` with timeout + denial path | + remember chosen-location-for-home / -for-work as pinned |
| Earliest / Latest time | ✅ Real bindings, real filtering | + "right now" preset that expands the window |
| Mode rail (Driver Dash / Create / My Subs) | ✅ Real pushes | + a "first-time driver" walkthrough behind the Driver tile |
| Route results | ✅ Real `/commute/search` + `CommuteMatchingEngine` fallback | + filter chips: women-only, EV only, female driver only, smoking ok |
| Empty state (no queries) | 🟡 No empty state — section just doesn't render | Illustrated empty state pointing at the search fields |
| Empty state (queries with no results) | ✅ "No routes found · adjust locations or window" | + "Suggest a route" button → driver-side recruitment |

### 🚗 Route details

| Feature | Current | Ideal |
|---|---|---|
| Abstract route diagram hero | ✅ Stops fed from real route | + animated stroke draw-on, real map snapshot toggle |
| Driver row (avatar, rating) | ✅ Real | + verified badge, ride count, last ride together |
| Route info table | ✅ Real | Same |
| Pickup / Drop selection | ✅ Real radio | + "save as default for this route" |
| Tier picker | ✅ Real Daily / Monthly / Quarterly | + "what's the difference?" sheet |
| **Subscribe & pay** CTA | ✅ `/payments/charge` → Billplz hosted checkout → deep-link return | + Apple Pay / Google Pay path; + 3DS handling explicit |
| Charge failure auto-pause | ✅ Subscription auto-paused on charge failure | + retry timer ("retries in 4h") on the My Subs row |
| Reliability metrics | ✅ On-time / cancel rate / repeat riders | + per-pickup-cluster breakdown ("95% overall, 78% at YOUR pickup") |

### 📅 My subscriptions / Calendar

| Feature | Current | Ideal |
|---|---|---|
| List of active subscriptions | ✅ Real | + grouping by route |
| Cancel with confirmation | ✅ Real, atomic two-step (cancel + report) | + "cancel reason" picker so support can categorize |
| Retry payment on paused | ✅ Real | + Apple-Pay-quick-retry without the Billplz round-trip |
| Upcoming calendar | ✅ Real `store.upcomingRides` | + ICS export, calendar app integration |

### 🛰 Live trip

| Feature | Current | Ideal |
|---|---|---|
| Pickup / drop labels | ✅ Resolved from real route (just landed) | Same + dynamic ETA-shifted labels |
| Driver row | ✅ Real `driverName` + carType (just landed) | + plate, vehicle photo, driver photo |
| Abstract route diagram | ✅ Stops from real route | Replace with live `Map` once tracking ships |
| GPS dot | 🔴 Static circle | Real driver location via SSE/WebSocket |
| ETA countdown | 🔴 12-min timer demo | Real `/rides/{id}/eta` poll or push |
| Phone button | 🟡 Disabled (no driver phone on model) | `tel://` once `driverPhone` lands |
| Share button | 🔴 No-op | Generate `/share/{token}` URL → ActivityViewController |
| **SOS button** | 🟡 Alert with no real action | Contacts permission → MFMessageComposeVC with location + backend `/safety/sos` |
| Status pill ("En route") | 🔴 Hardcoded | Reflect real `rideStatus` |

### ⭐ Rate ride

| Feature | Current | Ideal |
|---|---|---|
| Driver header | ✅ Real driver/route from LiveTrip | + last-trip thumbnail |
| Stars + tags + tip | ✅ Real local state | Same |
| Submit | 🟡 Local only — no `/reviews` endpoint yet | `POST /reviews` with rating + tags + tip |
| Skip vs Back | ✅ Disambiguated chevron + Skip pill | Same |

### 💳 Wallet

| Feature | Current | Ideal |
|---|---|---|
| Voygo Credit hero | ✅ Computed from refunded payments | + breakdown of how credit was earned (refund × N, referral × M) |
| Top-up | 🔴 Coming-soon | Apple Pay top-up → `/wallet/top-up` |
| Withdraw | 🔴 Coming-soon | Bank transfer via FPX |
| Payment methods | 🟡 Empty state until backend exposes them | Real `/users/me/payment-methods` with default + delete |
| Recent transactions | ✅ Real `store.payments`, empty state when none | + filter by month, search by route |

### 🧾 Trip history

| Feature | Current | Ideal |
|---|---|---|
| Summary stats | ✅ Total / Trips / Refunded computed from real payments | + monthly breakdown |
| Filter chips | ✅ All / Completed / Cancelled | + Year / Month nav |
| Trip list | ✅ Real `store.payments` | Same + pagination once volume grows |
| Tap → Receipt | ✅ Real | Same |
| Empty state | ✅ Honest "No trips yet" | Same |

### 🧾 Receipt

| Feature | Current | Ideal |
|---|---|---|
| Status & body | ✅ Real (resolved from payment + route lookup) | + tax line items if business account |
| QR | 🟢 Decorative (a11y-hidden) | Real QR encoding the receipt URL |
| Share | _not present_ | Add a top-right share pill |

### 🚙 Driver dashboard / payouts / create route

| Feature | Current | Ideal |
|---|---|---|
| Driver dashboard list | ✅ Real `store.driverDashboards()` | Same |
| Pause / resume | ✅ Real with confirm + double-fire guard | + "schedule pause" for vacation |
| Schedule update (Mon-Fri / All-Days) | ✅ Real with throttle | + per-day toggle (custom mix) |
| Create route | ✅ Real `/commute/routes` create + map picker | + duplicate from existing route |
| Driver payouts | 🟡 Real `store.payout` but no auto-refresh | Add `.task { await store.refreshPayout() }` |
| Stripe Connect | 🔴 Not integrated | Onboard drivers to Stripe Connect Express; weekly payout to bank |

### 💬 Inbox / Chat

| Feature | Current | Ideal |
|---|---|---|
| Threads list | ✅ Real `store.threads` | + search threads |
| Empty state | ✅ Real | Same |
| Chat thread | ✅ Real send/receive, custom nav chrome | + read receipts + typing indicator |

### 👤 Profile

| Feature | Current | Ideal |
|---|---|---|
| Identity row | ✅ Real name + rating + ride count (just landed) | + verified pill click target |
| KYC card | ✅ Status-aware copy and color | Same |
| Wallet shortcut | ✅ Real subtitle | Same |
| Quick stats | ✅ Real Saved / Trips / On-time | + breakdown drill-in |
| Settings rows | ✅ All push correctly | + edit profile, address book |
| Driver mode card | ✅ Hidden when no driver routes | + explainer for first-time tap |
| Logout | ✅ Real with throttle | + biometric re-enroll on sign-back-in |

### ⚙ Settings sub-screens

| Feature | Current | Ideal |
|---|---|---|
| **NotificationsView** | ✅ Empty state until `/notifications` lands; Mark-all-read is a real Button | Real notifications list with deep-links to relevant screen |
| **KYC verification** | 🟡 Real checklist + role switcher; no photo picker | PHPicker + S3 upload + image preview |
| **Privacy & Security** | 🔴 Static "Security tips" copy | Data export request, account deletion, location-share toggles |
| **Help Center** | ✅ `mailto:` and `https://voygo.app/help` links real | + in-app live chat integration |

### 🗺 Place picker / Map

| Feature | Current | Ideal |
|---|---|---|
| Place picker sheet | ✅ User-scoped recents, Home/Work, MKLocalSearch | + suggested workplaces from corridor data |
| Map location picker | ✅ Reverse geocode while panning | + draw-pickup-radius for drivers |
| Search filters | ✅ Real bindings | + persist filters across sessions |

---

## Component layer cake

```
┌────────────────────────────────────────────────────────────┐
│                          UI (SwiftUI)                       │
│   HomeView · FindCommuteRoutesView · RouteDetailsView ·     │
│   LiveTripView · WalletView · TripHistoryView · Profile…    │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│              ViewModels (@Observable, @MainActor)           │
│  FindCommuteRoutesViewModel · RouteDetailsViewModel ·       │
│  CreateRouteViewModel · VerificationViewModel(removed)      │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│           AppStore (@Observable, single source)             │
│   isAuthenticated, currentUser, routes, subscriptions,      │
│   rideInstances, threads, messages, payments, payout,       │
│   kycDocuments, cancellationRecords                         │
│                                                             │
│   Methods: requestOtp, verifyOtp, refreshAll,               │
│   findCommuteRoutes, subscribe, chargeSubscription,         │
│   cancelSubscription, refreshPayments, refreshPayout,       │
│   submitKycDocument, sendMessage, …                         │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│   Services (stateless)                                      │
│   VoygoAPIClient (REST)  · VoygoLocationService (CL/MapKit) │
│   SessionStorage (Keychain)  · AppConfiguration (URLs)      │
│   Telemetry (stub)                                          │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│   Models (Codable, Equatable)                               │
│   RecurringRoute · RouteSubscription · CommuteRideInstance  │
│   ChatMessage · PaymentRecord · KycDocument                 │
│   CancellationPolicyEngine · SubscriptionPricing            │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│   Backend (separate codebase) — API contracts only          │
│   /auth · /commute · /payments · /payouts · /cancellations  │
│   /places · /notifications · /reviews · /safety …           │
└─────────────────────────────────────────────────────────────┘
```

---

## Where v1 still has gaps (organized by impact)

| Severity | Gap | Effort |
|---|---|---|
| 🚨 | Real driver tracking (replaces LiveTrip ETA + GPS dot demo) | Weeks (backend + client) |
| 🚨 | Real SOS plumbing | 2-3 days |
| 🟧 | Stripe Connect for driver payouts | 1 week |
| 🟧 | KYC photo picker | 1-2 days |
| 🟧 | `/notifications` endpoint + push | 3-5 days |
| 🟨 | Search hero stats hardcoded labels | 1 hour |
| 🟨 | DriverPayouts auto-refresh | 30 min |
| 🟨 | AppError UI surface (typed cases unused at call sites) | 1 day |
| 🟨 | iPad layout (`NavigationSplitView`) | 1 week |
| 🟨 | Skeleton placeholders on Wallet / RouteDetails / MySubs | half a day |
| 🟦 | Telemetry instrumentation | 1 day |
| 🟦 | Bahasa Malaysia localization | 1 day after Strings.swift broadens |
| 🟦 | Dynamic Type semantic-font migration | 1 day |
| 🟦 | Swipe-back gesture restoration | 2 hours |

The find-ride flow itself is **fully wired**. The gaps above are
adjacent — what happens after a rider is matched, what happens during
the ride, how the driver gets paid out, and platform polish.

— Generated from `2a768cf`.
