import Foundation
import Testing
@testable import TravelComposeApp

// MARK: - AppCapabilities flag tests
//
// Three iOS capabilities (Sign in with Apple, Push Notifications,
// Live Activities) are gated behind compile-time flags in
// `AppConfiguration.swift` because the Personal Team account can't
// enable the underlying entitlements. The test pins the *current*
// expected state of those flags so:
//   - Anyone flipping a flag has to also update this test (forces
//     intentional change)
//   - CI catches an accidental flip from a merge conflict
//
// When the team upgrades to a paid Developer Program seat AND the
// matching entitlements get linked, flip each flag to `true` here
// to match the production state.

@Suite("AppCapabilities flags")
struct AppCapabilityFlagsTests {

    @Test("SIWA is gated until paid team")
    func siwaGated() {
        // SIWA requires `com.apple.developer.applesignin` entitlement.
        // Personal Teams can't add it. The UI hides the SIWA button
        // when this is false (`AuthViews.swift` `AppCapabilities.signInWithAppleAvailable`).
        #expect(AppCapabilities.signInWithAppleAvailable == false)
    }

    @Test("Push is gated until paid team")
    func pushGated() {
        // APNs requires `aps-environment` entitlement.
        // `PushRegistration.swift` no-ops when this is false.
        #expect(AppCapabilities.pushNotificationsAvailable == false)
    }

    @Test("Live Activities is gated (needs widget extension target)")
    func liveActivitiesGated() {
        // ActivityKit requires a Widget Extension target — not yet
        // shipped. Flag stays false even after paid-team upgrade.
        #expect(AppCapabilities.liveActivitiesAvailable == false)
    }
}
