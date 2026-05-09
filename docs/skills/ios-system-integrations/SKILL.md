---
name: ios-system-integrations
description: Integrate iOS system surfaces from SwiftUI — PHPicker (photos), MFMessageComposeViewController (SMS), UIActivityViewController (share), interactivePopGestureRecognizer (swipe-back), tel:// calls, custom URL deep links. Each pattern is a small UIViewControllerRepresentable + Swift 6 strict-concurrency-safe.
---

## When to use

- Any time a SwiftUI screen needs a system surface that doesn't have a
  first-class SwiftUI wrapper yet:
  - Photo picker (PHPickerViewController)
  - SMS composer (MFMessageComposeViewController)
  - Share sheet with mixed text+URL items (UIActivityViewController)
  - Phone call from a button (`tel://` URL scheme)
  - Edge swipe-back on a screen with a hidden system nav bar
  - Custom URL scheme deep link (`yourapp://...`)

## Recipe

### Photo picker (PHPicker)

```swift
import SwiftUI
import PhotosUI
import UIKit

struct PhotoPicker: UIViewControllerRepresentable {
    /// `@Sendable` because `loadObject(...)` completion runs on a
    /// background queue. Without this annotation, Swift 6 strict
    /// concurrency rejects the closure capture.
    var onPicked: @Sendable (Data?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: @Sendable (Data?) -> Void
        init(onPicked: @escaping @Sendable (Data?) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                onPicked(nil); return
            }
            let cb = onPicked
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let data = (object as? UIImage).flatMap { $0.jpegData(compressionQuality: 0.85) }
                Task { @MainActor in cb(data) }
            }
        }
    }
}
```

**Required Info.plist key** (auto-generated INFOPLIST_KEY in pbxproj):

```
INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "We need access to your library to upload identity documents.";
```

Usage:

```swift
.sheet(isPresented: $showPicker) {
    PhotoPicker { data in
        guard let data else { return }
        Task { await uploadDocument(data) }
    }
}
```

### SMS composer

```swift
import SwiftUI
import MessageUI

struct MessageComposerView: UIViewControllerRepresentable {
    let body: String
    var recipients: [String]? = nil

    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.body = body
        if let recipients { vc.recipients = recipients }
        vc.messageComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
        }
    }
}
```

Always check `MessageComposerView.canSendText` before presenting —
iPad without paired iPhone returns false, and presenting an empty
modal looks broken.

### Share sheet (mixed text + URL)

```swift
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// Usage:
.sheet(isPresented: $showShare) {
    ActivityShareSheet(items: [
        "Check out this ride: \(routeName)",
        URL(string: "https://yourapp.com/share/\(token)")!
    ])
    .presentationDetents([.medium])
}
```

For pure-Transferable single items, prefer SwiftUI's `ShareLink`.
ActivityViewController is for the mixed-text+URL case where
`ShareLink` doesn't fit cleanly.

### Phone call (`tel://`)

```swift
Button {
    if let phone = route.driverPhone, !phone.isEmpty,
       let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
        UIApplication.shared.open(url)
    }
} label: { Image(systemName: "phone.fill") }
.disabled(route.driverPhone?.isEmpty != false)
.accessibilityLabel(route.driverPhone?.isEmpty != false
    ? "Driver phone unavailable"
    : "Call driver")
```

Disable + relabel when the data isn't there. Don't open `tel://`
unless the phone is non-empty — empty `tel://` opens the dialer
with a blank field, which feels like a bug.

### Swipe-back gesture restoration

When a screen sets `.navigationBarHidden(true)` to use custom nav
chrome, the system disables `interactivePopGestureRecognizer`.
Restore it manually:

```swift
import SwiftUI
import UIKit

struct EnableSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SwipeBackHostController {
        SwipeBackHostController()
    }
    func updateUIViewController(_ vc: SwipeBackHostController, context: Context) {}
}

final class SwipeBackHostController: UIViewController, UIGestureRecognizerDelegate {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if let nav = findNavController(from: parent) {
            nav.interactivePopGestureRecognizer?.delegate = self
            nav.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
    private func findNavController(from vc: UIViewController?) -> UINavigationController? {
        var c: UIViewController? = vc
        while let cur = c {
            if let nav = cur as? UINavigationController { return nav }
            c = cur.parent
        }
        return nil
    }
    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let nav = findNavController(from: parent) else { return false }
        return nav.viewControllers.count > 1   // only when there's something to pop
    }
}

extension View {
    func enableSwipeBack() -> some View {
        background(EnableSwipeBack().frame(width: 0, height: 0))
    }
}
```

Apply once per `NavigationStack` root:

```swift
NavigationStack(path: $path) { … }
    .navigationBarHidden(true)
    .enableSwipeBack()
```

### Custom URL scheme deep links

Register the scheme in `INFOPLIST_KEY_*` (or via Info.plist):

```
INFOPLIST_KEY_CFBundleURLTypes = ... (legacy)
```

For modern Xcode, just add to the auto-generated Info.plist via
build settings, or use:

```yaml
// Info.plist (if you need a real one)
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.yourapp.deeplink</string>
    <key>CFBundleURLSchemes</key>
    <array><string>yourapp</string></array>
  </dict>
</array>
```

Handle in App:

```swift
@main
struct YourApp: App {
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .onOpenURL { url in
                    // Parse scheme + host + components, route accordingly
                    store.handleDeepLink(url)
                }
        }
    }
}
```

## Pitfalls

- **`@Sendable` on PHPicker callbacks.** Without it, Swift 6 strict
  concurrency complains because the completion is called on a
  background queue. Either `@Sendable` or `nonisolated(unsafe)` on
  the captured property.
- **Sheet detents.** `presentationDetents([.medium])` works for
  most system sheets; ActivityViewController traditionally goes
  full-height — it's UIKit-driven and will ignore SwiftUI detents
  inside an Action Extension presentation in some iOS versions.
- **`MFMessageComposeViewController.canSendText` is false on
  iPad.** Always check before presenting; provide an honest
  fallback sheet ("This device can't send SMS").
- **`EnableSwipeBack` walks the responder chain.** If the
  `NavigationStack` is wrapped weirdly (e.g. inside a
  `TabView` that's inside a sheet), the walk may not find the
  underlying `UINavigationController`. Fall back to system nav
  in those cases.
- **`tel://` opens immediately without confirmation.** Users
  expect that on phone-icon taps, but if you wire it to anything
  ambiguous, add a confirmation alert.

## Adjacent skills

- `ios-swiftui-bootstrap` — the project the integrations slot into.
- `ios-design-system-port` — the buttons that trigger these sheets.

## Reference implementation

Voygo at commit `599dd5b`:
- `TravelComposeApp/Core/PhotoPicker.swift`
- `TravelComposeApp/Core/SharePresenters.swift` (Share + SMS)
- `TravelComposeApp/Core/SwipeBack.swift`
- `TravelComposeApp/App/TravelComposeApp.swift` (`onOpenURL` for
  Billplz `voygo://` return).
