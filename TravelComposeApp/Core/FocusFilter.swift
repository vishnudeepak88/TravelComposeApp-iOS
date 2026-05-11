import Foundation
#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Voygo Focus state (lightweight, AppIntent-ready)
//
// This file holds the SHARED STATE that a future SetFocusFilterIntent
// will write to. Wiring the actual `SetFocusFilterIntent` conformance
// is gated behind a follow-up because the iOS 26 / Swift 6
// `InstanceDisplayRepresentable` requirements need a build-time
// validated parameter summary that didn't compile in this branch
// without further AppIntents schema work.
//
// What's already in place + safe to ship:
//   1. `VoygoFocusState.current` — reads UserDefaults keys that the
//      future FocusFilter will set
//   2. `Notification.Name.voygoFocusStateChanged` — observers can
//      already subscribe and react
//   3. UI sites that should respect the focus (Inbox badge, chat
//      fan-out) can opt-in NOW; they'll do nothing until the
//      FocusFilter ships
//
// What's deferred:
//   - The actual `SetFocusFilterIntent` struct (Apple R&D follow-up)
//   - The Settings → Focus → App Filters → Voygo configuration UI
//     (requires the intent to be registered)

extension Notification.Name {
    /// Posted whenever the active Voygo Focus configuration changes.
    /// Inbox badge + push-notification routing observe this and
    /// re-evaluate which categories to surface.
    static let voygoFocusStateChanged = Notification.Name("voygo.focus.stateChanged")
}

/// Snapshot of the user's current Voygo Focus configuration. Reads
/// from UserDefaults so it survives process restarts and is shared
/// with any future widget / Live Activity / FocusFilter target.
struct VoygoFocusState: Equatable, Sendable {
    var active: Bool = false
    var mutePromotional: Bool = false
    var hideInboxBadge: Bool = false

    /// Snapshot the current state from UserDefaults. Returns a
    /// neutral default when no FocusFilter has ever been configured.
    static var current: VoygoFocusState {
        let d = UserDefaults.standard
        return VoygoFocusState(
            active: d.bool(forKey: keyActive),
            mutePromotional: d.bool(forKey: keyMutePromotional),
            hideInboxBadge: d.bool(forKey: keyHideInboxBadge)
        )
    }

    /// Persist this state. Used by the (deferred) FocusFilter.perform
    /// hook + by an internal "Test focus mode" debug toggle.
    func save() {
        let d = UserDefaults.standard
        d.set(active, forKey: VoygoFocusState.keyActive)
        d.set(mutePromotional, forKey: VoygoFocusState.keyMutePromotional)
        d.set(hideInboxBadge, forKey: VoygoFocusState.keyHideInboxBadge)
        NotificationCenter.default.post(name: .voygoFocusStateChanged, object: nil)
    }

    static let keyActive            = "voygo.focus.active"
    static let keyMutePromotional   = "voygo.focus.mutePromotional"
    static let keyHideInboxBadge    = "voygo.focus.hideInboxBadge"
}
