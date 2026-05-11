# Codex Handoff

Date: 2026-05-12
Current goal: Fix pilot UI/navigation issues found during real-device/simulator testing.
Branch: main

## Completed
- Fixed backend route driver names so account UUIDs are never stored or returned as public `driverName` fallbacks. New fallback is `Voygo Driver`; route reads now prefer `users.display_name` over stale `recurring_routes.driver_name`.
- Added iOS defensive decoding so existing production rows whose `driverName` is a UUID render as `Driver` instead of exposing the raw identifier.
- Fixed `voygo://routes/:id` deep links by storing a pending route id in `MainTabView` and letting `CommuteTab` consume it after the Search tab exists.
- Fixed Home `See all` / carpool search entry so it switches to the real Search tab instead of pushing the Search screen under Home.
- Added backend regression tests for public driver-name sanitization.
- Verified simulator flow after fix:
  - `/tmp/voygo-ui-captures/sim-fixed-see-all-search-tab.png`
  - `/tmp/voygo-ui-captures/sim-fixed-route-deeplink-details.png`
- Built, installed, and launched the fixed app on `Vishnu’s iPhone` (`com.voygo.travelcomposeapp`) using `/tmp/voygo-phone-ui-build/Build/Products/Debug-iphoneos/TravelComposeApp.app`.
- Replaced the abstract route visuals on route detail, receipt, and live trip surfaces with `VRouteMapPreview` using Apple Maps tiles.
- Upgraded `VRouteMapPreview` to calculate MapKit driving legs between every pickup/drop point, draw each road segment, sum road distance + ETA, and show a badge like `23.4 km · 38 min`.
- Added graceful MapKit fallback behavior: failed legs render as dashed direct estimates and the badge switches to `Partial` or `Direct` instead of pretending the route is fully road-resolved. Partial/direct fallback shows distance only; full Apple routing shows distance + ETA.
- Added an `Open` map action to `VRouteMapPreview`; users can choose Apple Maps or Google Maps. Google Maps opens the native app when installed and falls back to Google Maps web with waypoints.
- Built, installed, and launched the updated iOS app on `Vishnu’s iPhone` (`com.voygo.travelcomposeapp`) with process launch outcome `success`.
- Fixed the Home `See all` / Find Routes flow so it no longer runs a blank stale search that can show the dev KL/Subang route.
- Changed route map previews with missing/zero coordinates to show an honest `Map unavailable` state instead of falling back to a hard-coded KL map.
- Fast-forwarded local `main` to `origin/main` at `f6a58c3`.
- Re-read Voygo project handoff and project map.
- Confirmed recent upstream changes already added privacy manifest, entitlements, account deletion/privacy controls, and backend deletion routes.
- Patched Xcode target settings so `TravelComposeApp/Info.plist` is wired into the generated app metadata, preserving the `voygo://` URL scheme.
- Replaced fake booking-confirmation pickup/driver values with route/subscription-derived values.
- Wired Live Trip's message action to the existing Inbox deep-link path.
- Added product analytics consent in Privacy & Security, persisted through `/users/me/preferences`, and enforced it in iOS telemetry and the backend telemetry endpoint.
- Changed SOS from a silent/fake notification path into honest client status plus real env-gated Twilio/PagerDuty dispatch.
- Hardened auth so deleted accounts return 410 on every protected route, and OTP sign-in clears `deleted_at` to cancel deletion inside the grace window.
- Added admin KYC queue/decision endpoints so APPROVED/REJECTED no longer require direct DB edits.
- Changed production KYC upload to fail safe until durable object storage is implemented; non-production local disk remains available for testing.
- Wired push ride notifications into LiveTrip navigation, gated push permission requests behind `AppCapabilities`, and removed dead share/finance buttons.
- Added backend auth regression tests.

## Files touched
- `docs/CODEX_HANDOFF.md`
- `TravelComposeApp.xcodeproj/project.pbxproj`
- `TravelComposeApp/Core/RouteDiagram.swift`
- `TravelComposeApp/Features/Home/HomeView.swift`
- `TravelComposeApp/Features/Commute/RouteDetailsView.swift`
- `TravelComposeApp/Info.plist`
- `TravelComposeApp/App/AppRoute.swift`
- `TravelComposeApp/App/Navigation.swift`
- `TravelComposeApp/Features/Commute/FindCommuteRoutesView.swift`
- `TravelComposeApp/Features/Money/ReceiptView.swift`
- `TravelComposeApp/Features/Money/WalletView.swift`
- `TravelComposeApp/Features/Profile/ProfileViews.swift`
- `TravelComposeApp/Services/APIClient.swift`
- `TravelComposeApp/Services/Telemetry.swift`
- `backend/src/auth.js`
- `backend/src/server.js`
- `backend/src/repository.js`
- `backend/test/auth.test.js`
- `backend/test/repository.test.js`

## Commands run
- `git status --short --branch`
- `git log -1 --oneline`
- `git pull --ff-only origin main`
- `rg` checks for Info.plist, privacy, account deletion, SOS, telemetry, and project wiring.
- `node --check backend/src/server.js`
- `npm test` from `backend` (passes, but reports 0 tests)
- `plutil -lint TravelComposeApp/Info.plist TravelComposeApp/PrivacyInfo.xcprivacy TravelComposeApp/TravelComposeApp.entitlements`
- `xcodebuild -project TravelComposeApp.xcodeproj -scheme TravelComposeApp -destination 'generic/platform=iOS Simulator' build` (blocked locally because `xcode-select` points at Command Line Tools instead of full Xcode)
- `for f in backend/src/*.js backend/test/*.js; do node --check "$f" || exit 1; done`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project TravelComposeApp.xcodeproj -scheme TravelComposeApp -destination 'generic/platform=iOS Simulator' build` (passes)
- `git diff --check` (passes)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project TravelComposeApp.xcodeproj -scheme TravelComposeApp -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test` (passes, 47 tests)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project TravelComposeApp.xcodeproj -scheme TravelComposeApp -destination 'platform=iOS,id=00008140-001805CE0E40801C' -configuration Debug -derivedDataPath /tmp/voygo-device-build build` (passes)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app --device 00008140-001805CE0E40801C /tmp/voygo-device-build/Build/Products/Debug-iphoneos/TravelComposeApp.app` (passes)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device process launch --device 00008140-001805CE0E40801C --terminate-existing --json-output /tmp/voygo-launch.json com.voygo.travelcomposeapp` (passes, latest PID 15925)
- `node --check src/server.js && node --test` from `backend` (passes, 9 tests)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project TravelComposeApp.xcodeproj -scheme TravelComposeApp -destination 'generic/platform=iOS Simulator' build` (passes)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install BF3760C6-2FCC-4FB9-93A2-5B0E7D685124 .../TravelComposeApp.app`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch BF3760C6-2FCC-4FB9-93A2-5B0E7D685124 com.voygo.travelcomposeapp`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl openurl BF3760C6-2FCC-4FB9-93A2-5B0E7D685124 'voygo://routes/rr-dev-1'`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project TravelComposeApp.xcodeproj -scheme TravelComposeApp -destination 'id=00008140-001805CE0E40801C' -derivedDataPath /tmp/voygo-phone-ui-build build` (passes)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app --device A7CA22FB-811C-57E3-BAE3-8BC0DA897E44 /tmp/voygo-phone-ui-build/Build/Products/Debug-iphoneos/TravelComposeApp.app` (passes)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device process launch --device A7CA22FB-811C-57E3-BAE3-8BC0DA897E44 com.voygo.travelcomposeapp` (passes)

## Current state
- Remaining local untracked files before this work: `.playwright-mcp/`, `form-filled.png`, `TravelComposeApp/Features/System/NotificationsView 2.swift`.
- Current fixed flow: Home `See all` selects Search tab, and `voygo://routes/rr-dev-1` opens Search tab route-detail stack. The simulator showed `Route not found` because that specific demo route is not present after the live refresh, but the navigation destination is now correct.
- MapKit route preview is now local/client-calculated. Backend persistence for `distanceMeters`, `durationSeconds`, and route provider is still not implemented.
- Find Routes now requires both From and To before searching. If a route has fewer than two real coordinates, the UI shows `Map unavailable` instead of KL.
- Important remaining blockers:
  - Backend test suite now contains a small auth security regression suite, but payments/KYC/SOS still need route-level tests.
  - Production KYC uploads intentionally fail with `kyc_storage_unavailable` until real object storage is implemented.
  - Duplicate untracked `TravelComposeApp/Features/System/NotificationsView 2.swift` should be reviewed/deleted by the owner before release.

## Next steps
- If distance/ETA must be consistent across every device and receipt forever, add backend columns for cached MapKit route metadata and populate them when a driver creates/edits a route.
- Add backend route tests for preferences, telemetry opt-out, KYC admin decisions, payments, and `/safety/sos` dispatch reporting.
- Implement durable encrypted KYC object storage before enabling KYC uploads in production.
- Configure production `SAFETY_TWILIO_NUMBER` and/or `SAFETY_PAGERDUTY_KEY` if Voygo Safety should be truly live during pilot.

## Caveats
- Real production APNs, S3, Billplz, Stripe, PagerDuty/Twilio depend on external credentials and cannot be fully verified from local code alone.
