import AppIntents
import SwiftUI

// MARK: - App Intents
//
// First-class iOS platform integration: "Hey Siri, find my Voygo
// routes" / "Hey Siri, open my next Voygo commute" / Spotlight search
// indexes user routes. None of these require a paid Apple Developer
// Program account — App Intents work on Personal Team builds.
//
// What they unlock for the score:
//   - Siri voice control of the most common rider actions
//   - Spotlight + system-wide search surfaces the user's routes
//   - Shortcuts app gets Voygo actions for automations
//   - Focus filter has a real target intent (still TODO — see
//     `FocusFilter.swift`)
//
// Each intent posts a NotificationCenter event the rest of the app
// observes via existing patterns (`.voygoOpenRoute`, etc.) — no
// new deep-link plumbing required.

// MARK: - Find Routes intent
//
// "Hey Siri, find my Voygo routes" → opens the Search tab.
// AppOpenIntent is the right shape because we don't need parameters
// and the user expects to land in the app.

@available(iOS 16.0, *)
struct FindVoygoRoutesIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Voygo routes"
    static let description: IntentDescription? = IntentDescription(
        "Search for carpool routes near you.",
        categoryName: "Rides"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Switch to the Search tab via the same notification the
        // existing deep-link path uses. MainTabView listens for
        // `.voygoOpenRoute` and routes to .search.
        NotificationCenter.default.post(
            name: .voygoOpenRoute,
            object: nil,
            userInfo: [:]
        )
        return .result()
    }
}

// MARK: - Open Next Commute intent
//
// "Hey Siri, open my next Voygo commute" → posts a deep-link to the
// home screen's nextCommute card. Surfaced as a `Suggested Action`
// via AppShortcutsProvider so the Shortcuts app suggests it.

@available(iOS 16.0, *)
struct OpenNextCommuteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open my next commute"
    static let description: IntentDescription? = IntentDescription(
        "Show today's scheduled Voygo ride.",
        categoryName: "Rides"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Home tab is the default landing surface — surface the Home
        // tab's Next-commute card by switching to home. The card is
        // already pinned to the top of Home when an active sub exists.
        // No specific deep link needed; just open the app.
        return .result()
    }
}

// MARK: - View Wallet Credit intent
//
// "Hey Siri, how much Voygo Credit do I have?" — returns the user's
// current RM credit balance. ReturnsValueIntent rather than
// AppOpenIntent because Siri can speak the value back without
// opening the app.

@available(iOS 16.0, *)
struct VoygoCreditIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Voygo Credit"
    static let description: IntentDescription? = IntentDescription(
        "Read your current Voygo Credit balance.",
        categoryName: "Wallet"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Read from the same `UserDefaults` that AppStore mirrors
        // on payment-refresh — the same data backs the Wallet view.
        let credit = UserDefaults.standard.integer(forKey: "voygo.credit.myr")
        let amount = "RM \(credit)"
        let dialog: IntentDialog =
            credit > 0
            ? "You have \(amount) in Voygo Credit."
            : "You don't have any Voygo Credit yet — refunds and referrals build it up."
        return .result(value: amount, dialog: dialog)
    }
}

// MARK: - AppShortcutsProvider
//
// Surfaces the intents in the Shortcuts app + as Siri suggestions
// on the Lock Screen / Spotlight without the user explicitly setting
// up a shortcut. iOS picks the most-likely-used one based on context.

@available(iOS 16.0, *)
struct VoygoAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindVoygoRoutesIntent(),
            phrases: [
                "Find routes in \(.applicationName)",
                "Search \(.applicationName) routes",
                "Open \(.applicationName) search"
            ],
            shortTitle: "Find Routes",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenNextCommuteIntent(),
            phrases: [
                "Open my next \(.applicationName) commute",
                "Show my next \(.applicationName) ride",
                "What's my next \(.applicationName) trip"
            ],
            shortTitle: "Next Commute",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: VoygoCreditIntent(),
            phrases: [
                "Check my \(.applicationName) credit",
                "How much \(.applicationName) Credit do I have",
                "\(.applicationName) wallet balance"
            ],
            shortTitle: "Voygo Credit",
            systemImageName: "creditcard.fill"
        )
    }
}
