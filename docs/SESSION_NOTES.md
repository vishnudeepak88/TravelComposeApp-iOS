# Voygo — Session handoff notes

> **READ ME FIRST after any context compaction or new session.**
> Every chunk of work this agent finishes appends a section here.
> Resume by scrolling to the bottom and continuing from "Open work
> items" — don't re-derive state from scratch.

## How to use this file

1. **At session start** (after compaction or fresh start): read this whole
   file top-to-bottom, then `git log --oneline -20` to see actual
   commit state. The notes describe intent; commits are ground truth.
2. **At the end of each meaningful work chunk** (right before a likely
   compaction): append a new dated section with:
   - what just shipped
   - commit shas
   - per-screen / per-file state changes
   - **Open work items** — the carry-forward list
3. **When picking up work**: scan the most recent "Open work items"
   list, pick the top item, work it, then add a new note section.

Keep entries short. The goal is "I had to step away — what was I
doing?" not a full audit doc (those live alongside as
`UX_AUDIT_*.md`, `ARCHITECTURE.md`, `ROADMAP.md`).

---

## 2026-05-09 · session checkpoint after `60adbfb`

### What's running on `main`

```
60adbfb  Adaptive Home + backend-backed Notifications
fcf50c8  Harden backend marketplace flows           ← user's commit
5ece9b1  Pure-iOS gap closures (AppError surface,
         skeletons, Dynamic Type ladder, Bahasa
         Malaysia scaffold)
5f7cb3d  docs/ROADMAP.md — implementation cookbook
ef7b13e  v1 gap fixes (Search stats, skeletons,
         swipe-back, share, SOS, KYC photos)
```

### Concrete state per area

**Auth**
- Real OTP/JWT against backend; dev shortcut behind `#if DEBUG`
- `AppError` typed cases (`.unauthorized / .network / .validation /
  .server / .decoding / .message`) wired through, surfaced via
  `VErrorBanner` on AuthPhone + AuthOtp. Other call sites still on
  flat strings — that's the next sweep target.

**Home (super-app)**
- Vibrant green palette (`#00B14F` primary)
- Adaptive: search-first when no active subscription; "Next commute"
  card first under the hero when subscribed
- Bell shows coral unread badge when `store.unreadNotificationsCount > 0`
- Tap-the-active-tab scrolls to top via `.voygoTabReselected` notif

**Search / Find Commute**
- `POST /commute/search` with `CommuteMatchingEngine` offline fallback
- Hero stats real (`store.routes.count`, active subs, avg fare from
  real prices)
- Optional `onBack` chevron when pushed from Home; nil when tab root

**Route Details**
- Real route + driver + reliability data, real Subscribe & pay flow
  through Billplz checkout sheet, deep-link return
- Skeleton placeholder during initial load (`VSkeleton`)

**Subscriptions / Calendar**
- Real `store.mySubscriptions()`, atomic two-step cancel with rollback,
  retry-payment on paused subs

**Live Trip**
- Reads `tripId` from `store.rideInstances`; pickup/drop/driver real
- Phone button: `tel://` when `route.driverPhone` is non-nil; disabled
  with proper a11y label otherwise
- Share button: `ActivityShareSheet` (UIActivityViewController) with
  trip context + `voygo://rides/<id>` deep link
- SOS: `MFMessageComposeViewController` (`MessageComposerView`)
  pre-filled with route summary + driver + ETA + share URL.
  Honest fallback sheet when device can't send SMS.
- ETA + GPS dot still demo (need backend tracking)

**Wallet / Trip History / Receipt**
- Real `store.payments`; honest empty states
- Wallet payment-methods list is empty until backend exposes them
- Receipt body resolves driver+route from `payment.routeId` lookup,
  "—" placeholder when route gone
- Both screens have skeleton placeholders during first refresh

**Driver Dashboard / Create / Payouts**
- All real backend calls; pause/resume + schedule update with double-
  fire guards + confirmation alerts

**KYC**
- `KycVerificationView` is real with real role checklist
- Photo upload uses `PhotoPicker` (PHPicker wrapper); image bytes are
  observed locally — backend S3 path still TODO
- `NSPhotoLibraryUsageDescription` added to auto-Info.plist

**Inbox / Chat**
- Real threads + messages
- Chat now uses `VPolishedNavBar` (was system NavigationLink)
- `ChatThread.tripId` is the route_id from `chat_threads.route_id`
  (used by Home Next-commute "Message" pill to detect existing thread)

**Profile**
- Real Trips count + Saved (via `SubscriptionPricing.savingsVsDaily`)
  + On-time avg from active routes' reliability
- Privacy & Help pushed to `AppRoute` (formerly `.sheet`)
- Help Center has real `mailto:` and `https://voygo.app/help` links
- Profile destinations live in shared `AppRoute` enum

**Notifications**
- Backend-backed via `GET /notifications/me` and `PUT
  /notifications/{id}/read`
- `NotificationDTO` has `id, type, title, body, routeId?,
  subscriptionId?, rideInstanceId?, readAt?, createdAt`
- Time-bucketed groups in `NotificationsView` (Today / Yesterday /
  This week / Earlier)
- Tap row → optimistically mark-read + drill-in to RouteDetails /
  MySubscriptions / Calendar where applicable
- Mark-all-read iterates unread ids
- Unread badge on Home bell

**Architecture / cross-cutting**
- iOS 26 + Swift 6 + `@Observable` everywhere
- Single shared `AppRoute` enum + `appRouteDestinations(...)` modifier
- Custom `VPolishedNavBar` everywhere (`VoygoNavBar` deleted)
- `VTabBarLayout.clearance` constant replaces 4 hand-tuned bottom
  paddings
- `enableSwipeBack()` UIKit interop on every tab root NavigationStack
- Strings.swift resolves through `NSLocalizedString` with English
  fallbacks; `Localizable.strings` for `en` + `ms` (Malay first-pass
  needs native review); HomeView keys flow through it
- `Font.vTitle / .vHeadline / .vBodyHeavy / .vBody / .vCaption /
  .vMonoSmall` semantic ladder defined; per-screen sweep TODO
- `[Voygo]` print diagnostics removed
- ~265 lines of dead code removed (`VerificationView` step wizard,
  `VoygoNavBar`, `VMapPlaceholder`, `ProfileRoute` enum)

**Backend**
- `5c82309` (re-applied as `fcf50c8`) hardened the marketplace flows
- `/notifications/me` and `/notifications/:id/read` exposed
- `chat_threads.route_id` populated; surfaced as `tripId` in DTO

### Docs in repo (referenceable)

- `docs/ARCHITECTURE.md` — find-ride flow + function map (current
  vs. ideal v1)
- `docs/ROADMAP.md` — implementation cookbook for deferred items
  (AppError surface, Dynamic Type, BM, iPad, telemetry, push,
  tracking, SOS backend, Stripe Connect)
- `docs/UX_AUDIT.md`, `docs/UX_AUDIT_DEEP.md`, `docs/UX_AUDIT_AFTER.md`
  — three iterations of the screen audit
- `docs/REDESIGN.md`, `docs/IMPROVEMENTS.md` — earlier planning docs

### Open work items (carry-forward)

These are doable in code without backend changes:

1. **AppError UI surface across remaining call sites** — `VErrorBanner`
   exists; replace `Text(err.localizedDescription)` in
   `RouteDetailsView`, `MySubscriptionsView`, `KycVerificationView`,
   `CreateRouteView`. ~15 call sites. Each follows the same pattern
   already in `AuthPhoneView`/`AuthOtpView`.
2. **Dynamic Type sweep** — `Font.vTitle / .vBodyHeavy / .vCaption`
   etc. exist. Sweep `.font(.system(size: N, weight: …))` literals
   to semantic fonts. ~1 day, mechanical, touches every view. Test
   at AX5 for clipping.
3. **Scroll-to-top opt-in for Search / Trips / Inbox / Profile** —
   Home subscribes to `.voygoTabReselected`. Apply the same 5-line
   pattern (`ScrollViewReader` + `Color.clear.id("top")` + `.onReceive`)
   to the other tab roots.
4. **Cross-tab Inbox deep-link to specific thread** — Home's
   "Message" pill currently switches to the Inbox tab root. To open
   the actual chat thread we need `Inbox`'s `NavigationPath`
   addressable cross-tab. Options: lift InboxRoute path into a shared
   observable, or post a richer notification that Inbox listens for.
5. **AppError surface for notifications** — `markNotificationRead`
   rolls back silently on failure; consider a `lastNotificationsError`
   + a small inline `VErrorBanner` above the list.
6. **Skeleton coverage** — RouteDetails / Wallet / TripHistory /
   Notifications all have skeletons. MySubscriptions and DriverDashboard
   still spinner-load. Apply `VSkeleton` rows.
7. **Deferred from `docs/ROADMAP.md`** that need backend or weeks:
   real GPS tracking, real `/safety/sos` ping, Stripe Connect, push
   notifications + `/notifications` realtime, iPad layout, telemetry
   SDK, full BM translation review.

### Re-deploy quick reference

```bash
# CI-equivalent build (simulator; matches the GitHub workflow)
xcodebuild -project TravelComposeApp.xcodeproj \
  -scheme TravelComposeApp \
  -destination 'generic/platform=iOS Simulator' build

# Real-device deploy (iPhone 16 Pro):
xattr -cr build && \
  xcodebuild -project TravelComposeApp.xcodeproj \
    -scheme TravelComposeApp \
    -destination 'platform=iOS,id=A7CA22FB-811C-57E3-BAE3-8BC0DA897E44' \
    -configuration Debug -derivedDataPath build build && \
  xcrun devicectl device install app \
    --device A7CA22FB-811C-57E3-BAE3-8BC0DA897E44 \
    build/Build/Products/Debug-iphoneos/TravelComposeApp.app && \
  xcrun devicectl device process launch \
    --device A7CA22FB-811C-57E3-BAE3-8BC0DA897E44 \
    com.voygo.travelcomposeapp

# Backend syntax checks (Codex node lives at this path):
NODE=/Applications/Codex.app/Contents/Resources/node
$NODE --check backend/src/server.js
$NODE --check backend/src/repository.js
$NODE --check backend/src/schema.js
$NODE --check backend/src/seed.js

# Phone identifier resolution:
xcrun devicectl list devices
```

### Force-push lessons learned

- The user pushed `5c82309` (Harden backend marketplace flows)
  while this agent was working. Force-pushing without `git fetch`
  first overwrote that commit. Recovered by cherry-picking from
  the local reflog.
- **Default protocol going forward**: before any `git push --force*`
  to `main`, run `git fetch origin && git log --oneline
  HEAD..origin/main` to see what would be lost. If anything shows,
  rebase or merge first.

---

## Template for the next session entry

```
## YYYY-MM-DD · session checkpoint after `<sha>`

### What just shipped
- one line per logical chunk + commit sha

### Per-screen / per-file changes since last note
- only what changed, not the full state

### Open work items (carry-forward)
- ranked list — top is the next thing to pick up
```

— First entry generated 2026-05-09 against commit `60adbfb`.

---

## 2026-05-09 (later) · session checkpoint after `599dd5b` + skills

### What just shipped
- `.claude/skills/` library — 7 reusable skill markdowns + README
  index. Captures every pattern from this build-out so a future
  session (this repo or another) can pull a playbook off the shelf.

### Skills shipped

| Skill | Captures |
|---|---|
| `ios-swiftui-bootstrap` | iOS 26 + Swift 6 + @Observable scaffold, AppRoute, AppStore, custom nav |
| `ios-design-system-port` | Palette enum, atom set, VErrorBanner, semantic Dynamic-Type fonts, Strings.swift + lproj |
| `ios-ux-audit-and-fix` | Per-screen audit methodology + phased fake-data sweep |
| `ios-real-device-deploy` | xcodebuild + devicectl recipe + xattr/codesign troubleshooting |
| `xcode-ci-setup` | GitHub Actions for Xcode projects, SDK-mismatch overrides |
| `ios-system-integrations` | PHPicker, MFMessageComposeVC, ActivityVC, swipe-back, tel://, deep links — all Swift 6 strict-concurrency safe |
| `backend-ios-pairing` | DTO + APIClient method + AppStore optimistic-write + typed AppError pattern |
| `session-handoff-ledger` | This file's own protocol. Meta-skill. |

Index lives at `.claude/skills/README.md` with a one-line trigger
for each skill so fresh sessions can match request → skill quickly.

### Open work items (carry-forward)

Same as the previous checkpoint — the skills work doesn't change
what's in-flight on the product. The top item is still:

1. **AppError UI surface across remaining call sites** — `VErrorBanner`
   exists, replace `Text(err.localizedDescription)` in
   RouteDetailsView, MySubscriptionsView, KycVerificationView,
   CreateRouteView. ~15 call sites.
2. Dynamic Type sweep across feature views.
3. Scroll-to-top opt-in for Search/Trips/Inbox/Profile.
4. Cross-tab Inbox deep-link to specific thread.
5. Remaining items per `docs/ROADMAP.md`.
