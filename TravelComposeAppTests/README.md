# TravelComposeAppTests

Swift Testing tests for the pure model + policy layer.

## What's here

- **`PhoneNormalizationTests.swift`** — `Voygo.normalizePhoneNumber` covering E.164 passthrough, all four common Malaysian paste forms (`+60…`, `60…`, `0…`, bare local), the Sabah/Sarawak 9-digit regression, autocorrect trailing-space artifacts, and empty/garbage input.
- **`SubscriptionPricingTests.swift`** — `SubscriptionPricing.discountedPricePerSeat`, `totalForTier`, `savingsVsDaily`, and `workingDaysBetween` (calendar-edge incl. weekend-only and inverted ranges).
- **`CancellationPolicyTests.swift`** — every cell of the playbook §5.3 cancellation matrix (driver late-cancel × 30-day count, no-show, rider mid-month, rider no-show, force majeure).
- **`DaysOfWeekFlagsTests.swift`** — `weekdays`/`allDays` presets, `enabled(for:)` mapping, `shortLabel` formatting.

## Wiring (one-time, manual)

The pbxproj surgery to add a unit-test target is involved enough that
doing it by hand from a worktree risks corrupting the project file.
Wire the target via Xcode UI instead — it's a 30-second job:

1. Open `TravelComposeApp.xcodeproj`.
2. **File → New → Target…** → **iOS → Unit Testing Bundle**.
3. Name: `TravelComposeAppTests`. Target to test: `TravelComposeApp`.
   Use "Swift Testing" as the testing system.
4. Xcode creates an empty `TravelComposeAppTests/` group + a default
   `TravelComposeAppTests.swift`. Delete that default file.
5. Right-click the `TravelComposeAppTests` group → **Add Files to
   "TravelComposeApp"…** → select all four `*.swift` files in this
   directory → ensure "Add to targets: TravelComposeAppTests" is
   checked (and NOT TravelComposeApp).
6. Set the test target's **iOS Deployment Target** to **18.0** so it
   matches the CI override.

After that, **⌘U** in Xcode runs the tests; CI can be extended with:

```yaml
- name: Test
  run: |
    set -o pipefail
    xcodebuild \
      -project TravelComposeApp.xcodeproj \
      -scheme TravelComposeApp \
      -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
      -configuration Debug \
      CODE_SIGNING_ALLOWED=NO \
      IPHONEOS_DEPLOYMENT_TARGET=18.0 \
      test
```

## Conventions

- Swift Testing only — no XCTest. `@Suite` for groups, `@Test` for
  cases, `#expect` for assertions.
- `@testable import TravelComposeApp` to reach internal types.
- Pure logic only — no view tests, no network, no `@MainActor` setup.
  AppStore and ViewModels remain untested at this layer.

## What to add next

In rough priority:
1. `CommuteMatchingEngine.matchRoutes` — the scoring policy is
   currently a "trust me" black box.
2. `formatPlacemark` (LocationService) — snapshot a few representative
   `MKPlacemark` shapes.
3. `AppError.from(_:)` — the typed-error fold added in commit 34aaea9.
