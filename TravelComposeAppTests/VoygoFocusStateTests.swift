import Foundation
import Testing
@testable import TravelComposeApp

// MARK: - VoygoFocusState tests
//
// The Focus state scaffold (in `Core/FocusFilter.swift`) persists
// user-tunable filter settings to UserDefaults so a future
// SetFocusFilterIntent can pick them up and the rest of the app can
// react via the `voygoFocusStateChanged` notification.
//
// These tests pin the persistence behaviour: write -> read round-trip,
// default values when unset, and notification fan-out on save.

@Suite("VoygoFocusState", .serialized)
struct VoygoFocusStateTests {

    private static let keyActive = "voygo.focus.active"
    private static let keyMute = "voygo.focus.mutePromotional"
    private static let keyBadge = "voygo.focus.hideInboxBadge"

    /// Clean the three UserDefaults keys before each test so cases
    /// don't bleed state into each other. The suite is serialized
    /// because these tests share UserDefaults + NotificationCenter.
    private func resetDefaults() {
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.keyActive)
        d.removeObject(forKey: Self.keyMute)
        d.removeObject(forKey: Self.keyBadge)
    }

    @Test("Default state is all-off when no Focus has been configured")
    func defaultStateAllOff() {
        resetDefaults()
        let state = VoygoFocusState.current
        #expect(state.active == false)
        #expect(state.mutePromotional == false)
        #expect(state.hideInboxBadge == false)
    }

    @Test("save() then read round-trips the values")
    func saveRoundTrips() {
        resetDefaults()
        let stored = VoygoFocusState(
            active: true,
            mutePromotional: true,
            hideInboxBadge: false
        )
        stored.save()
        let read = VoygoFocusState.current
        #expect(read.active == true)
        #expect(read.mutePromotional == true)
        #expect(read.hideInboxBadge == false)
    }

    @Test("save() fires voygoFocusStateChanged notification")
    func saveFiresNotification() async {
        resetDefaults()
        await confirmation(expectedCount: 1) { fired in
            let token = NotificationCenter.default.addObserver(
                forName: .voygoFocusStateChanged,
                object: nil,
                queue: .main
            ) { _ in
                fired()
            }
            defer { NotificationCenter.default.removeObserver(token) }

            VoygoFocusState(active: true, mutePromotional: true, hideInboxBadge: false).save()

            // Yield so the main-queue observer has a chance to fire.
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @Test("Equatable conformance compares field-by-field")
    func equatable() {
        let a = VoygoFocusState(active: true, mutePromotional: true, hideInboxBadge: false)
        let b = VoygoFocusState(active: true, mutePromotional: true, hideInboxBadge: false)
        let c = VoygoFocusState(active: true, mutePromotional: false, hideInboxBadge: false)
        #expect(a == b)
        #expect(a != c)
    }
}
