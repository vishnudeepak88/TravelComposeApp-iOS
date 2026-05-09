# Voygo — Deep Per-Screen Audit

Read every feature view file end-to-end on commit `a38f71c` and noted
what's real, what's mock, and what's missing. The earlier
`UX_AUDIT.md` covered navigation/exit-paths only — this one is the
functional/content side. Verdicts:

- ✅ **Real** — backed by the API/store, behaves correctly.
- 🟡 **Partial** — UI is wired but behind it are placeholder values,
  no-op buttons, or hardcoded sample data the user will see through.
- 🔴 **Mock** — entirely fake; nothing the user does on this screen
  changes anything.
- ⚠️ **Bug** — wrong behavior right now, not a missing feature.

---

## Per-screen verdicts

### Onboarding & Auth

| Screen | Verdict | Notes |
|---|---|---|
| **AuthPhoneView** | ✅ Real | Hits `/auth/request-otp`, normalizes phone (with the Sabah/Sarawak regression covered by tests). Dev-shortcut button gated under `#if DEBUG`. |
| **AuthOtpView** | ✅ Real | Real `/auth/verify-otp`, JWT lands in Keychain, refresh kicks off. Cancellable countdown, OTP autofill. Solid. |
| **Voygo brand splash on AuthPhone** | 🟡 | "12 routes · 1 active rides · RM local fares" stats are hardcoded into the auth hero on FindCommute (not Auth) — not a blocker for auth itself. |

### Home (super-app)

| Element | Verdict | Notes |
|---|---|---|
| Greeting + first-name | ✅ | Reads `store.currentUser.name`. |
| **"Book a ride" CTA** | ✅ | Just fixed in the recent waves; pushes `.findRides`. |
| Bell icon | 🔴 | Opens "Coming soon" — doesn't actually link to Notifications. Should go to `.notifications` (it already exists in Profile). |
| Service grid: **Carpool** | ✅ | Pushes `.findRides`. |
| Service grid: **Ride solo / Schedule / Long-haul** | 🔴 | Coming-soon alerts. The labels imply features that don't exist. |
| Promo banner ("First ride free, save RM 14") | 🔴 | Decorative — no offer code, no link, doesn't track redemptions. Aspirational copy on a screen the user thinks is functional. |
| **"Heading your way"** suggested rides | 🟡 | Reads from `store.routes` if non-empty, else falls back to two demo rows ("Maya R.", "David K."). On a fresh install riders see fake names. |
| "See all" link | 🟡 | Hooked to `onSearchTapped` (opens Search) — but the user expects "see more suggestions", not "open the Search screen". Subtle but real mismatch. |

### Search (renamed from Routes)

| Element | Verdict | Notes |
|---|---|---|
| Hero header (greeting + stats) | 🟡 | "12 routes / N active rides / RM local fares" — the 12 and "RM" labels are hardcoded. Counts should reflect `store.routes.count`. |
| From/To autocomplete | ✅ | Real `/places/autocomplete` with MKLocalSearch fallback. |
| "Use current location" | ✅ | `CLLocationManager` wired through `VoygoLocationService`. Has timeout + denial path. |
| Earliest/Latest time | ✅ | Real bindings down to `vm.searchRoutes()`. |
| Mode rail (Driver Dashboard / My Subscriptions / Create Route shortcuts) | ✅ | All three push real destinations now. |
| Search results | ✅ | Hits `/commute/search`, renders `PolishedRouteCard`s. |
| **Empty-state with "Find a route" CTA** | 🟡 | When `vm.results.isEmpty` AND queries empty, the section just doesn't render. Better to show an illustrated empty-state pointing at "search above". |

### Route Details

| Element | Verdict | Notes |
|---|---|---|
| `VRouteDiagram` hero | ✅ | Stops fed from `route.startLocation/pickupPoints/dropPoints/endLocation`. |
| Driver row (avatar, rating) | ✅ | Reads `route.driverName` + `route.reliability.averageRating`. |
| Route info table | ✅ | All fields from the model. |
| "Driver Reliability" trio | ✅ | Real data from `reliability`. |
| Pickup/Drop selection | ✅ | Real radio behavior; default selection is `first` for each. |
| Tier picker (Daily/Monthly/Quarterly) | ✅ | Drives `SubscriptionPricing.totalForTier(...)`. |
| **"Subscribe & pay RM …" CTA** | ✅ | Real `/payments/charge`, opens Billplz hosted checkout, deep-link returns. |
| Charge failure → auto-pause | ✅ | Subscription auto-paused if payment fails (race-fixed earlier). |
| Empty/missing route | ✅ | "Route not found" state. |

### Booking flow

| Screen | Verdict | Notes |
|---|---|---|
| **BillplzCheckoutSheet** | ✅ | SFSafariViewController + voygo:// deep link return. Hot-cache race fixed. |
| **BookingConfirmedView** | 🟡 | Header text uses real `bookingId / pickup / driverName`, but the **"What's next" steps** below are hardcoded copy ("Pickup tomorrow 7:42 AM · USJ 9 LRT" — irrelevant if the rider's actual route differs). |
| **MySubscriptions** | ✅ | Real list from `store.mySubscriptions()`. Cancel-with-confirm works. Retry payment works on paused subs. |
| **UpcomingCalendarView** | ✅ | Real upcoming rides from `store.upcomingRides`. |

### Live Trip

| Element | Verdict | Notes |
|---|---|---|
| `VRouteDiagram` hero (dark) | ✅ | Lands well visually. |
| Status pill ("En route") | 🔴 | Hardcoded; doesn't reflect actual ride status. |
| Animated GPS dot on map | 🔴 | Static circle at `47% × 55%` of geo — never moves. |
| Top-bar share button | 🔴 | No-op `Button {}`. |
| **ETA countdown** | 🟡 | Decrements every 60s from a hardcoded `12` minutes. No backend integration. |
| Pickup/Drop addresses | 🔴 | Hardcoded "USJ 9 LRT" / "KLCC Tower B". The view receives a `tripId` but never reads `store.rideInstances` to render the actual trip. |
| Driver row | 🔴 | Hardcoded "Aiman Z. · Tesla Model 3 · VEC 4123". Same as above — should pull from the trip's route. |
| Phone button | 🔴 | No-op. Should `tel:` to driver number once we have it. |
| Message button | 🟡 | Calls `onMessageDriver?()` but the closure is nil from `AppRouteDestinations`. So in practice no-op. |
| **SOS button** | 🟡 | Alert shows; tapping "Send SOS" does nothing real (comment acknowledges it). No SMS, no contact alert, no backend call. |

### Rate Ride

| Element | Verdict | Notes |
|---|---|---|
| Driver header | 🟡 | Reads `driverInitial`/`driverName` from the push payload, but the call site (`AppRouteDestinations`) hardcodes `"A"`/`"Aiman"`/`"Subang Jaya → KLCC"`. |
| Star picker | ✅ | Real state. |
| Tag selector | ✅ | Real state. |
| Tip stepper | ✅ | Real state. |
| **"Submit review"** | 🟡 | Calls `onSubmit(rating, tags, tip)` but `AppRouteDestinations` ignores the parameters (`{ _, _, _ in path = [] }`). The review is never persisted. |

### Wallet

| Element | Verdict | Notes |
|---|---|---|
| Credit hero balance | ✅ | Computed from `store.payments.filter(.refunded)`. |
| Skeleton on first sync | ✅ | `isPaymentsLoading` shows "—" not a misleading "0.00". |
| Top-up / Withdraw buttons | 🔴 | Coming-soon. |
| **Payment methods list** | 🔴 | Hardcoded `methods: [Method]` — DuitNow Maybank ··4221, TNG eWallet ··2987, Visa ··8412. None are real. "+ Add" → coming-soon. |
| Default badge | 🔴 | Always lights up DuitNow because it's hardcoded `isDefault: true`. |
| Recent transactions | 🟡 | Real `store.payments` if present, else sample reel of 5 hardcoded rows ("Subang → KLCC", "Voygo Credit", etc.). |

### Trip History

| Element | Verdict | Notes |
|---|---|---|
| Summary stats | 🔴 | Hardcoded "RM 252 / RM 168 / 94%". Should aggregate `store.payments`. |
| Filter chips (All/Completed/Cancelled) | ✅ | Filter logic works. |
| **Trip list** | 🔴 | Entirely hardcoded array of 5 trips ("Subang → KLCC", "Aiman Z." everywhere). Doesn't read `store.payments` at all. |
| Tap to receipt | 🟡 | `onOpenReceipt(receiptId)` fires, but the IDs are mock ("VG-412-0614") and won't be found in `store.payments` so the destination shows the fallback. |
| Cancelled rows non-tappable | ✅ | QA-fixed earlier. |
| Nav-bar kicker "Last 30 days · 18 trips" | 🔴 | The "18" is fake; the on-screen list has 5. |

### Receipt

| Element | Verdict | Notes |
|---|---|---|
| Lookup by `bookingId` | ✅ | `store.payments.first { $0.id == bookingId }` — real. |
| Status text + color | ✅ | Real status enum. |
| `VRouteDiagram` hero | 🟡 | Generic "Pickup → Dropoff" labels because backend doesn't thread real addresses on the payment row yet. |
| Body content | 🔴 | "USJ 9 LRT" / "KLCC Tower B" / "Aiman Z." / "Tesla Model 3 · VEC 4123" / "5.0 stars" — all hardcoded. |
| Total / fare / payment method | 🟡 | `amountMyr` is real; "Voygo Pay · DuitNow / TNG / card" subtitle is invented. |
| QR placeholder | 🟢 | Honestly decorative — `accessibilityHidden(true)`. |

### Driver

| Element | Verdict | Notes |
|---|---|---|
| **DriverDashboardView** | ✅ | Real `store.driverDashboards()`. Pause/resume + schedule update both gated against double-fire. Confirmation alert before pause (destructive). |
| **CreateRouteView** | ✅ | Real `/commute/routes` create. Map-picker integration works. Pickup/drop suggestions via MKLocalSearch. |
| **DriverPayoutsView** | 🟡 | Reads `store.payout` if available; otherwise empty state. The `payout` model fields are real but no `refreshPayout()` is called automatically — the screen will show empty until something else triggers a sync. |

### Inbox / Chat

| Element | Verdict | Notes |
|---|---|---|
| **InboxView** | ✅ | Real `store.threads`. |
| Empty state | 🟢 | Honest. |
| **ChatThreadView** | ✅ | Real `store.messages(for:)` and `sendMessage`. Just migrated to `VPolishedNavBar`. |
| Send button enabled state | ✅ | Disabled when input is whitespace. |

### Profile

| Element | Verdict | Notes |
|---|---|---|
| Identity row | 🟡 | Name/rating from store. **"0 rides"** is hardcoded — should reflect a real trip count. |
| KYC card | ✅ | Status-aware copy + colors. |
| Wallet shortcut subtitle | ✅ | Reflects credit / dev-mode / empty correctly. |
| **Quick stats trio** | 🔴 | Hardcoded "RM 1,820 saved · 412 trips · 97% on-time". Tappable → opens Trip History. |
| Settings rows | 🟡 | Privacy/Help push correctly now. "Notifications" pushes real screen but the screen is mock data. |
| Driver mode card | ✅ | Hidden when no driver routes exist. |
| Logout pill | ✅ | Real logout flow with double-tap throttle. |

### Settings (Profile sub-screens)

| Screen | Verdict | Notes |
|---|---|---|
| **Identity Verification (KycVerificationView)** | 🟡 | Real document checklist by role (rider/driver). Upload calls `submitKycDocument(kind:storageUrl:nil)` — **no real photo picker** yet. Comment acknowledges. |
| **Identity Verification (legacy `VerificationView`)** | ⚠️ | Dead code — the file still defines a step-wizard `VerificationView` with mock document/selfie/vehicle sections. Not navigated to anywhere. Remove. |
| **Privacy & Security** | 🔴 | Pure static copy. No real toggles, no real data export, no account deletion. Just "Security Tips". |
| **Help Center** | 🔴 | Static support@voygo.app email + "Available from Inbox tab" + "voygo.app/help" link. None of those are tappable; the email isn't a `mailto:`, the URL isn't a link. |
| **NotificationsView** | 🔴 | Three groups (Today/Yesterday/This week) of fully hardcoded notifications including names ("Aiman is on the way") and amounts ("RM 312 credited to Maybank ··4221"). The "Mark all read" button in the nav bar is plain Text — not a Button. |

### Place picker / Map

| Element | Verdict | Notes |
|---|---|---|
| **PlacePickerSheet** | ✅ | User-scoped recents, Home/Work shortcuts, MKLocalSearch fallback, voiceover-aware focus. Solid. |
| **MapLocationPicker** | ✅ | Reverse-geocode while panning, "Use this location" CTA. |
| **SearchFiltersView** | ✅ | Real bindings flowing through `@Binding` (no more throwaway placeholders). |

---

## Cross-cutting findings

### CC-1 · Mock-data debt is the single biggest user-facing risk

Counting just what's listed above, **23 hardcoded values** that read as live data:

- Profile quick stats (RM 1,820 / 412 trips / 97%).
- Profile identity row "0 rides".
- Trip History: 5 sample trips + 3-stat summary + nav kicker "18 trips".
- Wallet: 3 payment methods + fallback transaction reel.
- LiveTrip: every text field + the GPS dot position.
- Receipt body: all text below the lookup status line.
- BookingConfirmed: "What's next" steps.
- Notifications: 8 sample notifications.
- RateRide invocation: hardcoded driver/route in `AppRouteDestinations`.
- Search hero: "12 routes / N active rides / RM local fares" labels.

**On a real account in dev mode (no backend sync) the user sees a
Frankenstein of mock + real**. They can't tell which is which. That's
the worst kind of trust hole for a transport app.

### CC-2 · `[Voygo]` console diagnostics — gone (good)

Cleaned up in commit `a38f71c`. No further action.

### CC-3 · Dead code

- `Features/Profile/VerificationView` (legacy step wizard, ~150 lines).
- `VoygoNavBar` in `Core/DesignSystem.swift` (unused after migration).
- `VMapPlaceholder` in `Core/Polished.swift` (unused after VRouteDiagram migration).
- `ProfileRoute` enum (replaced by AppRoute, but not yet deleted from the file).

About 350 lines of dead code total. Removing them shrinks the surface and stops developers from accidentally extending the wrong thing.

### CC-4 · Background refreshes

Several screens depend on `store.*` data that nothing refreshes:
- `WalletView`: refreshes payments via `.task` ✅ + pull-to-refresh ✅.
- `DriverPayoutsView`: refreshes via `.task` ✅.
- `MySubscriptionsView`: refreshes via the parent navigator's `.task` only at app start.
- `LiveTripView`: never refreshes its `tripId`'s data.
- `Notifications`: no refresh — it's all hardcoded so there's nothing to refresh, but if it were real, no listener exists.

A central `store.refreshAll()` runs at MainTabView's `.task`, which gets us most cases. But once a real notifications stream / live-tracking exists, each screen needs its own subscription.

### CC-5 · Accessibility — partial

What's good (already QA-fixed):
- `textHint` contrast at 5:1 against the new `bg`.
- Tap targets bumped to 88×44 on KYC upload, 44×44 on LiveTrip icon buttons.
- VoiceOver labels on icon-only buttons (chevron, bell, calendar, payouts).
- KYC progress bar div-by-zero guarded.
- Net-payout uses `.system(.largeTitle)` semantic font for AX5.

What's missing:
- **Most text uses `.font(.system(size: N))`** — doesn't scale with Dynamic Type. Migrate the majority to semantic fonts.
- VoiceOver order on Home: search card should announce after the headline ("Where to, this morning?"), not before.
- Reduced-motion: route diagram + ETA tick don't check `accessibilityReduceMotion`.
- Color-only state distinction in some places (e.g. rating stars filled vs `border`).

### CC-6 · Error states

The typed `AppError` cases (`.unauthorized` / `.network` / `.validation` / `.server` / `.decoding`) are wired in `AppStore` but **call sites still display only `error.localizedDescription`**. Nobody yet branches on the case to surface actionable UX (e.g. "Sign in again" button on `.unauthorized`).

### CC-7 · Loading states

- Most screens have a `LoadingView()` for primary loads.
- No skeleton placeholders. On slow networks the user sees a spinner where a page-shaped grey shimmer would feel faster.

### CC-8 · Routes tab vs Search tab

Renamed in the recent waves but the screen contents still read as a "search-with-extras" experience (mode rail, Driver Dashboard shortcut, etc.). Consider whether the **mode rail** belongs on Search or is better moved into Profile (Driver mode) and Calendar (My Subscriptions) — it's currently duplicated as both a rail on Search and a Profile card.

### CC-9 · Tab re-tap → scroll-to-top

Wave 4 wired the notification but no root subscribes. Easy follow-up: each tab root listens for `.voygoTabReselected` with its index and bumps a `ScrollViewProxy` to top.

### CC-10 · Swipe-back gesture

Deferred from Wave 3. Custom-nav screens disable `interactivePopGestureRecognizer`. Restoring it requires a small UIKit interop — `UIViewControllerRepresentable` wrapper that flips the recognizer's `isEnabled` flag.

---

## Plan: what to do, in order

### Phase A · Stop showing fake data as real (~1–2 days)

The single most important thing. Triage:

1. **Delete dead code** (~30 min)
   - `VerificationView` (legacy).
   - `VoygoNavBar`, `VMapPlaceholder`.
   - `ProfileRoute` enum.

2. **TripHistoryView reads `store.payments`** (~2–3 hrs)
   - Replace the 5-trip array with `store.payments.compactMap { Trip(from: $0) }`.
   - Compute summary stats from real data.
   - Drop the "18 trips" kicker — show actual count.
   - Receipt tap path already works once IDs match.

3. **Profile quick stats become real** (~1 hr)
   - "Saved" = sum of `payment.savings` (need to add field) or `subscriptions × tier discount`.
   - "Trips" = `store.payments.count(where: .paid)`.
   - "On-time" = `store.routes.first?.reliability.onTimeRate * 100` (until backend exposes per-rider).
   - "0 rides" → real trip count.

4. **WalletView payment methods → either real or honest** (~1 hr)
   - Best: backend exposes `/users/me/payment-methods`, we render from there.
   - Fallback: collapse to a single "Add a payment method" empty-state until backend lands.

5. **NotificationsView → either real or removed** (~1 hr)
   - If backend exposes `/users/me/notifications`, render from there.
   - Otherwise: replace with an empty state until it does. Don't ship hardcoded "Aiman is on the way" to a real driver named not-Aiman.
   - Wire bell icon on Home to actually push `.notifications` (not coming-soon).

6. **LiveTripView reads its `tripId`** (~3–4 hrs)
   - `store.rideInstances.first { $0.id == tripId }` — render its route's start/end, driver name, car, ETA.
   - Phone button uses `route.driver.phone` (need to add) → `tel:` URL.
   - Drop GPS dot until tracking is real, OR make it honestly decorative.

7. **ReceiptView body fields** (~1 hr)
   - Backend should thread pickup/drop addresses + driver+vehicle on the payment row. Until then, the hardcoded body is the worst offender — at minimum, switch text to "—" placeholders for fields we can't populate.

8. **BookingConfirmed "what's next"** (~30 min)
   - Tomorrow's first scheduled pickup pulled from `store.upcomingRides`. If empty, omit the section.

9. **RateRide → AppRouteDestinations passes real values** (~1 hr)
   - `path.append(.rateRide(driverInitial:..., driverName:..., summary:...))` already takes args, but `LiveTrip.onEndTrip` ignores them and pushes hardcoded "Aiman / Subang Jaya → KLCC".
   - Wire `LiveTrip` to pass through the actual trip's driver/route.
   - Submit handler should `await store.submitReview(...)` (need to add).

### Phase B · Fix the wired-but-no-op buttons (~1 day)

10. **Home bell** → push `.notifications`.
11. **LiveTrip phone / share** → `tel:` link, share-my-ride link (Phase B-real, P3 #16 from earlier improvements doc).
12. **LiveTrip SOS** → first pass: SMS to a single saved emergency contact. Real V2: backend safety alert. Both gated on contacts permission.
13. **NotificationsView "Mark all read"** → real Button (currently a Text).
14. **Help Center email/FAQ** → `mailto:` and proper `Link(...)` rather than display strings.
15. **Profile rating** — read live from API once it returns it; compute placeholder from store rides for now.

### Phase C · Architectural cleanup (~1 day)

16. **`AppError` switching at call sites** — surface `.unauthorized` as a "Sign in again" CTA, `.network` as "Reconnect" with a retry button. Currently `localizedDescription` is shown but the structural cases go unused.
17. **Skeleton placeholders** for primary loading states on Wallet, TripHistory, RouteDetails, MySubscriptions.
18. **Refresh wiring** — every `.task` on a screen that reads from `store.*` should call the corresponding refresh method explicitly. Today some rely on `MainTabView.task`'s global refresh.
19. **Scroll-to-top on tab re-tap** — wire `.voygoTabReselected` into each tab root.
20. **Swipe-back gesture restoration** — UIViewControllerRepresentable wrapper.

### Phase D · Localization + Dynamic Type (~1.5 days)

21. **Migrate hardcoded copy to `Strings.swift`** (started in commit `6cf1428`, expand to cover every screen).
22. **Migrate `.font(.system(size: N))` → semantic fonts** across all body text.
23. **Bahasa Malaysia** — add `Localizable.strings`. Now that copy is centralized this is a one-day translation pass.

### Phase E · Strategic / external (deferred until product input)

24. iPad layout (`NavigationSplitView`).
25. Real driver KYC photo picker (PHPickerViewController).
26. Real live tracking (SSE/WebSocket from backend).
27. Real Stripe Connect for driver payouts.
28. Real telemetry instrumentation.

---

## What to ship next, concretely

If we cap scope at ~2 days, **Phase A** is the right next batch — it's the single change that flips the app from "pretty demo with fake data" to "functional first-version product". Plus a couple of cheap Phase B items that pair naturally (Home bell, NotificationsView "Mark all read", Help Center mailto/link).

After that the product is honest enough to ship to a real user without them spotting hardcoded strings on a fresh login.

— Generated 2026-05-09. Reflects worktree state at commit `a38f71c`.
