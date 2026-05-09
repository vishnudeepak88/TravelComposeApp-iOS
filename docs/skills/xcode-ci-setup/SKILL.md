---
name: xcode-ci-setup
description: Wire GitHub Actions CI for an Xcode iOS project on macos-latest, including SDK-version mismatch handling, codesign workarounds, and IPHONEOS_DEPLOYMENT_TARGET overrides. Use when a project ships its first .github/workflows/swift.yml or migrates from Swift-Package CI to Xcode-project CI.
---

## When to use

- Repo has an `.xcodeproj` (not a Swift Package), so the default
  `swift build` / `swift test` workflow GitHub auto-suggests will
  fail with "root manifest not found".
- Project targets a newer iOS SDK than the runner's installed Xcode
  exposes (e.g. you built locally against iOS 26 but `macos-latest`
  ships Xcode 16.4 with iOS 18.5 SDK).
- You want CI to gate PRs without having to push to TestFlight.

## Prerequisites

- Repo on GitHub.
- An Xcode project + scheme that builds locally.
- The scheme is **shared** in Xcode (Product → Scheme → Manage
  Schemes → tick "Shared"). Without that, GitHub clones the repo
  and `xcodebuild` can't find the scheme.

## Recipe

### 1 · Workflow file

`.github/workflows/swift.yml`:

```yaml
name: iOS Build

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  build:
    runs-on: macos-15  # current = Xcode 16.x with iOS 18.5 SDK

    steps:
      - uses: actions/checkout@v4

      - name: Show Xcode version
        run: xcodebuild -version

      - name: Build
        run: |
          set -o pipefail
          xcodebuild \
            -project YourApp.xcodeproj \
            -scheme YourApp \
            -destination 'generic/platform=iOS Simulator' \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO \
            IPHONEOS_DEPLOYMENT_TARGET=18.0 \
            build
```

Three load-bearing flags:

- **`CODE_SIGNING_ALLOWED=NO`** — runner doesn't have your signing
  identity. Simulator builds don't need codesigning.
- **`IPHONEOS_DEPLOYMENT_TARGET=18.0`** — overrides the project's
  iOS 26 target *just for CI*. The runner's max SDK is whatever
  Xcode is installed (16.x = 18.5). Local builds keep iOS 26 from
  the pbxproj.
- **`generic/platform=iOS Simulator`** — no specific simulator
  needed for build-only; if you add tests, switch to a concrete
  simulator (`platform=iOS Simulator,name=iPhone 15,OS=latest`).

### 2 · Common build failures + fixes

#### `swift build` errors (`root manifest not found`)

You inherited GitHub's auto-suggested `swift.yml` for SPM. Replace
it with the xcodebuild version above.

#### `MKLocalSearch.Response` non-Sendable in CI but not local

iOS 26 SDK marks the type Sendable; older SDKs don't. Fix on the
Swift side:

```swift
@preconcurrency import MapKit
```

The annotation says "this module's Sendable annotations are
incomplete; treat strict-concurrency violations as warnings." Same
fix applies to any system framework that's behind on Sendable
annotations.

#### `IPHONEOS_DEPLOYMENT_TARGET = 26.0 ... supported range is 12.0 to 18.5.99`

Workflow override above (`IPHONEOS_DEPLOYMENT_TARGET=18.0`).

#### `resource fork, Finder information, or similar detritus not allowed`

The xattr trap. Add `xattr -cr` before xcodebuild:

```yaml
- name: Build
  run: |
    set -o pipefail
    xattr -cr .
    xcodebuild …
```

(Local re-deploy uses `xattr -cr build`; on a fresh runner the
checkout sometimes carries provenance xattrs from the Git plumbing.)

### 3 · Add tests once a target exists

The scaffolding above is build-only. Once you have a Swift Testing
target wired:

```yaml
- name: Test
  run: |
    set -o pipefail
    xcodebuild \
      -project YourApp.xcodeproj \
      -scheme YourApp \
      -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
      -configuration Debug \
      CODE_SIGNING_ALLOWED=NO \
      IPHONEOS_DEPLOYMENT_TARGET=18.0 \
      -enableCodeCoverage YES \
      test
```

Concrete simulator (`name=iPhone 15`) is required for `test`;
`generic/platform=iOS Simulator` only works for `build`.

### 4 · Faster CI with caches

Two caches help most:

```yaml
- uses: actions/cache@v4
  with:
    path: ~/Library/Developer/Xcode/DerivedData
    key: ${{ runner.os }}-derived-data-${{ hashFiles('**/project.pbxproj') }}

- uses: actions/cache@v4
  with:
    path: ~/Library/Caches/CocoaPods   # only if you use CocoaPods
    key: ${{ runner.os }}-cocoapods-${{ hashFiles('**/Podfile.lock') }}
```

Don't cache `~/Library/Developer/Xcode/DerivedData/*/SourcePackages`
— SPM checkouts are fast and stale caches break weirdly.

### 5 · Pinning the Xcode version

`macos-15` defaults to whatever Xcode the runner has installed. To
pin (e.g. for reproducibility):

```yaml
- run: sudo xcode-select -s /Applications/Xcode_16.4.app
```

Available paths are documented in
[actions/runner-images](https://github.com/actions/runner-images).
Don't pin to a specific minor unless you need to — you'll fall
behind on security updates.

## Pitfalls

- **CI runner SDK lag is normal.** Apple ships an iOS SDK in
  June; GitHub's `macos-latest` runner doesn't pick it up until
  August-October. Plan deployment-target overrides accordingly.
- **`CODE_SIGNING_ALLOWED=NO` is **only** for simulator builds.**
  Real-device builds need a signing identity, which means
  configuring `secrets.APPLE_*` and downloading a provisioning
  profile in the workflow. That's its own skill.
- **Don't `xcodebuild test` on `generic/platform=iOS Simulator`.**
  `test` requires a concrete simulator name + OS.
- **Build with `-configuration Debug` matches local dev.** If you
  want to gate Release-only failures, add a second job for
  `-configuration Release`.

## Adjacent skills

- `ios-real-device-deploy` — same flags, different destination.
- `ios-swiftui-bootstrap` — the project this CI builds.

## Reference implementation

Voygo at commit `599dd5b`:
- `.github/workflows/swift.yml` — the working workflow.
- Commits `4daee81` (initial setup) and `a76ead8` (SDK-mismatch
  fixes) walk the failure modes in real time.
