# Voygo — Navigation & UX Audit

Cold walk-through of the navigation graph and per-screen affordances
on commit `d067576`. Reads as a triage list, not as a manifesto.

## Method

Walked every named flow as a fresh user would experience it on the
phone, traced each screen's exit options (custom back button, system
nav, swipe-to-dismiss, tab bar), and noted where the model differs
between physically-similar screens. Where the issue is "this screen
has no exit" the priority is **P0**; where the issue is just polish
(inconsistent chrome, redundant navigation) it's **P1+**.

---

## Inventory: how each screen exits today

| Screen | Reached from | Exit affordances | Notes |
|---|---|---|---|
| **HomeView** | Tab bar (Home) | Tab bar | Root, no back needed |
| **FindCommuteRoutesView** | Tab bar (Routes) **or** Home → Book a ride | Tab bar; **back chevron when pushed** | Just fixed in `d067576` |
| **RouteDetailsView** | Find/Home → tap card | Custom back chevron (`VoygoNavBar`) | OK |
| **CreateRouteView** | Find → menu → Create | Custom back chevron | OK |
| **DriverDashboardView** | Find → menu → Driver Dashboard | Custom back chevron | OK |
| **DriverPayoutsView** | DriverDashboard → "This week" | Custom back chevron | OK |
| **MySubscriptionsView** | Tab (Calendar) **or** Find → menu | Custom back chevron — **but optional `onBack`**; nil hides it | OK as both root + pushed |
| **UpcomingCalendarView** | MySubscriptions, RouteDetails | Custom back chevron | OK |
| **BookingConfirmedView** | RouteDetails (post-subscribe) | **No back, no close** — only "View Receipt" / "See subscription" CTAs | **🚨 P0** |
| **RateRideView** | LiveTrip → "End trip" | "Skip" reuses onBack, "Submit" pops to root | OK but skip-as-back is non-obvious |
| **LiveTripView** | (currently unreachable from UI — RateRide normally follows) | Custom back chevron | OK |
| **WalletView** | Profile → Wallet | Custom back chevron | OK |
| **TripHistoryView** | Profile → Trips | Custom back chevron | OK |
| **ReceiptView** | TripHistory → row, Wallet → row | Custom back chevron | OK |
| **NotificationsView** | Profile → Notifications | Custom back chevron | OK |
| **KycVerificationView** | Profile → KYC card | Custom back chevron | OK |
| **PrivacySecurityView** | Profile → Privacy | **`.sheet`** — swipe-to-dismiss + custom Done | OK but **inconsistent** (everything else is push) |
| **HelpCenterView** | Profile → Help | **`.sheet`** — swipe-to-dismiss + custom Done | Same pattern as Privacy |
| **InboxView** | Tab (Inbox) | Tab bar | Root |
| **ChatThreadView** | Inbox row | **System back arrow** (NavigationLink + `navigationTitle`) | **🚨 inconsistent** with rest of app |
| **ProfileView** | Tab (Profile) | Tab bar | Root |
| **AuthPhoneView** | Pre-auth root | n/a (root pre-login) | OK |
| **AuthOtpView** | AuthPhone → Send OTP | Custom back chevron | OK |
| **PlacePickerSheet** | CreateRoute, FindCommute query field | `.sheet` — swipe-to-dismiss + Cancel | OK |
| **MapLocationPicker** | Inside PlacePickerSheet | "Use this location" CTA returns to picker | OK |
| **PaymentCheckoutSheet** (Billplz) | RouteDetails → Subscribe & pay | Sheet — paid-or-cancelled return-URL handling | OK |
| **SearchFiltersView** | Find → filter pill | Custom back chevron | OK |

---

## Dead-ends and inconsistencies (priority order)

### 🚨 P0 — Things the user can get visibly stuck on

**1. BookingConfirmedView has no escape hatch.**
- After a successful subscription, the user lands on the "Booking confirmed" screen with two big buttons: "View Receipt" and "See subscription". There's no back chevron, no close X, no swipe-to-dismiss (it's a push, not a sheet).
- **Fix:** add a small "Done" pill in the top-right of the hero that pops back to root (`path = []`). Mirrors the pattern most apps use on confirmation screens. Don't add a back chevron — the *previous* screen was the payment checkout sheet, returning there would be wrong.

**2. ChatThreadView uses a different navigation system than the rest of the app.**
- Inbox uses iOS system-default `NavigationLink` + `navigationTitle`, so the back button is the system blue chevron labeled "Inbox". Every other screen in the app uses `VoygoNavBar` / `VPolishedNavBar` with custom green-on-translucent chevron pills.
- Visually feels like a different app once you tap a chat row.
- **Fix:** rebuild ChatThreadView around `VPolishedNavBar(title: thread.title, onBack: …)` like the rest. Keep using `NavigationStack(path:)` for the inbox so back is just `path.removeLast()`.

**3. Skip-as-back on RateRide is non-obvious.**
- Top-left chevron on `RateRideView` is bound to `onSkip`, which pops back to root. The user reads it as "back to LiveTrip" but it actually clears the whole nav stack.
- **Fix:** label-disambiguate. The chevron should pop one level (back to LiveTrip), and the visible "Skip" button (right-aligned in the nav bar) should remain the "skip rating, return to root" path.

### 🟧 P1 — Inconsistencies that compound annoyance

**4. Two nav-bar components doing the same job.**
- `VoygoNavBar` (legacy) and `VPolishedNavBar` (new) both render a title + back chevron + optional trailing slot. Eight screens use one, eight use the other. The visual is similar but the chevron styles differ subtly (the older one is a hairline outline, the newer one is a filled white circle).
- **Fix:** delete `VoygoNavBar`, migrate the eight callsites. Aesthetic alignment, no behavior change.

**5. Profile uses its own `ProfileRoute` enum; not unified into `AppRoute`.**
- Every other tab now uses the shared `AppRoute` enum (commit `34aaea9`). Profile still has `wallet / tripHistory / notifications / receipt / driverDashboard / driverPayouts / kyc`.
- Side effect: a deep link like `voygo://wallet` would have to know whether to open it inside the Profile tab or Home tab — the current split makes that ambiguous.
- **Fix:** add the seven Profile destinations to `AppRoute` and have the Profile tab use `appRouteDestinations(...)` like the others.

**6. Privacy & Help present as sheets while every other Profile destination pushes.**
- Inconsistent with the rest of the Profile menu. The only thing that justifies a sheet is brief, modal, dismissible content — these are full settings pages with lots of toggles.
- **Fix:** convert both to push destinations. If the multi-screen settings group ever grows, sheets are fine for *those*, but the entry point should be a push.

**7. Routes tab opens straight on the Find/Search screen, not a "Routes home".**
- The Routes tab root is `FindCommuteRoutesView`, which is a search screen. Tapping the Routes tab in the bottom bar takes you to the same place "Book a ride" from Home does. Confusing — Routes tab feels redundant.
- **Fix (option A):** make the Routes tab show a list of the user's currently-active routes (subscribed routes) with a "Book another route" CTA at the top. The search becomes a destination off that.
- **Fix (option B):** rename the tab to "Search" so its purpose matches its content.

### 🟨 P2 — Polish that compounds first impressions

**8. Tab bar covers content on long screens.**
- Several screens (`HomeView`, `FindCommute`, `MySubscriptions`) add bottom padding `108–110pt` to clear the tab bar. The number is hand-tuned per-screen and drifts. SafeArea handling for the floating tab bar should live in one place.
- **Fix:** wrap each tab root in a single `tabBarSafeArea(...)` modifier that reads the actual tab bar height.

**9. ProfileView's NavBar has no trailing content; Wallet's does.**
- Wallet has an "Up-arrow" / share button in the top-right. Profile and TripHistory don't, but they have actions (logout, filter) that could live there.
- Minor consistency issue. Decide a rule and apply.

**10. No system back-swipe gesture support on custom-nav screens.**
- iOS users expect swipe-from-left-edge to pop. Because every screen sets `.navigationBarHidden(true)` and uses custom chevrons, the system `interactivePopGestureRecognizer` is disabled.
- **Fix:** in each `.navigationBarHidden(true)` view, add `.toolbar(.hidden, for: .navigationBar)` (modern API) and explicitly enable the swipe-back gesture, OR ditch the custom nav bars and use `toolbar` items with the system bar.
- This is mid-effort but pays back every screen. A user expecting swipe-back will tap → mis-tap → frustration.

**11. RouteDetails' "Subscribe & pay RM …" button is the only way to commit.**
- If the user wants to come back later, there's no "save for later" or wishlist. They lose context and need to refind the route.
- **Fix:** add a heart/bookmark in the nav bar trailing slot. Bookmarks cluster under a new "Saved routes" section in MySubscriptions. (Touches AppStore — small but adds real product value.)

**12. Empty states feel thin.**
- Inbox empty state ("No messages") is a single line with an icon. MySubscriptions empty doesn't exist explicitly — the screen just renders a blank list.
- **Fix:** illustrated empty states with one-tap CTAs ("Find a route" → Routes search, "Start a chat" → noop / coming soon).

### 🟦 P3 — Nice to have

**13. No haptic feedback on primary CTAs.**
- "Book a ride", "Subscribe & pay", "Send OTP" are the three highest-stakes taps. None of them fire `UIImpactFeedbackGenerator`. Modern iOS apps do.
- **Fix:** wrap `VPrimaryButton` action in a `.sensoryFeedback(.success, trigger:)` modifier (iOS 17+) or `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` in the button's action.

**14. Loading states inside push transitions show a blank screen.**
- E.g. RouteDetails on first load briefly shows the empty info card before the route arrives. Fine for sub-200ms loads but jarring on slow network.
- **Fix:** skeleton placeholders for route card, suggested rides, payment list.

**15. No "scroll to top" on tab re-tap.**
- iOS convention: tap the active tab again to scroll to top. Voygo does nothing.
- **Fix:** track tap-on-active-tab and broadcast a "scrollToTop" notification each tab can subscribe to.

---

## Recommended sequencing (this is the plan)

**Wave 1 — kill the dead-ends (~half a day)**
- P0 #1: BookingConfirmed — Done pill in nav.
- P0 #2: Chat thread — switch to VPolishedNavBar.
- P0 #3: RateRide chevron vs Skip — disambiguate.

**Wave 2 — alignment (~half a day)**
- P1 #4: delete `VoygoNavBar`, migrate 8 callsites to `VPolishedNavBar`.
- P1 #5: lift Profile destinations into `AppRoute`.
- P1 #6: Privacy & Help → push.

**Wave 3 — product affordances (~1 day)**
- P1 #7: Routes tab pivot (option A: list + search-as-destination, OR option B: rename to Search).
- P2 #8: tab bar safe-area helper.
- P2 #10: swipe-back gestures across all custom-nav screens.

**Wave 4 — polish (open-ended)**
- P2 #11–15.
- P3 #13: haptics on primary CTAs.
- Skeleton placeholders.
- Empty-state illustrations.
- Scroll-to-top on tab re-tap.

---

## Notes the audit missed (parking lot)

- The `print("[Voygo] …")` diagnostics added in commit `9da30ca` should come out before any release. They're cheap, but they shouldn't ship.
- iPad layout still entirely missing — every screen is iPhone-shaped.
- No deep linking; the URL scheme `voygo://` only handles the Billplz return.
- KycVerificationView's progress bar logic was QA-fixed but the screen has no failure-state UI ("upload failed" → ?).

— Generated 2026-04-30. Reflects worktree state at commit `d067576`.
