import SwiftUI
import UIKit

// MARK: - Safe URL helpers
//
// The audit flagged force-unwrapped URL(string:)! in several places
// (`AppConfiguration.swift:18`, `AuthViews.swift:114,120`,
// `ProfileViews.swift:1344`, `APIClient.swift:166`). Force-unwraps on
// URL construction are the #1 source of crash reports — and the URL
// inputs were all compile-time constants, so the unwraps were both
// unsafe AND avoidable.
//
// `safe(_:)` returns nil on parse failure; `unwrap(_:)` traps in
// DEBUG and returns a graceful fallback in release. Callers should
// use `safe` whenever the value crosses an `if let` and `unwrap`
// only for genuinely-static URLs (the API base, brand links).

extension URL {
    /// Same as `URL(string:)` but explicit about returning Optional.
    /// Use this for any URL that comes from data: server payloads,
    /// user input, decoded fields. Never `!`.
    static func safe(_ string: String) -> URL? {
        URL(string: string)
    }

    /// Static URL fallback. Use ONLY for compile-time constants where
    /// failure indicates a typo in the source. DEBUG traps so we
    /// catch typos in development; release-mode returns a graceful
    /// `about:blank` so a typo doesn't crash a user's session.
    static func staticURL(_ string: String) -> URL {
        if let url = URL(string: string) { return url }
        #if DEBUG
        // Trap loudly in DEBUG — this is a programmer error.
        fatalError("URL.staticURL: \(string) is not a valid URL")
        #else
        // Release-mode fallback: an opaque `about:blank` URL. Any
        // open() call against this will simply fail silently, which
        // is preferable to a startup crash.
        return URL(string: "about:blank")!
        #endif
    }
}

// MARK: - Safe external-link opener
//
// `mailto:` and `tel:` URLs silently fail when no handler app is
// installed — Mail and Phone are no longer guaranteed on every iOS
// device (Mail can be removed; iPads don't have Phone at all). The
// helper checks `canOpenURL` first and runs a fallback if it can't,
// so the user never taps a button that does nothing.

enum SafeOpen {
    /// Tries to open `url`. Returns true if the system claims it can
    /// open it. Falls through to `fallback` (typically a Toast / sheet
    /// with the email or phone copyable) when it can't.
    @MainActor
    @discardableResult
    static func url(_ url: URL, fallback: (() -> Void)? = nil) -> Bool {
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return true
        }
        fallback?()
        return false
    }

    /// Convenience: try a mailto, and on failure copy the address to
    /// the pasteboard + show a haptic so the user knows their tap was
    /// acknowledged. They can paste into their preferred mail client.
    @MainActor
    static func mailto(
        _ address: String,
        subject: String? = nil,
        onCopied: (() -> Void)? = nil
    ) {
        let encodedSubject = subject?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        if let encodedSubject {
            components.queryItems = [URLQueryItem(name: "subject", value: encodedSubject)]
        }
        let mailtoURL = components.url ?? URL(string: "mailto:\(address)") ?? URL.staticURL("about:blank")
        let opened = url(mailtoURL)
        if !opened {
            // Mail handler missing. Put the address on the clipboard
            // so the user can paste it into Gmail / Outlook / etc.,
            // and signal success via haptic + caller callback.
            UIPasteboard.general.string = address
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCopied?()
        }
    }

    /// Convenience: dial a tel:// number. Falls back to copying the
    /// number to the pasteboard on iPads or numbers-locked devices.
    @MainActor
    static func tel(_ phone: String, onCopied: (() -> Void)? = nil) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return }
        guard let telURL = URL(string: "tel://\(digits)") else { return }
        let opened = url(telURL)
        if !opened {
            UIPasteboard.general.string = phone
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCopied?()
        }
    }
}

// MARK: - Reduce-Motion-aware animation
//
// SwiftUI doesn't auto-skip explicit `.animation(.spring(...))` calls
// when Settings → Accessibility → Reduce Motion is on. We have ~50
// `withAnimation(.spring(...))` callsites; rather than edit each one,
// this small helper returns `nil` (= instant transition) when reduce
// motion is enabled, otherwise the requested animation. Use as
// `withAnimation(reduceMotionAware(.spring(...))) { ... }` or via the
// `.voygoAnimation()` view modifier below.

@MainActor
func reduceMotionAware(_ animation: Animation) -> Animation? {
    UIAccessibility.isReduceMotionEnabled ? nil : animation
}

extension View {
    /// Re-applies `.animation(...)` only when Reduce Motion is OFF.
    /// Pairs with `value:` exactly like the native modifier, so the
    /// migration is one-line per call site.
    func voygoAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        self.animation(UIAccessibility.isReduceMotionEnabled ? nil : animation, value: value)
    }
}
