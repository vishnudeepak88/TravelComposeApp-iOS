import Foundation

// MARK: - Strings (centralized copy)
//
// Single home for user-facing strings that are reused across views or
// that are easy to typo. Two reasons to keep them here:
//   1. The compiler now catches `S.subscribeAndPay(amount:)` typos —
//      previously a view that mis-typed the format string just
//      silently disagreed with its sibling.
//   2. When we localize for Bahasa Malaysia (the obvious next step
//      for a Malaysian carpool app), this file is the only place
//      that has to grow `NSLocalizedString` calls. Until then the
//      values are plain literals so we don't pay for an unused
//      `Localizable.strings` table.
//
// Not every string belongs here. Page-specific microcopy (an empty
// state, a single label) is fine in-line; once a string is referenced
// from two places or contains formatting, hoist it.

enum S {

    // MARK: Common

    static let comingSoonTitle = "Coming soon"
    static func comingSoonMessage(feature: String) -> String {
        "\(feature) is on the roadmap. We'll let you know when it lands."
    }
    static let ok = "OK"
    static let cancel = "Cancel"
    static let retry = "Retry"
    static let back = "Back"
    static let unknownError = "Something went wrong. Try again in a moment."
    static let networkError = "You're offline. Reconnect and try again."
    static let sessionExpired = "Your session has expired. Please sign in again."

    // MARK: Auth

    static let enterPhone = "Enter your phone number"
    static let enterOtp = "Enter the 6-digit code"
    static let phoneMissing = "Phone number missing — go back and re-enter"

    // MARK: Subscription / pricing

    static func subscribeAndPay(amountMyr: Int) -> String {
        "Subscribe & pay RM \(amountMyr)"
    }
    static let subscribeCreating = "Creating subscription…"
    static let subscribeCharging = "Charging payment…"
    static let cancelSubscriptionTitle = "Cancel subscription?"
    static let cancelSubscriptionMessage = "Your remaining rides will be cancelled. Refunds are calculated by our policy engine and applied to your Voygo Credit."
    static let confirmCancel = "Yes, cancel"

    // MARK: Wallet

    static let walletTitle = "Wallet"
    static let walletSyncing = "Syncing your wallet…"
    static let walletAutoApplied = "Auto-applied to next ride"
    static let walletEarnPrompt = "Earn credit from referrals & cancellations"

    // MARK: Live Trip

    static let liveSos = "Send SOS?"
    static let liveSosMessage = "We'll alert your emergency contacts and share your live location."
    static let liveSosConfirm = "Send SOS"

    // MARK: Home (super-app)

    static let homeWhereTo = "Where to,\nthis morning?"
    static let homeFindRide = "Find ride"
    static let homeHeadingYourWay = "Heading your way"
    static let homeSeeAll = "See all"
    static let homePromoKicker = "FIRST RIDE FREE"
    static let homePromoTitle = "Try carpool today, save RM 14"
}
