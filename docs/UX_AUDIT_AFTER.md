# Voygo — Deep Audit: After-Snapshot

Companion to `docs/UX_AUDIT_DEEP.md`. Walks the same surfaces and
shows what flipped from 🟡/🔴 to ✅ after commit `a1b790b` (Phase A+B
of the plan), and what's still pending.

## Mock-data debt — before vs. after

| # | Surface | Before | After | Status |
|---|---|---|---|---|
| 1 | TripHistory list | Hardcoded 5 trips ignoring `store.payments` | Reads `store.payments`, maps each to a row, real "no trips yet" empty state | ✅ Fixed |
| 2 | TripHistory summary stats | "RM 252 / RM 168 / 94%" | "Total / Trips / Refunded" computed from real payments | ✅ Fixed |
| 3 | TripHistory nav kicker | "Last 30 days · 18 trips" | "0/1/N trips" — actual count | ✅ Fixed |
| 4 | Profile quick stats | "RM 1,820 saved · 412 · 97%" | Saved = `SubscriptionPricing.savingsVsDaily`; Trips = paid count; On-time = avg reliability or "—" | ✅ Fixed |
| 5 | Profile identity "0 rides" | Hardcoded literal | Real trip count from store | ✅ Fixed |
| 6 | Wallet payment methods | 3 fake cards (DuitNow ··4221 etc.) | Empty state "Add a card or e-wallet to subscribe to routes" | ✅ Fixed |
| 7 | Wallet recent transactions fallback reel | 5 hardcoded txs ("Subang → KLCC · Aiman Z.") | Empty state when `store.payments` empty | ✅ Fixed |
| 8 | Notifications reel | 8 fake notifications | Empty state with `bell.slash` icon | ✅ Fixed |
| 9 | Notifications "Mark all read" | Inert Text | Real Button (disabled when list empty) | ✅ Fixed |
| 10 | LiveTrip pickup/drop addresses | "USJ 9 LRT" / "KLCC Tower B" hardcoded | Resolved from `route.pickupPoints.first.label` / `route.dropPoints.first.label` | ✅ Fixed |
| 11 | LiveTrip driver row | "Aiman Z. · Tesla Model 3 · VEC 4123" | Real `route.driverName` + `route.carType.label` + "plate on file" | ✅ Fixed |
| 12 | LiveTrip route diagram stops | Hardcoded 4 stops | Computed from the resolved route | ✅ Fixed |
| 13 | LiveTrip phone button | No-op masquerading as live | Disabled with proper accessibilityLabel "Call driver" | 🟡 Partial — needs driver phone on the model |
| 14 | LiveTrip share button | No-op | _unchanged_ | 🟡 Pending |
| 15 | LiveTrip GPS dot | Static circle | _unchanged_ — kept as decorative until real tracking lands | 🟡 Pending (needs backend tracking) |
| 16 | LiveTrip ETA countdown | Hardcoded 12 → 0 over 12 minutes | _unchanged_ — same demo behavior | 🟡 Pending (needs ETA service) |
| 17 | LiveTrip SOS | Alert with no real action | _unchanged_ | 🟡 Pending (needs ContactsUI + SMS plumbing) |
| 18 | Receipt body — pickup/drop | "USJ 9 LRT" / "KLCC Tower B" | Resolved from route lookup; "—" placeholder when route is gone | ✅ Fixed |
| 19 | Receipt body — driver | "Aiman Z." / "Tesla Model 3 · VEC 4123" / "5.0" | Real driverName / carType.label; rating row hidden when no data | ✅ Fixed |
| 20 | BookingConfirmed "What's next" | "Daily 7:42 AM events" / "1 seat left" hardcoded | Generic CTAs anchored on real `pickup` and `driverName` | ✅ Fixed |
| 21 | RateRide invocation | Hardcoded "A / Aiman / Subang Jaya → KLCC" in AppRouteDestinations | Real values forwarded from LiveTrip's `onEndTrip(initial, name, summary)` | ✅ Fixed |
| 22 | Home bell button | "Coming soon" alert | Pushes `.notifications` | ✅ Fixed |
| 23 | Help Center email / FAQ | Inert text rows | SwiftUI `Link` to `mailto:support@voygo.app` and `https://voygo.app/help` | ✅ Fixed |

**Tally:** 18 of 23 fully fixed; 5 partial/pending — all on `LiveTripView` (phone, share, GPS dot, ETA countdown, SOS) and gated on backend or device-permission work that exceeds Phase A scope.

## Dead code — before vs. after

| Component | Before | After |
|---|---|---|
| `VerificationView` step wizard + `VerificationViewModel` + `Document/Selfie/Vehicle` sections | ~150 lines, unused | Removed |
| `VoygoNavBar` | ~35 lines, unused after Wave 2 | Removed |
| `VMapPlaceholder` | ~80 lines, unused after VRouteDiagram migration | Removed |
| `ProfileRoute` enum | Replaced by AppRoute but still in file | Removed (folded into AppRoute) |

**Net:** ~265 lines of dead code removed; legacy `import Combine` already cleared in earlier waves; `VoygoTheme` color aliases retained intentionally for the deprecation window.

## Per-screen verdict, after Phase A+B

| Screen | Before | After |
|---|---|---|
| AuthPhoneView | ✅ | ✅ |
| AuthOtpView | ✅ | ✅ |
| **HomeView** | 🟡 (bell coming-soon) | ✅ Bell pushes notifications |
| Search (renamed Routes) | 🟡 (hardcoded stats labels) | 🟡 _unchanged_ (low-impact polish) |
| RouteDetails | ✅ | ✅ |
| BookingConfirmedView | 🟡 (hardcoded what's-next) | ✅ Generic copy anchored on real values |
| **MySubscriptions / Calendar** | ✅ | ✅ |
| LiveTripView | 🔴 (every text + dot fake) | 🟡 Pickup/drop/driver real; ETA/GPS/phone/SOS still demo |
| RateRideView | 🟡 (got hardcoded values from caller) | ✅ Receives real driver+route from LiveTrip |
| **WalletView** | 🟡 (3 fake methods + sample reel) | ✅ Empty states; real `store.payments` only |
| **TripHistoryView** | 🔴 (entirely hardcoded) | ✅ Real payments + summary; honest empty state |
| ReceiptView | 🟡 (hardcoded body) | ✅ Real driver/route or "—" placeholders |
| DriverDashboardView | ✅ | ✅ |
| CreateRouteView | ✅ | ✅ |
| DriverPayoutsView | 🟡 (no auto-refresh) | 🟡 _unchanged_ |
| InboxView | ✅ | ✅ |
| ChatThreadView | ✅ | ✅ |
| **ProfileView** | 🟡 (fake quick stats + "0 rides") | ✅ Real stats from store |
| **NotificationsView** | 🔴 (entirely hardcoded) | ✅ Empty state + real Button |
| KycVerificationView | 🟡 (no photo picker) | 🟡 _unchanged_ — needs PHPicker |
| PrivacySecurityView | 🔴 (static copy) | 🔴 _unchanged_ — content audit deferred |
| **HelpCenterView** | 🔴 (inert text rows) | ✅ Real `mailto:` and FAQ link |
| PlacePickerSheet | ✅ | ✅ |
| MapLocationPicker | ✅ | ✅ |
| SearchFiltersView | ✅ | ✅ |

## What's still pending (organized by urgency)

### Still pending P1 (worth a second batch)

1. **LiveTrip phone button working** — needs `driverPhone: String` on the route/driver model so it can open `tel://`. Currently disabled with a real `accessibilityLabel("Call driver")` so VoiceOver users hear it as inactive rather than "button" with no handler.

2. **LiveTrip ETA / GPS dot honesty** — both are timer-driven demos. Two paths:
   - Wait for backend tracking (real fix, weeks) and remove the demo.
   - Render an "Approximate" badge so the rider knows the figure is a stub, not GPS.

3. **LiveTrip SOS plumbing** — needs:
   - Contacts permission via `ContactsUI`.
   - One designated emergency contact picked from settings.
   - `MFMessageComposeViewController` with location URL.
   - Backend `/safety/sos` ping with rider+ride context.

4. **DriverPayoutsView auto-refresh** — `store.refreshPayout()` exists but no view triggers it (currently relies on global app-load refresh). Add a `.task` like Wallet has.

5. **AppError UI surface (Phase C.1 deferred)** — typed cases (`.unauthorized` / `.network` / `.validation` / `.server` / `.decoding`) are wired, but every call site still shows `error.localizedDescription`. Branch on cases at the screens that consume `Result<_, AppError>` (auth screens, RouteDetails, MySubscriptions) to surface actionable CTAs (sign-in-again on `.unauthorized`, retry on `.network`).

6. **Search hero stats hardcoded** — "12 routes / N active rides / RM local fares" labels in `FindCommuteRoutesView.homeHero`. Should reflect `store.routes.count`, etc.

### Still pending P2 (polish)

7. **Search empty state (no queries entered)** — section just doesn't render. Better to show an illustrated empty state pointing the user at the search fields.

8. **PrivacySecurityView content** — currently just static "Security tips". Real Privacy screen would have data-export request, account deletion, location-sharing toggles. Product input needed.

9. **Skeleton loading placeholders** — Wallet, RouteDetails, MySubscriptions show `LoadingView()` (a spinner). Page-shaped grey shimmer would feel faster on slow networks.

10. **Scroll-to-top on tab re-tap** — notification is wired (`.voygoTabReselected`) but no root subscribes. Each tab opt-in is ~5 lines.

11. **Swipe-back gesture restoration** — custom-nav screens disable `interactivePopGestureRecognizer`. UIKit interop wrapper would re-enable it.

12. **Hardcoded copy → `Strings.swift`** — started in commit `6cf1428` for a few common strings; expand to cover the remaining ~50 user-visible literals. Unlocks Bahasa Malaysia.

13. **Dynamic Type** — most fonts use `.font(.system(size: N))`. Migrate body text to semantic fonts (`.body`, `.headline`, `.subheadline`). Largely mechanical but touches every view.

### Still pending P3 (strategic)

14. **iPad layout** — `NavigationSplitView`. Out of scope for v1.
15. **KYC photo picker** — `PHPickerViewController` + S3 upload.
16. **Real driver tracking** — SSE or WebSocket from backend; replace LiveTrip demo behavior.
17. **Stripe Connect for driver payouts** — Billplz handles charging; payouts are still aspirational.
18. **Telemetry** — `Services/Telemetry.swift` is a stub. Pick a backend (Posthog / Amplitude / MetricKit) and instrument the funnel.
19. **iPhone push notifications** — UNUserNotificationCenter + APNs registration; once `/notifications` endpoint exists, populate the screen and badge the bell.

## Net effect

**Before:** A real user logging in saw a polished mock with 23
hardcoded values that read as live data. They couldn't tell which
parts were real.

**After:** A real user sees real data from `store.*` everywhere we
have real data, and honest empty states (or `—` placeholders) where
we don't. The screens that still degrade to demo behavior — LiveTrip
ETA, GPS dot, phone, SOS — are five of the original 23, all
concentrated on a single screen, all gated on backend or
device-permission work that's larger than a single batch.

The redesign + refactor work since the start of this session has
landed:
- Vibrant super-app palette (`5d92a2f`).
- Home tab + RouteDiagram (`ebddb2c`).
- Tap-fix iterations (`304d55f`, `67bfff6`, `a406a2a`, `9da30ca`).
- UX waves 1-4 (`a38f71c`).
- Phase A+B fake-data sweep (`a1b790b`).

All while keeping the build green for iOS 26 + Swift 6 in default
mode and the GitHub macos-15 runner.

— Generated 2026-05-09. Reflects worktree state at commit `a1b790b`.
