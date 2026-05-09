import Foundation

// MARK: - Strings (centralized copy)
//
// Single home for user-facing strings that are reused across views or
// that are easy to typo. Two reasons to keep them here:
//   1. The compiler catches typos in keys like `S.subscribeAndPay(...)`
//      so a view can't silently disagree with its sibling.
//   2. Each entry resolves through `NSLocalizedString`, so adding a
//      new locale is a pure-asset job — drop a `Localizable.strings`
//      under `<lang>.lproj/` and the whole file translates.
//
// Note: Localizable.strings tables live next to this file under the
// project's `Resources/{en,ms}.lproj/` paths. A missing key falls
// back to the English literal supplied as `value:` so partial
// translation passes never crash.

enum S {

    // MARK: Common

    static var comingSoonTitle: String { Self.t("common.comingSoon.title", "Coming soon") }
    static func comingSoonMessage(feature: String) -> String {
        let template = Self.t("common.comingSoon.message", "%@ is on the roadmap. We'll let you know when it lands.")
        return String(format: template, feature)
    }
    static var ok: String { Self.t("common.ok", "OK") }
    static var cancel: String { Self.t("common.cancel", "Cancel") }
    static var retry: String { Self.t("common.retry", "Retry") }
    static var back: String { Self.t("common.back", "Back") }
    static var unknownError: String { Self.t("common.error.unknown", "Something went wrong. Try again in a moment.") }
    static var networkError: String { Self.t("common.error.network", "You're offline. Reconnect and try again.") }
    static var sessionExpired: String { Self.t("common.error.sessionExpired", "Your session has expired. Please sign in again.") }

    // MARK: Auth

    static var enterPhone: String { Self.t("auth.enterPhone", "Enter your phone number") }
    static var enterOtp: String { Self.t("auth.enterOtp", "Enter the 6-digit code") }
    static var phoneMissing: String { Self.t("auth.phoneMissing", "Phone number missing — go back and re-enter") }

    // MARK: Subscription / pricing

    static func subscribeAndPay(amountMyr: Int) -> String {
        let template = Self.t("subscribe.payCTA", "Subscribe & pay RM %d")
        return String(format: template, amountMyr)
    }
    static var subscribeCreating: String { Self.t("subscribe.creating", "Creating subscription…") }
    static var subscribeCharging: String { Self.t("subscribe.charging", "Charging payment…") }
    static var cancelSubscriptionTitle: String { Self.t("subscribe.cancelTitle", "Cancel subscription?") }
    static var cancelSubscriptionMessage: String { Self.t("subscribe.cancelMessage", "Your remaining rides will be cancelled. Refunds are calculated by our policy engine and applied to your Voygo Credit.") }
    static var confirmCancel: String { Self.t("subscribe.confirmCancel", "Yes, cancel") }

    // MARK: Wallet

    static var walletTitle: String { Self.t("wallet.title", "Wallet") }
    static var walletSyncing: String { Self.t("wallet.syncing", "Syncing your wallet…") }
    static var walletAutoApplied: String { Self.t("wallet.autoApplied", "Auto-applied to next ride") }
    static var walletEarnPrompt: String { Self.t("wallet.earnPrompt", "Earn credit from referrals & cancellations") }

    // MARK: Live Trip

    static var liveSos: String { Self.t("live.sos.title", "Send SOS?") }
    static var liveSosMessage: String { Self.t("live.sos.message", "We'll alert your emergency contacts and share your live location.") }
    static var liveSosConfirm: String { Self.t("live.sos.confirm", "Send SOS") }

    // MARK: Home (super-app)

    static var homeWhereTo: String { Self.t("home.whereTo", "Where to,\nthis morning?") }
    static var homeFindRide: String { Self.t("home.findRide", "Find ride") }
    static var homeBookARide: String { Self.t("home.bookARide", "Book a ride") }
    static var homeHeadingYourWay: String { Self.t("home.headingYourWay", "Heading your way") }
    static var homeSeeAll: String { Self.t("home.seeAll", "See all") }
    static var homePromoKicker: String { Self.t("home.promo.kicker", "FIRST RIDE FREE") }
    static var homePromoTitle: String { Self.t("home.promo.title", "Try carpool today, save RM 14") }

    // MARK: - Internals

    /// Look up a string from `Localizable.strings`, falling back to
    /// the English literal we drew the value from. The fallback keeps
    /// partial translation passes safe — a missing Malay row doesn't
    /// blank the UI.
    private static func t(_ key: String, _ value: String) -> String {
        NSLocalizedString(key, value: value, comment: "")
    }
}
