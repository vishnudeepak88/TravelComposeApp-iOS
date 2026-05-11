# Codex Handoff

Date: 2026-05-11
Current goal: Fix Apple R&D audit blockers for Voygo iOS + backend.
Branch: main

## Completed
- Replaced the abstract route visuals on route detail, receipt, and live trip surfaces with `VRouteMapPreview` using Apple Maps tiles.
- Upgraded `VRouteMapPreview` to calculate MapKit driving legs between every pickup/drop point, draw each road segment, sum road distance + ETA, and show a badge like `23.4 km · 38 min`.
- Added graceful MapKit fallback behavior: failed legs render as dashed direct estimates and the badge switches to `Partial` or `Direct` instead of pretending the route is fully road-resolved. Partial/direct fallback shows distance only; full Apple routing shows distance + ETA.
- Added an `Open` map action to `VRouteMapPreview`; users can choose Apple Maps or Google Maps. Google Maps opens the native app when installed and falls back to Google Maps web with waypoints.
- Built, installed, and launched the updated iOS app on `Vishnu’s iPhone` (`com.voygo.travelcomposeapp`) with process launch outcome `success`.
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
- `TravelComposeApp/Features/Commute/RouteDetailsView.swift`
- `TravelComposeApp/Info.plist`
- `TravelComposeApp/App/AppRoute.swift`
- `TravelComposeApp/App/Navigation.swift`
- `TravelComposeApp/Features/Money/ReceiptView.swift`
- `TravelComposeApp/Features/Money/WalletView.swift`
- `TravelComposeApp/Features/Profile/ProfileViews.swift`
- `TravelComposeApp/Services/APIClient.swift`
- `TravelComposeApp/Services/Telemetry.swift`
- `backend/src/auth.js`
- `backend/src/server.js`
- `backend/test/auth.test.js`

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
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project TravelComposeApp.xcodeproj -scheme TravelComposeApp -destination 'platform=iOS,id=00008140-001805CE0E40801C' -configuration Debug -derivedDataPath /tmp/voygo-device-build build` (passes)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device install app --device 00008140-001805CE0E40801C /tmp/voygo-device-build/Build/Products/Debug-iphoneos/TravelComposeApp.app` (passes)
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun devicectl device process launch --device 00008140-001805CE0E40801C --terminate-existing --json-output /tmp/voygo-launch.json com.voygo.travelcomposeapp` (passes, latest PID 15851)

## Current state
- Remaining local untracked files before this work: `.playwright-mcp/`, `form-filled.png`, `TravelComposeApp/Features/System/NotificationsView 2.swift`.
- MapKit route preview is now local/client-calculated. Backend persistence for `distanceMeters`, `durationSeconds`, and route provider is still not implemented.
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
