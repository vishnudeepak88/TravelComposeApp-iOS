---
name: ios-real-device-deploy
description: Build, sign, install, and launch an iOS app on a real iPhone from the command line via xcodebuild + devicectl, including xattr/codesign troubleshooting. Use when the user says "deploy this to my phone" and you need a no-Xcode-UI path.
---

## When to use

- User asks to deploy/install on their physical iPhone.
- Xcode UI deploys are slow or unreliable; you want a scripted path.
- CI / scripted release for internal builds via TestFlight is overkill.

## Prerequisites

- iPhone is **plugged in** (or paired over Wi-Fi) and **unlocked**.
- Xcode is signed in to a developer account that owns the bundle id
  (or a free personal team is fine for local install).
- Project's `DEVELOPMENT_TEAM` is set in pbxproj (otherwise the
  signing identity selection fails silently).

## Recipe

### 1 · Find the device identifier

```bash
xcrun devicectl list devices
```

Output looks like:

```
Vishnu's iPhone   Vishnus-iPhone.coredevice.local   A7CA22FB-811C-57E3-BAE3-8BC0DA897E44   connected   iPhone 16 Pro
```

Capture the UUID (`A7CA22FB-…`). Any subsequent `devicectl` call
needs it.

### 2 · Build with the device destination

```bash
xcodebuild -project YourApp.xcodeproj \
  -scheme YourApp \
  -destination 'platform=iOS,id=A7CA22FB-811C-57E3-BAE3-8BC0DA897E44' \
  -configuration Debug \
  -derivedDataPath build \
  build
```

`-derivedDataPath build` puts the artifact at a stable, repo-local
path — the next step needs to find the `.app`.

### 3 · Install + launch

```bash
APP=build/Build/Products/Debug-iphoneos/YourApp.app

xcrun devicectl device install app \
  --device <UUID> \
  "$APP"

xcrun devicectl device process launch \
  --device <UUID> \
  com.your.bundle.id
```

If you're unsure of the bundle id, grep:

```bash
grep -m1 "PRODUCT_BUNDLE_IDENTIFIER" YourApp.xcodeproj/project.pbxproj
```

### 4 · Codesign troubleshooting — the xattr trap

The most common build failure is:

```
TravelComposeApp.app: resource fork, Finder information, or similar
detritus not allowed
Command CodeSign failed
```

This is `com.apple.provenance` (and similar) extended attributes
attached to files in the `.app` bundle by macOS Sequoia+. The fix
runs once before each codesign:

```bash
xattr -cr build && \
  xcodebuild ... build
```

`xattr -cr` strips xattrs recursively. Re-run the build immediately
afterward. If it fails again on a fresh xcodebuild invocation, it
means xcodebuild *re-applied* the xattrs during a copy phase — you
can chain it via a build-phase script:

```bash
# In Xcode: Build Phases → New Run Script Phase
# (place AFTER "Copy Bundle Resources", BEFORE "Sign")
xattr -cr "$CODESIGNING_FOLDER_PATH"
```

…but for a one-shot deploy, `xattr -cr build` between failed runs
is enough.

### 5 · One-line redeploy

After the first successful run, redeploy with:

```bash
xattr -cr build && \
  xcodebuild -project YourApp.xcodeproj -scheme YourApp \
    -destination 'platform=iOS,id=<UUID>' \
    -configuration Debug -derivedDataPath build build && \
  xcrun devicectl device install app --device <UUID> \
    build/Build/Products/Debug-iphoneos/YourApp.app && \
  xcrun devicectl device process launch --device <UUID> \
    com.your.bundle.id
```

Save it as a shell function in `~/.zshrc`:

```bash
yourapp-deploy() {
  local UUID=A7CA22FB-811C-57E3-BAE3-8BC0DA897E44
  xattr -cr build && \
    xcodebuild -project YourApp.xcodeproj -scheme YourApp \
      -destination "platform=iOS,id=$UUID" \
      -configuration Debug -derivedDataPath build build && \
    xcrun devicectl device install app --device "$UUID" \
      build/Build/Products/Debug-iphoneos/YourApp.app && \
    xcrun devicectl device process launch --device "$UUID" \
      com.your.bundle.id
}
```

### 6 · Wireless deploy

Once the device is paired over Wi-Fi (Xcode → Window → Devices and
Simulators → "Connect via network" checkbox), the same `devicectl`
command works without USB. The device must be on the same network +
unlocked.

## Pitfalls

- **`devicectl` warns about a missing `provider`.** That's
  `defaults` provider for some advanced features; it's harmless for
  install + launch.
- **"App not installed because the device is locked."** The device
  needs to be unlocked when `install` runs. Unlock and re-run.
- **"The app's signing certificate has expired."** Free Apple Dev
  certs expire after 7 days. Refresh in Xcode → Settings →
  Accounts → Manage Certificates. CLI build then picks up the new
  cert automatically.
- **Different from `xcrun simctl`.** `simctl` is for simulators
  (`booted` keyword); `devicectl` is for physical devices.
- **Don't `git add build/`.** It's huge and machine-specific. Add
  to `.gitignore`.

## Adjacent skills

- `xcode-ci-setup` — same xcodebuild flags but for GitHub Actions.
- `ios-swiftui-bootstrap` — the project structure this deploys.

## Reference implementation

Voygo at commit `599dd5b` deploys to iPhone 16 Pro via this exact
recipe. Re-deploy command captured in `docs/SESSION_NOTES.md`.
