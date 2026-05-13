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
    static var sessionExpired: String { Self.t("common.error.sessionExpired", "Sign in to continue.") }
    /// Banner / empty-state title pair for `sessionExpired`. The body
    /// is the period-terminated `sessionExpired` string; this is the
    /// short title shown above it.
    static var signInToContinueTitle: String { Self.t("common.signInToContinue.title", "Sign in to continue") }
    static var soloLoadFailed: String { Self.t("solo.loadFailed.title", "Couldn't load this ride") }
    static var longHaulPageTitle: String { Self.t("longhaul.page.title", "Long-haul") }
    static var longHaulKicker: String    { Self.t("longhaul.page.kicker", "ONE-OFF INTER-CITY TRIPS") }
    static var walletPageTitle: String   { Self.t("wallet.page.title", "Wallet") }
    static var walletPageKicker: String  { Self.t("wallet.page.kicker", "Payments & credits") }
    static var profilePageTitle: String  { Self.t("profile.page.title", "Profile") }

    // MARK: Auth

    static var enterPhone: String { Self.t("auth.enterPhone", "Enter your phone number") }
    static var enterOtp: String { Self.t("auth.enterOtp", "Enter the 6-digit code") }
    static var phoneMissing: String { Self.t("auth.phoneMissing", "Phone number missing — go back and re-enter") }
    static var authBrandName: String { Self.t("auth.brandName", "Voygo") }
    static var authTagline: String { Self.t("auth.tagline", "Your recurring commute, made dependable") }
    static var authPhoneCaption: String { Self.t("auth.phoneCaption", "We'll send a verification code") }
    static var authOr: String { Self.t("auth.or", "or") }
    static var authDevOnly: String { Self.t("auth.devOnly", "DEV ONLY") }
    static var authSkipLogin: String { Self.t("auth.skipLogin", "Skip login \u{2192} home screen") }

    // MARK: Profile

    static var profileWelcome: String { Self.t("profile.welcome", "Welcome") }
    static var profileNewRider: String { Self.t("profile.newRider", "New rider") }
    static var profileMemberSinceLabel: String { Self.t("profile.memberSince", "Member since") }
    static var profileMemberSinceToday: String { Self.t("profile.memberSinceToday", "Today") }
    static var profileRidesLabel: String { Self.t("profile.rides", "Rides") }
    static var profileLogOut: String { Self.t("profile.logOut", "Log out") }
    static var profileLogOutTitle: String { Self.t("profile.logOutTitle", "Log Out") }
    static var profileLogOutMessage: String { Self.t("profile.logOutMessage", "You'll need to sign in again.") }

    // MARK: Privacy & Security

    static var privacyTitle: String { Self.t("privacy.title", "Privacy & Security") }
    static var privacyPreferences: String { Self.t("privacy.section.preferences", "Preferences") }
    static var privacyPushNotifications: String { Self.t("privacy.toggle.push", "Push notifications") }
    static var privacyPushSubtitle: String { Self.t("privacy.toggle.pushSubtitle", "Receive ride reminders, chat messages, payment receipts") }
    static var privacyPhoneShare: String { Self.t("privacy.toggle.phone", "Share phone with subscribers") }
    static var privacyPhoneShareSubtitle: String { Self.t("privacy.toggle.phoneSubtitle", "When OFF, riders see a masked number until pickup") }
    static var privacyBiometric: String { Self.t("privacy.toggle.biometric", "Lock wallet with Face ID") }
    static var privacyBiometricSubtitle: String { Self.t("privacy.toggle.biometricSubtitle", "Require biometric to view payments + receipts") }
    static var privacyMarketing: String { Self.t("privacy.toggle.marketing", "Promotional emails") }
    static var privacyMarketingSubtitle: String { Self.t("privacy.toggle.marketingSubtitle", "Optional. Defaults to OFF (PDPA opt-in)") }
    static var privacyBlockedTitle: String { Self.t("privacy.section.blocked", "Blocked users") }
    static var privacyBlockedEmpty: String { Self.t("privacy.blocked.empty", "No blocked users") }
    static var privacyBlockedEmptyBody: String { Self.t("privacy.blocked.emptyBody", "Block a driver from any route detail to stop being matched with them.") }
    static var privacyUnblock: String { Self.t("privacy.unblock", "Unblock") }
    static var privacyDataTitle: String { Self.t("privacy.section.data", "Your data") }
    static var privacyDataDownload: String { Self.t("privacy.data.download", "Download my data") }
    static var privacyDataDownloadSubtitle: String { Self.t("privacy.data.downloadSubtitle", "We'll email a copy of your rides, payments and profile within 7 days (PDPA s.7)") }
    static var privacyDangerTitle: String { Self.t("privacy.section.danger", "Danger zone") }
    static var privacyDelete: String { Self.t("privacy.delete", "Delete account") }
    static var privacyDeleteSubtitle: String { Self.t("privacy.deleteSubtitle", "Permanently removes your account after 30 days. Required by App Store + PDPA.") }

    // MARK: Solo seat

    static var soloRideTitle: String { Self.t("solo.title", "Ride solo") }
    static var soloBookWhole: String { Self.t("solo.bookWhole", "Book the whole car") }
    static var soloRiderBlurb: String { Self.t("solo.blurb", "Pay ~2\u{00D7} the seat price for an exclusive ride. Same trusted driver, no other passengers, no detours.") }
    static var soloConfirmTitle: String { Self.t("solo.confirmTitle", "Confirm solo ride") }
    static var soloBrowseRoutes: String { Self.t("solo.browseRoutes", "Browse routes") }
    static func soloConfirmCTA(amountMyr: Int) -> String {
        let template = Self.t("solo.confirmCTA", "Confirm \u{2014} RM %d")
        return String(format: template, amountMyr)
    }

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
    static var subKeepIt: String { Self.t("subscribe.keepIt", "Keep it") }

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
    static var homeWhereToMorning: String   { Self.t("home.whereTo.morning",   "Where to,\nthis morning?") }
    static var homeWhereToAfternoon: String { Self.t("home.whereTo.afternoon", "Where to,\nthis afternoon?") }
    static var homeWhereToEvening: String   { Self.t("home.whereTo.evening",   "Where to,\nthis evening?") }
    static var homeWhereToLate: String      { Self.t("home.whereTo.late",      "Where to next?") }
    static var homeFindRide: String { Self.t("home.findRide", "Find ride") }
    static var homeBookARide: String { Self.t("home.bookARide", "Book a ride") }
    static var homeHeadingYourWay: String { Self.t("home.headingYourWay", "Heading your way") }
    static var homeSeeAll: String { Self.t("home.seeAll", "See all") }
    static var homePromoKicker: String { Self.t("home.promo.kicker", "FIRST RIDE FREE") }
    static var homePromoTitle: String { Self.t("home.promo.title", "Try carpool today, save RM 14") }
    static var homeNextCommute: String { Self.t("home.nextCommute", "Next commute") }
    static var homeDestPlaceholder: String { Self.t("home.destPlaceholder", "Where are you heading?") }
    static var homeTo: String { Self.t("home.to", "To") }
    static func homeDeparts(_ time: String) -> String {
        let template = Self.t("home.departs", "Departs %@")
        return String(format: template, time)
    }
    static var homePerSeat: String { Self.t("home.perSeat", "per seat") }
    static var homeServiceCarpool: String { Self.t("home.service.carpool", "Carpool") }
    static var homeServiceSolo: String { Self.t("home.service.solo", "Ride solo") }
    static var homeServiceSchedule: String { Self.t("home.service.schedule", "Schedule") }
    static var homeServiceLongHaul: String { Self.t("home.service.longHaul", "Long-haul") }
    static var homeServiceNewBadge: String { Self.t("home.service.newBadge", "NEW") }
    static var homeWhenToday: String      { Self.t("home.when.today", "Today") }
    static var homeWhenTomorrow: String   { Self.t("home.when.tomorrow", "Tomorrow") }
    static var homeActionCalendar: String { Self.t("home.action.calendar", "Calendar") }
    static var homeActionMessage: String  { Self.t("home.action.message", "Message") }
    static var homeActionInbox: String    { Self.t("home.action.inbox", "Inbox") }
    static var homeActionDetails: String  { Self.t("home.action.details", "Details") }
    static var homeStatusConfirmed: String { Self.t("home.status.confirmed", "Confirmed") }
    static var homeStatusPaused: String    { Self.t("home.status.paused", "Paused") }
    static var homeStatusCompleted: String { Self.t("home.status.completed", "Completed") }
    static var homeStatusCancelled: String { Self.t("home.status.cancelled", "Cancelled") }

    // Subscription / route status — used by model `label` getter so any
    // screen that surfaces `RouteSubscriptionStatus.label` (e.g. the
    // StatusBadge on the Calendar/My-commutes card) localizes for free.
    static var subStatusActive: String    { Self.t("sub.status.active",    "Active") }
    static var subStatusPaused: String    { Self.t("sub.status.paused",    "Paused") }
    static var subStatusCancelled: String { Self.t("sub.status.cancelled", "Cancelled") }
    static var subStatusCompleted: String { Self.t("sub.status.completed", "Completed") }

    // Chat empty state
    static var chatEmptyTitle: String { Self.t("chat.empty.title", "No messages yet") }
    static var chatEmptyBody: String  { Self.t("chat.empty.body",  "Say hi to your driver — they'll see it on their next pickup window.") }
    static var chatDirectKicker: String      { Self.t("chat.direct.kicker", "Direct chat") }
    static var chatMessagePlaceholder: String { Self.t("chat.message.placeholder", "Message…") }

    // MARK: Notifications view
    static var notifTitle: String         { Self.t("notif.title",         "Notifications") }
    static var notifMarkAllRead: String   { Self.t("notif.markAllRead",   "Mark all read") }
    static var notifEmptyTitle: String    { Self.t("notif.empty.title",   "No notifications yet") }
    static var notifEmptyBody: String     { Self.t("notif.empty.body",    "Ride updates, pickup reminders, and chat alerts will appear here.") }
    static var notifGroupToday: String     { Self.t("notif.group.today",     "Today") }
    static var notifGroupYesterday: String { Self.t("notif.group.yesterday", "Yesterday") }
    static var notifGroupThisWeek: String  { Self.t("notif.group.thisWeek",  "This week") }
    static var notifGroupEarlier: String   { Self.t("notif.group.earlier",   "Earlier") }

    // MARK: Wallet (additional)

    static var walletPaymentMethods: String { Self.t("wallet.paymentMethods", "Payment methods") }
    static var walletNoPayments: String { Self.t("wallet.noPayments", "No payments yet") }
    static var walletPayAtCheckout: String { Self.t("wallet.payAtCheckout", "Pay at checkout") }
    static var walletCheckoutBlurb: String { Self.t("wallet.checkoutBlurb", "DuitNow, FPX, TNG and cards are selectable on the Billplz checkout page.") }
    static var walletCreditBlurb: String { Self.t("wallet.creditBlurb", "Credit accumulates from cancellation refunds and applies to your next ride automatically.") }

    // MARK: KYC (visible-screen extras)

    static var kycTitle: String { Self.t("kyc.title", "Identity Verification") }
    static var kycKicker: String { Self.t("kyc.kicker", "Trust & safety") }
    static var kycWhoVerifying: String { Self.t("kyc.whoVerifying", "Who's verifying") }
    static var kycRider: String { Self.t("kyc.rider", "Rider") }
    static var kycDriver: String { Self.t("kyc.driver", "Driver") }
    static var kycRiderDocsCount: String { Self.t("kyc.riderDocsCount", "3 documents") }
    static var kycDriverDocsCount: String { Self.t("kyc.driverDocsCount", "7 documents") }
    static var kycDocsUploaded: String { Self.t("kyc.docsUploaded", "Documents uploaded") }
    static var kycStuckTitle: String { Self.t("kyc.stuckTitle", "Stuck for over 48 hours?") }
    static var kycStuckBody: String { Self.t("kyc.stuckBody", "Email support@voygo.app with your name and we'll prioritise your review.") }
    static var kycEmailSupport: String { Self.t("kyc.emailSupport", "Email support →") }

    // MARK: Route details / common actions

    static var routeDetailsTitle: String { Self.t("route.details.title", "Route Details") }
    static var routeNotFound: String { Self.t("route.notFound", "Route not found") }
    static var routeNotFoundBody: String { Self.t("route.notFoundBody", "This route may no longer be available") }
    static var subscriptionActive: String { Self.t("subscribe.active", "Subscription active!") }
    static var subscribeBookSolo: String { Self.t("subscribe.bookSolo", "Book solo for a day") }
    static func subscribeSoloPrice(_ amount: Int) -> String {
        let template = Self.t("subscribe.soloPrice", "RM %d — whole car, no other passengers")
        return String(format: template, amount)
    }

    // MARK: Inbox + chat

    static var inboxTitle: String { Self.t("inbox.title", "Inbox") }
    static var inboxEmpty: String { Self.t("inbox.empty", "No conversations yet") }
    static var inboxEmptyBody: String { Self.t("inbox.emptyBody", "Subscribe to a route to chat with your driver") }
    static var inboxFindRoutes: String { Self.t("inbox.findRoutes", "Find routes") }

    // MARK: Common UI actions

    static var save: String { Self.t("common.save", "Save") }
    static var done: String { Self.t("common.done", "Done") }
    static var edit: String { Self.t("common.edit", "Edit") }
    static var delete: String { Self.t("common.delete", "Delete") }
    static var confirm: String { Self.t("common.confirm", "Confirm") }
    static var loading: String { Self.t("common.loading", "Loading…") }
    static var refresh: String { Self.t("common.refresh", "Refresh") }
    static var search: String { Self.t("common.search", "Search") }
    static var settings: String { Self.t("common.settings", "Settings") }

    // MARK: Action-required banner (Home)

    static var actionRequiredOne: String { Self.t("home.actionRequired.one", "Subscription paused") }
    static func actionRequiredMany(count: Int) -> String {
        let template = Self.t("home.actionRequired.many", "%d subscriptions paused")
        return String(format: template, count)
    }
    static var actionRequiredBody: String { Self.t("home.actionRequired.body", "Payment didn't go through. Tap to retry — your seats stay reserved until then.") }

    // MARK: Skip-a-day

    static var skipShort: String { Self.t("skip.label", "Skip") }
    static var skipFailedTitle: String { Self.t("skip.failed.title", "Couldn't skip") }
    static var skipAccessibility: String { Self.t("skip.a11y", "Skip this ride") }

    // MARK: Subscriptions list

    static var subscriptionsTitle: String { Self.t("subs.title", "My commutes") }
    static var subscriptionsEmptyTitle: String { Self.t("subs.empty.title", "No subscriptions") }
    static var subscriptionsEmptyBody: String { Self.t("subs.empty.body", "Search for commute routes and subscribe to start riding") }
    static var subscriptionsEmptyCTA: String { Self.t("subs.empty.cta", "Find a route") }

    // MARK: Tab bar

    static var tabHome: String     { Self.t("tab.home",     "Home") }
    static var tabSearch: String   { Self.t("tab.search",   "Search") }
    static var tabCalendar: String { Self.t("tab.calendar", "Calendar") }
    static var tabInbox: String    { Self.t("tab.inbox",    "Inbox") }
    static var tabProfile: String  { Self.t("tab.profile",  "Profile") }

    // MARK: Driver dashboard

    static var driverEmptyTitle: String { Self.t("driver.empty.title", "No routes yet") }
    static var driverEmptyBody: String { Self.t("driver.empty.body", "Create your first recurring route to start picking up riders") }
    static var driverEmptyCTA: String { Self.t("driver.empty.cta", "Create a route") }
    static var driverTodayRide: String       { Self.t("driver.todayRide",       "Today's ride") }
    static var driverRideScheduled: String   { Self.t("driver.rideScheduled",   "Scheduled") }
    static var driverRideInProgress: String  { Self.t("driver.rideInProgress",  "Live") }
    static var driverStartRide: String       { Self.t("driver.startRide",       "Start ride") }
    static var driverEndRide: String         { Self.t("driver.endRide",         "End ride") }
    static var driverMarkNoShow: String      { Self.t("driver.markNoShow",      "No-show") }
    static var driverConfirmNoShowTitle: String {
        Self.t("driver.noShow.confirm.title", "Mark rider as no-show?")
    }
    static func driverConfirmNoShowBody(_ name: String) -> String {
        let template = Self.t("driver.noShow.confirm.body", "%@ will be removed from this ride and notified. This can affect their trust score.")
        return String(format: template, name)
    }
    static var driverEditRoute: String       { Self.t("driver.editRoute",       "Edit route") }
    static var driverEditPricing: String     { Self.t("driver.editPricing",     "Pricing") }
    static var driverEditPricePerSeat: String { Self.t("driver.editPricePerSeat", "Price per seat") }
    static var driverEditPriceLocked: String { Self.t("driver.editPriceLocked", "Price is locked while riders are subscribed. Wait for current subs to lapse before re-pricing.") }
    static var driverEditSeats: String       { Self.t("driver.editSeats",       "Seats") }
    static var driverEditRouteLabels: String { Self.t("driver.editRouteLabels", "Route labels") }
    static var driverEditStart: String       { Self.t("driver.editStart",       "Start location") }
    static var driverEditEnd: String         { Self.t("driver.editEnd",         "End location") }
    static var driverEditCarType: String     { Self.t("driver.editCarType",     "Car type") }
    static var driverEditSave: String        { Self.t("driver.editSave",        "Save changes") }
    static var driverEditSaved: String       { Self.t("driver.editSaved",       "Saved") }

    // MARK: KYC

    static var kycVerified: String { Self.t("kyc.verified", "Verified") }
    static var kycUnderReview: String { Self.t("kyc.underReview", "Under review") }
    static var kycNotUploaded: String { Self.t("kyc.notUploaded", "Not uploaded") }
    static var kycUpload: String { Self.t("kyc.upload", "Upload") }
    static var kycReplace: String { Self.t("kyc.replace", "Replace") }
    static var kycReupload: String { Self.t("kyc.reupload", "Re-upload") }
    static func kycRejected(reason: String) -> String {
        let template = Self.t("kyc.rejected", "Rejected — %@")
        return String(format: template, reason)
    }

    // MARK: Auth — Terms link copy

    static var authTermsLead: String { Self.t("auth.terms.lead", "By continuing, you agree to Voygo's") }
    static var authTermsLink: String { Self.t("auth.terms.link", "Terms") }
    static var authTermsAnd: String { Self.t("auth.terms.and", "and") }
    static var authPrivacyLink: String { Self.t("auth.privacy.link", "Privacy Policy") }
    static var authSendOtp: String { Self.t("auth.sendOtp", "Send OTP") }

    // MARK: - Internals

    /// Look up a string from `Localizable.strings`, falling back to
    /// the English literal we drew the value from. The fallback keeps
    /// partial translation passes safe — a missing Malay row doesn't
    /// blank the UI.
    private static func t(_ key: String, _ value: String) -> String {
        NSLocalizedString(key, value: value, comment: "")
    }
}
