# Voygo — Improvement Plan

State of play (post-`a76ead8`):
- Vibrant super-app palette landed.
- Home tab + abstract route diagram landed.
- @Observable migration landed; Swift 6 default mode is clean.
- CI green (xcodebuild on macos-15 + iOS 18 deployment override).

This doc lists what's worth doing next, ranked by impact-vs-effort. Each
item has enough detail to start without re-discovering scope. Nothing
here is committed work — it's a queue you can pull from.

---

## P0 · High impact, low risk (do these next)

### 1. Add a real test target
Currently zero tests; CI is build-only. CLAUDE.md mandates Swift Testing.
- Create `TravelComposeAppTests` target in pbxproj.
- Tests to land first (they pay the most per hour):
  - `CancellationPolicyEngine` — pure logic, easy `#expect` cases for rider vs driver penalty rules and the late-cancel tier escalation.
  - `SubscriptionPricing` — daily/monthly/quarterly tier math + discount.
  - `DaysOfWeekFlags.contains(date:)` — calendar-edge bugs love living here.
  - `normalizePhone(_:)` — already had two production bugs, deserves regression tests for `+60`/`60`/`0` prefixes and Sabah/Sarawak 9-digit numbers.
  - `formatPlacemark` / `mapKitSearch` — snapshot-test the address formatting.
- Wire into CI: add a `test` step that runs `xcodebuild test` on a pinned simulator (`platform=iOS Simulator,name=iPhone 15,OS=latest`).

**Effort:** ~half a day. **Why now:** every change after this is safer.

### 2. Promote `RouteDiagram` into Live Tracking
The component exists (`Core/RouteDiagram.swift`) but is only used on
RouteDetails. The Live Tracking screen (`LiveTripView` in
`ProfileViews.swift`) still has a placeholder hero.
- Drop `VRouteDiagram(stops: …, dark: true)` into LiveTripView's hero
  band, full-bleed.
- Animate the route stroke draw-on with `trim(from:to:)` over ~600ms
  for a "we just routed you" feel.

**Effort:** ~1–2 hours.

### 3. Wire suggested rides on Home to real driver routes
Right now `HomeView.suggestedRideRows` falls back to a hardcoded demo
when `store.routes` is empty. The demo names ("Maya R.", "David K.")
look real but break trust the moment the user logs in and sees "Driver"
on every row because `RecurringRoute.driverName` is server-populated
inconsistently.
- Call a new `GET /commute/discover` (or filter `store.routes` by
  proximity to last-known coordinate) and surface 3–5 rides max.
- Tap on a card should `path.append(.routeDetails(routeId:))` — not
  drop into the find-routes search. (Requires lifting the destination
  enum out of CommuteTab so HomeTab can also route.)

**Effort:** ~half a day, mostly the navigation refactor.

### 4. Centralize navigation routes
`HomeRoute`, `CommuteRoute`, `TripsRoute` each define their own enum.
There's already friction (Home can't route into RouteDetails without
duplicating CommuteTab's destinations).
- Extract a single `AppRoute: Hashable` with all destinations.
- Each tab's `NavigationStack` accepts `[AppRoute]` and shares one
  `navigationDestination(for:)` builder.
- Side benefit: deep links (`voygo://routes/<id>`) become trivial.

**Effort:** ~half a day.

---

## P1 · Medium impact, medium effort

### 5. Liquid Glass for iOS 26
CLAUDE.md asks for it; we ship pure Material/`Color`. iOS 26's
`.glassEffect()` modifier is the biggest visual unlock the runtime
gives us for free.
- Apply `.glassEffect()` to: tab bar background, Wallet's credit hero,
  the search card on Home, the sticky "Subscribe & pay" footer on
  RouteDetails.
- Gate behind `#available(iOS 26, *)` since CI builds against iOS 18.

**Effort:** ~2–3 hours, all in.

### 6. Split multi-type files (CLAUDE.md style rule)
Three files violate "one type per file":
- `Core/Polished.swift` — 16 types (Palette, Atoms, NavBar, Cards…).
- `Core/DesignSystem.swift` — 14 types (legacy aliases + atoms).
- `App/Navigation.swift` — 5 types (RootView, MainTabView, TabBar, …).

Mechanical splits, but worth doing in one focused commit so future PRs
have small diffs.

**Effort:** ~2 hours, mostly pbxproj wrangling.

### 7. SwiftData layer for offline-first behaviour
CLAUDE.md asks for SwiftData. We have AppStore as a pure in-memory
cache today.
- Mirror `RecurringRoute`, `RouteSubscription`, `CommuteRideInstance`,
  `ChatMessage`, `PaymentRecord` as `@Model`s.
- AppStore reads from `ModelContext` first, then refreshes from API.
- Fixes a real UX bug: users on KL → Penang trains lose the route list
  on every tunnel.

**Effort:** ~1–2 days.

### 8. Add `#Preview` blocks to all 71 view structs
Currently spotty — `HomeView` and a few others have them; most don't.
CLAUDE.md mandates it for all new views, but legacy views never got
backfilled. SwiftUI Previews are the single biggest dev-loop accelerator
on iOS, especially for small visual tweaks like the redesign we just
did. Without previews each tweak is a full rebuild + simulator launch.

**Effort:** mechanical — ~3 hours but tedious. Can be split per-feature
across small PRs.

### 9. Real Driver Live Tracking
`LiveTripView` shows static state. Pieces needed:
- Backend: server-sent events / WebSocket on `/rides/{id}/stream`.
- Client: a `LiveTripViewModel` that subscribes for the trip's
  duration, updates `driverLocation` every 5s.
- Display: animated dot on the `RouteDiagram`, ETA recomputed
  client-side from the dot's progress along the path.

**Effort:** ~2–3 days; depends on backend.

---

## P2 · Polish, accessibility, and footguns

### 10. Accessibility audit
Round-2 QA caught the obvious (textHint contrast, AX5 net-payout
clipping). Real audit still pending:
- Run `Accessibility Inspector` on every screen — flag missing
  `accessibilityLabel`s on icon-only buttons (the bell on Home,
  service-grid tiles, the SOS pill).
- Dynamic Type: `.font(.system(size: …))` doesn't scale. Migrate to
  `.font(.headline)` / `.font(.body)` etc. across at least the
  primary text in every view.
- VoiceOver flow on Home: hero's "Where to, this morning?" should
  announce *before* the search card so the gesture has context.
- Reduced motion: disable the route-stroke draw-on (see P0 #2) when
  `accessibilityReduceMotion` is true.

**Effort:** ~1 day for the audit, ~2–3 days for the fixes if we're
serious about Dynamic Type.

### 11. Consolidate hardcoded copy
Strings are scattered ("Subscribe & pay RM \(total)", "Coming soon",
hardcoded "Subang → KLCC" demo data). Two wins:
- Move to a `Strings.swift` enum so we get compiler errors when copy
  is referenced wrong.
- Adds a hook for localization later (Bahasa Malaysia is the obvious
  next locale).

**Effort:** ~half a day. **Why bother:** unblocks BM localization.

### 12. Replace remaining `MapPlaceholder` callsites
We have a real `MapLocationPicker` (MKMapView wrapper) and a stylised
`VRouteDiagram`. The legacy `MapPlaceholder` (a Canvas-drawn fake map)
in `Polished.swift` is still wired into BookingConfirmedView and
RateRideView. Either:
- Replace with `VRouteDiagram` (consistent visual language), or
- Replace with a real static `Map` snapshot via `MKMapSnapshotter`
  showing the actual pickup/drop coords.

**Effort:** ~3 hours.

### 13. Type the API client's errors
`AppError` is currently `.message(String)` — every call site loses the
machine-readable status code. Hard to tell "user not authenticated"
from "validation failed" from "server error" except by string match.
- Introduce a `VoygoAPIError` enum with cases for `unauthorized`,
  `validation([Field: String])`, `rateLimit`, `server`, `network`.
- Lift up `APIError` from APIClient into the public surface; let UI
  switch on it.

**Effort:** ~half a day, mostly grunt at call sites.

### 14. Drop unused legacy code
- `VoygoTheme` is now a pure alias of `VPalette` — keep it for the
  duration of the redesign migration, then delete after one release.
- `MapPlaceholder` (after #12).
- `import Combine` references in feature files that don't use
  Combine anymore (post @Observable migration).

**Effort:** ~1 hour.

---

## P3 · Strategic / further out

### 15. Real driver onboarding (KYC + Stripe Connect)
KYC is wired through `submitKyc`/`KycDocument`s but the verification
path is a stub. To actually let drivers earn:
- Plaid IDV or onfido for ID + selfie → backend validates.
- Stripe Connect Express for payouts (Billplz handles charging only).
- Tax form collection (e-Faktura for MY).

**Effort:** weeks.

### 16. Ride-sharing safety: real "share my ride" + SOS
The SOS button alerts; it doesn't actually call anyone. The "share my
ride" toggle is decorative. Both are the most-cited carpool safety
features and the hardest to fake convincingly.
- SOS: integrate `ContactsUI` + a configured emergency contact, send
  SMS via `MFMessageComposeViewController` with live location URL.
- Share my ride: real link — backend `/share/{token}` page that shows
  the route map + ETA, no auth, expires when ride completes.

**Effort:** ~3–4 days.

### 17. iPad layout
Currently every view is iPhone-shaped. CLAUDE.md says iPhone + iPad.
Either:
- `NavigationSplitView` for the iPad: route list on the left, details
  on the right. Tab bar collapses into a sidebar.
- Or accept that iPhone-only is the reality and update CLAUDE.md.

**Effort:** ~1 week to do well; ~1 day to do badly.

### 18. Analytics / observability
We have `Telemetry.swift` as a stub. Without it we can't tell which
service-grid tile actually gets tapped, what % of users abandon the
checkout, etc.
- Pick one: Posthog (cheap, self-hostable), Amplitude (richest), or
  Apple's MetricKit (free but iOS-only signals).
- Standardize event names: `home_tile_tapped {tile}`, `subscribe_started {tier, route_id}`, `checkout_abandoned {amount_myr, reason}`.

**Effort:** ~1 day for instrumentation; ongoing for dashboards.

---

## Recommended sequencing

If you want a 2-week shape:

**Week 1 — Foundations**
- Day 1: P0 #4 (centralize routes) + P0 #3 (real suggested rides).
- Day 2: P0 #1 (test target + first 5 test files).
- Day 3: P0 #2 (RouteDiagram in LiveTrip) + P1 #5 (Liquid Glass).
- Day 4: P1 #6 (file splits) + P2 #14 (cleanup).
- Day 5: P1 #8 (preview blocks) + buffer.

**Week 2 — Depth**
- Days 1–2: P1 #7 (SwiftData layer).
- Days 3–4: P2 #10 (a11y audit + Dynamic Type fixes).
- Day 5: P2 #13 (typed API errors) + P2 #11 (strings consolidation).

After that the queue is P3-flavored — scope creeps into backend work,
and you'll want product input on which strategic bet to take first.

---

— Generated 2026-04-30. Reflects worktree state at commit `a76ead8`.
