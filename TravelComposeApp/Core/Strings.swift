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

    // Welcome feature chips on phone-entry screen.
    static var authFeatureDailyRoutes: String { Self.t("auth.feature.dailyRoutes", "Daily routes") }
    static var authFeatureTrustedDrivers: String { Self.t("auth.feature.trustedDrivers", "Trusted drivers") }
    static var authFeatureReserveSeats: String { Self.t("auth.feature.reserveSeats", "Reserve seats") }

    // OTP screen copy.
    static var authOtpTitle: String { Self.t("auth.otp.title", "Verify Phone Number") }
    static func authOtpBody(_ phone: String) -> String {
        let template = Self.t("auth.otp.body", "Enter the 6-digit code sent to %@")
        return String(format: template, phone)
    }
    static func authOtpDevCode(_ code: String) -> String {
        let template = Self.t("auth.otp.devCode", "Dev code: %@")
        return String(format: template, code)
    }
    static func authResendIn(_ seconds: Int) -> String {
        let template = Self.t("auth.otp.resendIn", "Resend code in 0:%02d")
        return String(format: template, seconds)
    }
    static var authResendCode: String { Self.t("auth.otp.resendCode", "Resend Code") }
    static var authResending: String { Self.t("auth.otp.resending", "Resending\u{2026}") }
    static var authVerify: String { Self.t("auth.otp.verify", "Verify") }
    static var authVerifyNumberNav: String { Self.t("auth.otp.navTitle", "Verify Number") }
    static var authOtpA11yLabel: String { Self.t("auth.otp.a11y.label", "One-time code") }
    static var authOtpA11yEmpty: String { Self.t("auth.otp.a11y.empty", "Empty") }
    static func authOtpA11yEntered(_ count: Int) -> String {
        let template = Self.t("auth.otp.a11y.entered", "%d of 6 digits entered")
        return String(format: template, count)
    }
    static var authOtpA11yHint: String { Self.t("auth.otp.a11y.hint", "Tap to enter the six-digit code sent to your phone") }

    // Sign in with Apple status surfaces (pilot — backend exchange not wired yet).
    static func authAppleCredentialReceived(_ suffix: String) -> String {
        let template = Self.t("auth.apple.credentialReceived", "Apple credential received (\u{2022}\u{2022}\u{2022}%@). Backend exchange coming soon \u{2014} please use phone OTP for now.")
        return String(format: template, suffix)
    }
    static func authAppleSignInFailed(_ reason: String) -> String {
        let template = Self.t("auth.apple.failed", "Sign in with Apple failed: %@")
        return String(format: template, reason)
    }
    static var authAppleCredentialMissing: String { Self.t("auth.apple.credentialMissing", "Apple ID credential missing.") }
    static var authAppleSignInHint: String { Self.t("auth.apple.signInHint", "Sign in using your Apple ID") }
    static var authPhoneFieldLabel: String { Self.t("auth.phone.fieldLabel", "Phone number") }

    // MARK: Profile

    static var profileWelcome: String { Self.t("profile.welcome", "Welcome") }
    static var profileNewRider: String { Self.t("profile.newRider", "New rider") }
    static var profileMemberSinceLabel: String { Self.t("profile.memberSince", "Member since") }
    static var profileMemberSinceToday: String { Self.t("profile.memberSinceToday", "Today") }
    static var profileRidesLabel: String { Self.t("profile.rides", "Rides") }
    static var profileLogOut: String { Self.t("profile.logOut", "Log out") }
    static var profileLogOutTitle: String { Self.t("profile.logOutTitle", "Log Out") }
    static var profileLogOutMessage: String { Self.t("profile.logOutMessage", "You'll need to sign in again.") }
    /// Pluralised "rides count" label. Avoids the misleading
    /// "0 ride" / "1 rides" wording the previous `"\(n) rides"`
    /// interpolation produced and translates cleanly across locales.
    static func profileRidesCount(_ n: Int) -> String {
        if n == 1 {
            return Self.t("profile.ridesCount.one", "1 ride")
        }
        let template = Self.t("profile.ridesCount.many", "%d rides")
        return String(format: template, n)
    }

    // Settings row titles (Profile screen).
    static var profileSettingsIdentityVerification: String { Self.t("profile.settings.identityVerification", "Identity Verification") }
    static var profileSettingsWalletAndPayments: String { Self.t("profile.settings.walletAndPayments", "Wallet & payment methods") }
    static var profileSettingsFavourites: String { Self.t("profile.settings.favourites", "Favourites") }
    static var profileSettingsFavouritesNoneSaved: String { Self.t("profile.settings.favourites.noneSaved", "None saved") }
    static func profileSettingsFavouritesSaved(_ n: Int) -> String {
        let template = Self.t("profile.settings.favourites.saved", "%d saved")
        return String(format: template, n)
    }
    static var profileSettingsMyRequests: String { Self.t("profile.settings.myRequests", "My requests") }
    static var profileSettingsMyRequestsNone: String { Self.t("profile.settings.myRequests.none", "None waiting") }
    static func profileSettingsMyRequestsWaiting(_ n: Int) -> String {
        let template = Self.t("profile.settings.myRequests.waiting", "%d waiting")
        return String(format: template, n)
    }
    static var profileSettingsNotifications: String { Self.t("profile.settings.notifications", "Notifications") }
    static var profileSettingsPrivacy: String { Self.t("profile.settings.privacy", "Privacy & Security") }
    static var profileSettingsPaymentMethods: String { Self.t("profile.settings.paymentMethods", "Payment methods") }
    static var profileSettingsActivity: String { Self.t("profile.settings.activity", "Activity") }
    static var profileSettingsTripHistory: String { Self.t("profile.settings.tripHistory", "Trip history") }
    static var profileSettingsHelpCenter: String { Self.t("profile.settings.helpCenter", "Help Center") }

    // Driver mode card on Profile.
    static var profileDriverMode: String { Self.t("profile.driver.mode", "Driver mode") }
    static var profileDriverPublishFirst: String { Self.t("profile.driver.publishFirst", "Publish your first route") }
    static var profileDriverManageSubtitle: String { Self.t("profile.driver.manageSubtitle", "Manage your routes & earnings") }
    static var profileDriverApprovedSubtitle: String { Self.t("profile.driver.approvedSubtitle", "Your KYC is approved — start offering seats") }

    // Vehicle card + Edit vehicle sheet.
    static var profileVehicleTitle: String { Self.t("profile.vehicle.title", "Your vehicle") }
    static var profileVehicleSetUp: String { Self.t("profile.vehicle.setUp", "Set up") }
    static var profileVehicleSubtitle: String { Self.t("profile.vehicle.subtitle", "Set your plate, colour & model so riders can spot you") }
    static var profileVehicleEditHint: String { Self.t("profile.vehicle.editHint", "Tap to edit your plate, colour and model") }
    static var profileVehiclePlate: String { Self.t("profile.vehicle.plate", "Plate number") }
    static var profileVehiclePlatePlaceholder: String { Self.t("profile.vehicle.platePlaceholder", "PEN 1234") }
    static var profileVehicleColour: String { Self.t("profile.vehicle.colour", "Colour") }
    static var profileVehicleColourPlaceholder: String { Self.t("profile.vehicle.colourPlaceholder", "White") }
    static var profileVehicleModel: String { Self.t("profile.vehicle.model", "Model") }
    static var profileVehicleModelPlaceholder: String { Self.t("profile.vehicle.modelPlaceholder", "Myvi") }
    static var profileVehicleSheetSubtitle: String { Self.t("profile.vehicle.sheetSubtitle", "Riders use your plate, colour and model to spot the right car at the pickup point. This is set once and applies to every route you publish.") }

    // Edit display name sheet.
    static var profileNameSheetTitle: String { Self.t("profile.name.sheetTitle", "Your name") }
    static var profileNameSheetSubtitle: String { Self.t("profile.name.sheetSubtitle", "This is how drivers and riders see you on receipts, chat threads and ride confirmations.") }
    static var profileNamePlaceholder: String { Self.t("profile.name.placeholder", "e.g. Vishnu Kumar") }
    static var profileNameEditHint: String { Self.t("profile.name.editHint", "Tap to edit your display name") }

    // Language picker
    static var profileSettingsLanguage: String { Self.t("profile.settings.language", "Language") }
    static var langPickerTitle: String         { Self.t("lang.picker.title", "Language") }
    static var langPickerSubtitle: String      { Self.t("lang.picker.subtitle", "Choose the language Voygo uses in the app. This is independent of your iPhone's language setting.") }
    static var langSystem: String              { Self.t("lang.system", "Follow iPhone language") }
    static var langEnglish: String             { Self.t("lang.english", "English") }
    static var langBahasa: String              { Self.t("lang.bahasa", "Bahasa Malaysia") }

    // Help Center
    static var helpCenterTitle: String   { Self.t("help.center.title", "Help Center") }
    static var helpNeedHelp: String      { Self.t("help.needHelp",     "Need help?") }
    static var helpHereForYou: String    { Self.t("help.hereForYou",   "We're here for you") }
    static var helpEmailSupport: String  { Self.t("help.emailSupport", "Email support") }
    static var helpInAppChat: String     { Self.t("help.inAppChat",    "In-app chat") }
    static var helpInAppChatValue: String { Self.t("help.inAppChatValue", "Available from Inbox tab") }
    static var helpFAQ: String           { Self.t("help.faq",          "FAQ") }
    static var helpFooter: String        { Self.t("help.footer",       "For commute subscriptions, route issues, or payment questions, contact our support team. We typically respond within 2 hours.") }

    // KYC card on Profile — message + badge text.
    static var profileKycMessageApproved: String { Self.t("profile.kyc.message.approved", "You are fully verified · MyKad on file") }
    static var profileKycMessagePending: String { Self.t("profile.kyc.message.pending", "Verification under review") }
    static var profileKycMessageRejected: String { Self.t("profile.kyc.message.rejected", "Verification rejected – resubmit") }
    static var profileKycMessageNotStarted: String { Self.t("profile.kyc.message.notStarted", "Complete verification to drive") }
    /// Inline rejection-reason variant shown on the Profile KYC card.
    /// `%1$@` is the doc kind label, `%2$@` is the reason.
    static func profileKycMessageRejectedWithReason(_ kind: String, _ reason: String) -> String {
        let template = Self.t("profile.kyc.message.rejected.withReason", "%1$@ rejected — %2$@")
        return String(format: template, kind, reason)
    }
    static var profileKycBadgeVerified: String { Self.t("profile.kyc.badge.verified", "Verified") }
    static var profileKycBadgePending: String { Self.t("profile.kyc.badge.pending", "Pending") }
    static var profileKycBadgeRejected: String { Self.t("profile.kyc.badge.rejected", "Rejected") }
    static var profileKycBadgeNotStarted: String { Self.t("profile.kyc.badge.notStarted", "Not Started") }

    // Wallet subtitle on the Profile wallet card.
    static var profileWalletSyncAfterSignIn: String { Self.t("profile.wallet.syncAfterSignIn", "Wallet syncs after sign-in") }
    static var profileWalletNoPayments: String { Self.t("profile.wallet.noPayments", "No payments yet") }
    static var profileWalletViewPayments: String { Self.t("profile.wallet.viewPayments", "View payments & receipts") }
    static func profileWalletCreditAndPayments(_ credit: String) -> String {
        let template = Self.t("profile.wallet.creditAndPayments", "%@ credit · view payments")
        return String(format: template, credit)
    }

    // Payment methods subtitle on the Profile settings row.
    static var profileSettingsPayMethodsSignedOut: String { Self.t("profile.settings.payMethods.signedOut", "Sign in to manage") }

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

    // Privacy & Security — additional toggles, dialogs and errors.
    static var privacyAnalyticsTitle: String { Self.t("privacy.toggle.analytics", "Product analytics") }
    static var privacyAnalyticsSubtitle: String { Self.t("privacy.toggle.analyticsSubtitle", "Share usage events that help improve reliability and route matching") }

    static var privacyBlocksCounterMax: String { Self.t("privacy.blocks.max", "200") }
    static func privacyBlocksCounter(_ count: Int) -> String {
        let template = Self.t("privacy.blocks.counter", "%d/200")
        return String(format: template, count)
    }

    static var privacyDeleteConfirmTitle: String { Self.t("privacy.delete.confirmTitle", "Delete this account?") }
    static var privacyDeleteConfirmBody: String { Self.t("privacy.delete.confirmBody", "Your account, routes, and subscriptions will be paused immediately. You have 30 days to sign back in to cancel. After that, your data is permanently anonymised.") }
    static var privacyDeleteContinue: String { Self.t("privacy.delete.continue", "Continue") }
    static var privacyDeleteFinalTitle: String { Self.t("privacy.delete.finalTitle", "Really delete?") }
    static var privacyDeleteFinalBody: String { Self.t("privacy.delete.finalBody", "This is your last chance to back out. We'll email a confirmation.") }
    static var privacyDeleteYes: String { Self.t("privacy.delete.yes", "Yes, delete") }
    static var privacyDeleteKeep: String { Self.t("privacy.delete.keep", "Keep my account") }

    static var privacyLoadFailed: String { Self.t("privacy.error.loadFailed", "Couldn't load preferences.") }
    static var privacySaveFailed: String { Self.t("privacy.error.saveFailed", "Couldn't save preference. Try again.") }
    static var privacyUnblockFailed: String { Self.t("privacy.error.unblockFailed", "Couldn't unblock. Try again.") }
    static var privacyUnblockedToast: String { Self.t("privacy.unblockedToast", "Unblocked.") }
    static var privacyExportFailed: String { Self.t("privacy.error.exportFailed", "Couldn't queue the export. Try again.") }
    static var privacyDeleteFailed: String { Self.t("privacy.error.deleteFailed", "Couldn't delete the account. Try again or email support.") }

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

    // Time-of-day greeting + identity fallbacks (Home hero).
    static var homeGreetingMorning: String   { Self.t("home.greeting.morning",   "Good morning") }
    static var homeGreetingAfternoon: String { Self.t("home.greeting.afternoon", "Good afternoon") }
    static var homeGreetingEvening: String   { Self.t("home.greeting.evening",   "Good evening") }
    static var homeGreetingFallback: String  { Self.t("home.greeting.fallback",  "Hi there") }
    static var homeFirstNameFallback: String { Self.t("home.firstName.fallback", "there") }
    static var homeDriverFallback: String    { Self.t("home.driver.fallback",    "Driver") }
    static var homeA11yNextCommute: String   { Self.t("home.a11y.nextCommute",   "Open route details for next commute") }
    static var homeA11yActionRequired: String { Self.t("home.a11y.actionRequired", "Action required: subscription paused. Tap to resolve.") }
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
    static var homeServiceBookDay: String  { Self.t("home.service.bookDay",  "Book a day") }

    // MARK: Book a day

    static var bookDayPickTitle: String         { Self.t("bookDay.pickTitle",        "Book a day") }
    static var bookDayConfirmTitle: String      { Self.t("bookDay.confirmTitle",     "Confirm booking") }
    static var bookDayExplainerTitle: String    { Self.t("bookDay.explainer.title",  "One day, no commitment") }
    static var bookDayExplainerBody: String     { Self.t("bookDay.explainer.body",   "Pay 1× the seat price for a single day. Same trusted driver — book just the day you need, no monthly subscription.") }
    static var bookDayEmptyTitle: String        { Self.t("bookDay.empty.title",      "Find a route first") }
    static var bookDayEmptyBody: String         { Self.t("bookDay.empty.body",       "Book-a-day rides run on existing carpool routes — find one you like, then pick a day to ride.") }
    static var bookDayBrowseRoutes: String      { Self.t("bookDay.browseRoutes",     "Browse routes") }
    static var bookDayNoDatesAvailable: String  { Self.t("bookDay.noDates",          "No upcoming dates in the next 2 weeks.") }
    static var bookDaySeatSuffix: String        { Self.t("bookDay.seatSuffix",       "seat") }
    static func bookDayDepartsAt(_ time: String) -> String {
        let template = Self.t("bookDay.departsAt", "Departs %@")
        return String(format: template, time)
    }
    static var bookDayDeparts: String           { Self.t("bookDay.departs",          "Departs") }
    static var bookDaySeatPrice: String         { Self.t("bookDay.seatPrice",        "Total") }
    static var bookDayNoSeatsLeft: String       { Self.t("bookDay.noSeatsLeft",      "No seats left on this date — try another day.") }
    static var bookDayLoadFailed: String        { Self.t("bookDay.loadFailed",       "Couldn't load this ride") }
    static var bookDayPaymentCouldntStart: String {
        Self.t("bookDay.payment.couldntStart", "Payment couldn't start. Try again in a moment.")
    }
    static var bookDayPaymentDeclined: String   { Self.t("bookDay.payment.declined", "Payment declined. Try another day or use a different payment method.") }
    static func bookDayConfirmCTA(_ amountMyr: Int) -> String {
        let template = Self.t("bookDay.confirmCTA", "Confirm \u{2014} RM %d")
        return String(format: template, amountMyr)
    }
    static var bookDayWhatYouGetTitle: String   { Self.t("bookDay.whatYouGet.title", "What you get") }
    static var bookDayWhatYouGetSeat: String    { Self.t("bookDay.whatYouGet.seat",  "One reserved seat on this ride") }
    static var bookDayWhatYouGetDriver: String  { Self.t("bookDay.whatYouGet.driver", "Same vetted driver who runs the route daily") }
    static var bookDayWhatYouGetNoCommit: String { Self.t("bookDay.whatYouGet.noCommit", "No monthly commitment — pay only for the day") }
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

    // Wallet — Next-charge preview + accepted-methods chips
    // (replaces the old empty "Payment methods" placeholder).
    static var walletNextChargeTitle: String  { Self.t("wallet.nextCharge.title",  "NEXT CHARGE") }
    static var walletNextChargeNoneTitle: String { Self.t("wallet.nextCharge.none.title", "No upcoming charge") }
    static var walletNextChargeNoneBody: String  { Self.t("wallet.nextCharge.none.body",  "Subscribe to a route and the next renewal date and amount appear here.") }
    /// "RM {amount} on {date}" headline for the next-charge card.
    static func walletNextChargeAmountOn(_ amount: String, _ date: String) -> String {
        let template = Self.t("wallet.nextCharge.amountOn", "%@ on %@")
        return String(format: template, amount, date)
    }
    /// Subtitle: "{route} · {tier}". Joined here so translators see one
    /// string instead of two `·`-glued fragments.
    static func walletNextChargeRouteTier(_ route: String, _ tier: String) -> String {
        let template = Self.t("wallet.nextCharge.routeTier", "%@ · %@")
        return String(format: template, route, tier)
    }
    static var walletNextChargeHint: String   { Self.t("wallet.nextCharge.hint",   "Auto-renews · Pause from My commutes to skip") }
    static var walletAcceptedAtCheckout: String { Self.t("wallet.acceptedAtCheckout", "ACCEPTED AT CHECKOUT") }
    static var walletPickAtCheckout: String     { Self.t("wallet.pickAtCheckout",   "Pick your preferred method on the Billplz page.") }

    // MARK: KYC (visible-screen extras)

    static var kycTitle: String { Self.t("kyc.title", "Identity Verification") }
    static var kycKicker: String { Self.t("kyc.kicker", "Trust & safety") }
    static var kycWhoVerifying: String { Self.t("kyc.whoVerifying", "Who's verifying") }
    static var kycRider: String { Self.t("kyc.rider", "Rider") }
    static var kycDriver: String { Self.t("kyc.driver", "Driver") }
    static var kycRiderDocsCount: String { Self.t("kyc.riderDocsCount", "3 documents") }
    static var kycDriverDocsCount: String { Self.t("kyc.driverDocsCount", "7 documents") }
    /// Localised "N documents" — used by the rider/driver role chip
    /// subtitle. Built from `KycDocumentKind.{rider,driver}Required.count`
    /// so the count never drifts from the checklist.
    static func kycDocsCount(_ n: Int) -> String {
        if n == 1 {
            return Self.t("kyc.docsCount.one", "1 document")
        }
        let template = Self.t("kyc.docsCount.many", "%d documents")
        return String(format: template, n)
    }
    static var kycDocsUploaded: String { Self.t("kyc.docsUploaded", "Documents uploaded") }
    static var kycStuckTitle: String { Self.t("kyc.stuckTitle", "Stuck for over 48 hours?") }
    static var kycStuckBody: String { Self.t("kyc.stuckBody", "Email support@voygo.app with your name and we'll prioritise your review.") }
    static var kycEmailSupport: String { Self.t("kyc.emailSupport", "Email support →") }

    // KYC verification view — status copy + footer + submit CTA.
    static var kycStatusApprovedTitle: String { Self.t("kyc.status.approved.title", "You're fully verified") }
    static var kycStatusApprovedSubtitle: String { Self.t("kyc.status.approved.subtitle", "MyKad on file · trusted account") }
    static var kycStatusPendingTitle: String { Self.t("kyc.status.pending.title", "Verification under review") }
    static var kycStatusPendingSubtitle: String { Self.t("kyc.status.pending.subtitle", "Most reviews finish in 24–48 hours") }
    static var kycStatusRejectedTitle: String { Self.t("kyc.status.rejected.title", "Verification rejected") }
    static var kycStatusRejectedSubtitle: String { Self.t("kyc.status.rejected.subtitle", "Resubmit the rejected docs below to retry") }
    static var kycStatusNotStartedTitle: String { Self.t("kyc.status.notStarted.title", "Verify to start riding") }
    static var kycStatusNotStartedSubtitle: String { Self.t("kyc.status.notStarted.subtitle", "MyKad + selfie covers riders. Drivers add license + vehicle.") }
    static var kycFooterBlurb: String { Self.t("kyc.footer.blurb", "We use your documents to verify identity, run a quick safety check, and meet Bank Negara KYC rules. Only trust & safety reviewers see your photos.") }
    static var kycSubmitForReview: String { Self.t("kyc.submitForReview", "Mark verification submitted") }
    static func kycUploadedToast(_ label: String) -> String {
        let template = Self.t("kyc.uploadedToast", "%@ uploaded — review pending")
        return String(format: template, label)
    }
    static func kycUploadFailed(_ reason: String) -> String {
        let template = Self.t("kyc.uploadFailed", "Upload failed. %@")
        return String(format: template, reason)
    }
    static var kycUploadLinkFailed: String { Self.t("kyc.uploadLinkFailed", "Couldn't link upload") }

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

    // MARK: Route info rows
    static var routeInfoRoute: String { Self.t("route.info.route", "Route") }
    static var routeInfoDeparture: String { Self.t("route.info.departure", "Departure") }
    static var routeInfoSchedule: String { Self.t("route.info.schedule", "Schedule") }
    static var routeInfoCarType: String { Self.t("route.info.carType", "Car type") }
    static var routeInfoAvailableSeats: String { Self.t("route.info.availableSeats", "Available seats") }
    static func routeInfoSeatsOf(_ available: Int, _ total: Int) -> String {
        let template = Self.t("route.info.seatsOf", "%d of %d")
        return String(format: template, available, total)
    }
    static var routeInfoActiveRiders: String { Self.t("route.info.activeRiders", "Active riders") }
    static var routeInfoDriverReliability: String { Self.t("route.info.driverReliability", "Driver Reliability") }
    static var routeInfoOnTime: String { Self.t("route.info.onTime", "On-time") }
    static var routeInfoCancelRate: String { Self.t("route.info.cancelRate", "Cancel rate") }
    static var routeInfoRepeatRiders: String { Self.t("route.info.repeatRiders", "Repeat riders") }
    static var routePickupPoint: String { Self.t("route.pickupPoint", "Pickup Point") }
    static var routeDropPoint: String { Self.t("route.dropPoint", "Drop Point") }

    // MARK: Subscribe — config + tier picker
    static var subscribeSection: String { Self.t("subscribe.section", "Subscription") }
    static var subscribeNumberOfDays: String { Self.t("subscribe.numberOfDays", "Number of days") }
    static func subscribeStartsTodayDays(_ days: Int) -> String {
        let template = Self.t("subscribe.startsTodayDays", "Starts today · %d days")
        return String(format: template, days)
    }
    static var subscribeTier: String { Self.t("subscribe.tier", "Tier") }
    static var subscribeTierTry: String { Self.t("subscribe.tier.try", "Try it") }
    static func subscribeTierDiscount(percent: Int) -> String {
        let template = Self.t("subscribe.tier.discount", "%d%% off")
        return String(format: template, percent)
    }
    static var subscribeTotal: String { Self.t("subscribe.total", "Total") }

    // MARK: Subscribe — payment failure surfaces
    static func subscribePauseFailed(_ pauseErr: String) -> String {
        let template = Self.t("subscribe.error.pauseFailed",
                              "Payment couldn't start and we couldn't pause: %@. Cancel from My Subscriptions before retrying.")
        return String(format: template, pauseErr)
    }
    static var subscribePauseRetry: String {
        Self.t("subscribe.error.pauseRetry",
               "Payment couldn't start. Subscription paused — retry from My Subscriptions.")
    }
    static func subscribeDeclinedPauseFailed(_ pauseErr: String) -> String {
        let template = Self.t("subscribe.error.declinedPauseFailed",
                              "Payment declined and pause also failed: %@. Cancel from My Subscriptions before retrying.")
        return String(format: template, pauseErr)
    }
    static var subscribeDeclinedPaused: String {
        Self.t("subscribe.error.declinedPaused",
               "Payment declined. Subscription paused — retry from My Subscriptions.")
    }
    static func subscribeFailedPauseFailed(_ payErr: String, _ pauseErr: String) -> String {
        let template = Self.t("subscribe.error.failedPauseFailed",
                              "Payment failed (%@) and we couldn't pause the subscription either: %@. Please cancel from My Subscriptions before retrying.")
        return String(format: template, payErr, pauseErr)
    }
    static func subscribePaymentFailed(_ payErr: String) -> String {
        let template = Self.t("subscribe.error.paymentFailed",
                              "Subscription paused — payment failed: %@. Retry from My Subscriptions.")
        return String(format: template, payErr)
    }
    static func subscribeCancelledPauseFailed(_ pauseErr: String) -> String {
        let template = Self.t("subscribe.error.cancelledPauseFailed",
                              "Payment cancelled — pause also failed: %@.")
        return String(format: template, pauseErr)
    }
    static var subscribeNotCompleted: String {
        Self.t("subscribe.error.notCompleted",
               "Payment not completed. Subscription paused — retry from My Subscriptions.")
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
    // Multi-select / bulk-cancel
    static var subsSelect: String        { Self.t("subs.select",        "Select") }
    static var subsDone: String          { Self.t("subs.done",          "Done") }
    static var subsSelectAll: String     { Self.t("subs.selectAll",     "Select all") }
    static var subsClearAll: String      { Self.t("subs.clearAll",      "Clear all") }
    static var subsCalendarA11y: String  { Self.t("subs.calendarA11y",  "Open calendar") }
    static func subsBulkCancelCTA(_ n: Int) -> String {
        let template = Self.t("subs.bulkCancel.cta", "Cancel %d")
        return String(format: template, n)
    }
    static func subsBulkCancelTitle(_ n: Int) -> String {
        let template = n == 1
            ? Self.t("subs.bulkCancel.title.one",  "Cancel 1 subscription?")
            : Self.t("subs.bulkCancel.title.many", "Cancel %d subscriptions?")
        return n == 1 ? template : String(format: template, n)
    }
    static func subsBulkCancelConfirm(_ n: Int) -> String {
        let template = n == 1
            ? Self.t("subs.bulkCancel.confirm.one",  "Yes, cancel 1")
            : Self.t("subs.bulkCancel.confirm.many", "Yes, cancel %d")
        return n == 1 ? template : String(format: template, n)
    }
    static var subsBulkCancelBody: String { Self.t("subs.bulkCancel.body", "Remaining rides will be cancelled. Refunds are calculated by our policy engine and applied to your Voygo Credit.") }
    static func subsBulkCancelFailed(_ routes: String) -> String {
        let template = Self.t("subs.bulkCancel.failed", "Couldn't cancel: %@. Try again or cancel individually.")
        return String(format: template, routes)
    }

    // MARK: Upcoming Commutes (calendar view) — multi-select bulk-skip

    /// Nav-bar title for the Upcoming Commutes view. We renamed it from
    /// "Calendar" to "Upcoming Commutes" once bulk-skip moved here from
    /// My commutes — "Upcoming" makes the per-day instance scope obvious,
    /// where "Calendar" suggested the whole month view.
    static var upcomingCommutesTitle: String { Self.t("upcoming.title", "Upcoming Commutes") }
    static var upcomingEmptyTitle: String    { Self.t("upcoming.empty.title", "No upcoming commutes") }
    static var upcomingEmptyBody: String     { Self.t("upcoming.empty.body",  "Subscribe to a route to see your schedule here") }

    /// Confirm-dialog title for bulk-skip. Two branches so the singular
    /// reads naturally instead of "Skip 1 rides?".
    static func bulkSkipTitle(_ n: Int) -> String {
        let template = n == 1
            ? Self.t("upcoming.bulkSkip.title.one",  "Skip 1 ride?")
            : Self.t("upcoming.bulkSkip.title.many", "Skip %d rides?")
        return n == 1 ? template : String(format: template, n)
    }
    static func bulkSkipConfirm(_ n: Int) -> String {
        let template = n == 1
            ? Self.t("upcoming.bulkSkip.confirm.one",  "Yes, skip 1")
            : Self.t("upcoming.bulkSkip.confirm.many", "Yes, skip %d")
        return n == 1 ? template : String(format: template, n)
    }
    /// Body explains why skip is gentler than cancel — sub stays active,
    /// resumes the next day. Lifts the rider's fear that "skipping" a
    /// vacation week kills their subscription.
    static var bulkSkipBody: String {
        Self.t("upcoming.bulkSkip.body",
               "These rides won't pick you up. Your subscription stays active and resumes the next day.")
    }
    static func bulkSkipCTA(_ n: Int) -> String {
        let template = Self.t("upcoming.bulkSkip.cta", "Skip %d")
        return String(format: template, n)
    }
    static func bulkSkipFailed(_ n: Int) -> String {
        let template = n == 1
            ? Self.t("upcoming.bulkSkip.failed.one",  "Couldn't skip 1 ride. Try again.")
            : Self.t("upcoming.bulkSkip.failed.many", "Couldn't skip %d rides. Try again.")
        return n == 1 ? template : String(format: template, n)
    }

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
    static var kycRejectedFallback: String { Self.t("kyc.rejected.fallback", "rejected") }
    /// VoiceOver label for a rejected document row's action button.
    /// `%1$@` is the doc kind, `%2$@` is the rejection reason.
    static func kycRowA11yReupload(_ kind: String, _ reason: String) -> String {
        let template = Self.t("kyc.a11y.reupload", "Re-upload %1$@ — %2$@")
        return String(format: template, kind, reason)
    }
    /// VoiceOver label for a fresh / replace action button.
    /// `%1$@` is the action verb, `%2$@` is the doc kind.
    static func kycRowA11yAction(_ action: String, _ kind: String) -> String {
        let template = Self.t("kyc.a11y.action", "%1$@ %2$@")
        return String(format: template, action, kind)
    }
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

    // MARK: Commute / Search (Find Commute Routes view)

    static var commuteHeroSubtitle: String { Self.t("commute.hero.subtitle", "Find or offer recurring commute seats across Malaysia") }
    static var commuteMenuCreate: String { Self.t("commute.menu.create", "Create Route") }
    static var commuteMenuDriverDash: String { Self.t("commute.menu.driverDash", "Driver Dashboard") }
    static var commuteStatRoutes: String { Self.t("commute.stat.routes", "routes") }
    static var commuteStatActiveRides: String { Self.t("commute.stat.activeRides", "active rides") }
    static var commuteStatAvgFare: String { Self.t("commute.stat.avgFare", "avg fare") }
    static var commuteActionFindRide: String { Self.t("commute.action.findRide", "Find Ride") }
    static var commuteActionMatchSeats: String { Self.t("commute.action.matchSeats", "Match seats") }
    static var commuteActionOfferRide: String { Self.t("commute.action.offerRide", "Offer Ride") }
    static var commuteActionShareSeats: String { Self.t("commute.action.shareSeats", "Share seats") }
    static var commuteActionDriver: String { Self.t("commute.action.driver", "Driver") }
    static var commuteActionManage: String { Self.t("commute.action.manage", "Manage") }

    // Search panel
    static var searchFrom: String { Self.t("search.from", "From") }
    static var searchTo: String { Self.t("search.to", "To") }
    static var searchFromPlaceholder: String { Self.t("search.from.placeholder", "Home, current location, or pickup") }
    static var searchToPlaceholder: String { Self.t("search.to.placeholder", "Office or destination") }
    static var searchUseCurrentLocation: String { Self.t("search.useCurrentLocation", "Use Current Location") }
    static var searchUseCurrentLocationHint: String { Self.t("search.useCurrentLocation.hint", "Set your starting point from GPS") }
    static var searchEarliest: String { Self.t("search.earliest", "Earliest") }
    static var searchLatest: String { Self.t("search.latest", "Latest") }
    static var searchCTA: String { Self.t("search.cta", "Search Routes") }
    static var searchLookingNearby: String { Self.t("search.lookingNearby", "Searching nearby places") }
    static var searchMissingFromTo: String { Self.t("search.missingFromTo", "Enter both From and To before searching routes.") }
    static var searchLocationDenied: String { Self.t("search.locationDenied", "Unable to get your current location. Please allow precise location access in Settings and try again.") }

    // Filters bar
    static var filterRunOn: String { Self.t("filter.runOn", "RUN ON") }
    static var filterBudget: String { Self.t("filter.budget", "BUDGET") }
    static var filterSortBy: String { Self.t("filter.sortBy", "SORT BY") }
    static var filterCap: String { Self.t("filter.cap", "Cap") }
    static var filterAnyPrice: String { Self.t("filter.anyPrice", "Any price") }

    // Sort options (CommuteSortOption rawValue is persisted in
    // UserDefaults — DO NOT change rawValue. These are the display
    // strings only.)
    static var sortBestMatch: String { Self.t("sort.bestMatch", "Best match") }
    static var sortCheapest: String { Self.t("sort.cheapest", "Cheapest") }
    static var sortClosestPickup: String { Self.t("sort.closestPickup", "Closest pickup") }
    static var sortMostReliable: String { Self.t("sort.mostReliable", "Most reliable") }

    // Results
    static var searchResultsTitle: String { Self.t("search.results.title", "Best route matches") }
    static func searchSeatsLeft(_ x: Int, _ y: Int) -> String {
        let template = Self.t("search.seatsLeft", "%d of %d seats left")
        return String(format: template, x, y)
    }

    // Empty state
    static var searchEmptyTitle: String { Self.t("search.empty.title", "No routes for that exact corridor — yet") }
    static var searchEmptyBody: String { Self.t("search.empty.body", "Penang's pilot still has gaps. Try one of these:") }
    static var searchEmptyRequest: String { Self.t("search.empty.request", "Tell drivers I want this corridor") }
    static var searchEmptyWiden: String { Self.t("search.empty.widen", "Try a wider time window (06:00–10:00)") }
    static var searchEmptyReset: String { Self.t("search.empty.reset", "Reset filters") }

    // Share template — "{start} → {end} on Voygo\n{time} · {price}/seat · driver {driver}\n{link}"
    static func shareRouteTemplate(start: String, end: String, time: String, price: String, driver: String, link: String) -> String {
        let template = Self.t("share.route.template", "%@ → %@ on Voygo\n%@ · %@/seat · driver %@\n%@")
        return String(format: template, start, end, time, price, driver, link)
    }

    // MARK: Trip History

    static var tripHistoryTitle: String { Self.t("tripHistory.title", "Trip History") }
    static var tripHistoryFilterAll: String { Self.t("tripHistory.filter.all", "All") }
    static var tripHistoryFilterCompleted: String { Self.t("tripHistory.filter.completed", "Completed") }
    static var tripHistoryFilterCancelled: String { Self.t("tripHistory.filter.cancelled", "Cancelled") }
    static var tripHistoryEmptyTitleNone: String { Self.t("tripHistory.empty.titleNone", "No trips yet") }
    static var tripHistoryEmptyTitleFilter: String { Self.t("tripHistory.empty.titleFilter", "No trips match this filter") }
    static var tripHistoryEmptyBody: String { Self.t("tripHistory.empty.body", "Your completed and cancelled trips will appear here.") }
    static var tripHistoryStatTotal: String { Self.t("tripHistory.stat.total", "Total") }
    static var tripHistoryStatTrips: String { Self.t("tripHistory.stat.trips", "Trips") }
    static var tripHistoryStatRefunded: String { Self.t("tripHistory.stat.refunded", "Refunded") }
    static var tripHistoryRowCancelled: String { Self.t("tripHistory.row.cancelled", "Cancelled") }
    static var tripHistoryRowReceipt: String { Self.t("tripHistory.row.receipt", "Receipt \u{203A}") }
    /// Kicker line with pluralized trip count. Three branches matter:
    /// 0 → "No trips yet", 1 → "1 trip", N → "%d trips".
    static func tripHistoryKicker(_ n: Int) -> String {
        switch n {
        case 0: return Self.t("tripHistory.kicker.zero", "No trips yet")
        case 1: return Self.t("tripHistory.kicker.one", "1 trip")
        default:
            let template = Self.t("tripHistory.kicker.many", "%d trips")
            return String(format: template, n)
        }
    }
    static func tripHistoryRowA11yCancelled(_ dow: String, _ day: String, _ mo: String) -> String {
        let template = Self.t("tripHistory.row.a11yCancelled", "Cancelled trip on %@ %@ %@")
        return String(format: template, dow, day, mo)
    }

    /// Maps the backend tier rawValue ("MONTHLY" / "WEEKLY" / "TRY") to
    /// a localized display label. Falls back to the original string when
    /// nil so legacy callers still render something.
    static func tierLabel(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return Self.t("tier.fallback", "ride") }
        switch raw.uppercased() {
        case "MONTHLY": return Self.t("tier.monthly", "Monthly")
        case "WEEKLY":  return Self.t("tier.weekly",  "Weekly")
        case "TRY":     return Self.t("tier.tryIt",   "Try it")
        default:        return raw.capitalized
        }
    }

    // MARK: Receipt

    static var receiptTitle: String { Self.t("receipt.title", "Receipt") }
    static var receiptStatusCompleted: String { Self.t("receipt.status.completed", "Completed") }
    static var receiptStatusPending: String { Self.t("receipt.status.pending", "Pending payment") }
    static var receiptStatusFailed: String { Self.t("receipt.status.failed", "Failed") }
    static var receiptStatusRefunded: String { Self.t("receipt.status.refunded", "Refunded") }
    static var receiptStatusFallback: String { Self.t("receipt.status.fallback", "Receipt") }
    static func receiptHeader(_ id: String, _ status: String) -> String {
        let template = Self.t("receipt.header", "Booking #%@ · %@")
        return String(format: template, id, status)
    }
    static func receiptBaseFare(_ tier: String) -> String {
        let template = Self.t("receipt.baseFare", "Base fare (%@)")
        return String(format: template, tier)
    }
    static var receiptVoygoCredit: String { Self.t("receipt.voygoCredit", "Voygo credit") }
    static var receiptIncluded: String { Self.t("receipt.included", "Included") }
    static var receiptTotalCharged: String { Self.t("receipt.totalCharged", "Total charged") }
    static var receiptForExpense: String { Self.t("receipt.forExpense", "For expense reimbursement") }
    static var receiptFareBreakdown: String { Self.t("receipt.fareBreakdown", "Fare breakdown") }
    static var receiptVerification: String { Self.t("receipt.verification", "Verification") }
    static var receiptMethodOnFile: String { Self.t("receipt.methodOnFile", "Method on file") }
    static func receiptPickupAt(_ time: String) -> String {
        let template = Self.t("receipt.pickupAt", "Pickup · %@")
        return String(format: template, time)
    }
    static func receiptApproxDrop(_ time: String) -> String {
        let template = Self.t("receipt.approxDrop", "Approx. drop · %@")
        return String(format: template, time)
    }
    static var receiptDriverFallback: String { Self.t("receipt.driverFallback", "Driver") }
    static var receiptPlateOnFile: String { Self.t("receipt.plateOnFile", "plate on file") }
    static func receiptShareText(_ id: String, _ context: String, _ amount: Int, _ status: String) -> String {
        let template = Self.t("receipt.shareText", "Voygo receipt %@: %@, RM %d, %@")
        return String(format: template, id, context, amount, status)
    }
    static func receiptShareTextFallback(_ id: String) -> String {
        let template = Self.t("receipt.shareTextFallback", "Voygo receipt %@")
        return String(format: template, id)
    }
    static func receiptRouteA11y(_ label: String) -> String {
        let template = Self.t("receipt.routeA11y", "Trip route — %@")
        return String(format: template, label)
    }
    static func receiptRouteUnavailableA11y(_ label: String) -> String {
        let template = Self.t("receipt.routeUnavailableA11y", "Trip route unavailable — %@")
        return String(format: template, label)
    }

    // MARK: Wallet — hero + extras
    static var walletHeroLabel: String { Self.t("wallet.heroLabel", "Voygo Credit") }
    static var walletHeroPrefix: String { Self.t("wallet.heroPrefix", "RM") }
    static var walletHeroBadge: String { Self.t("wallet.heroBadge", "VOYGO") }
    static var walletRecentTitle: String { Self.t("wallet.recent", "Recent") }
    static var walletSeeAll: String { Self.t("wallet.seeAll", "See all") }
    static var walletNoPaymentsBody: String { Self.t("wallet.noPaymentsBody", "Subscribe to a route and your charges appear here") }
    static var walletDefault: String { Self.t("wallet.default", "Default") }
    static var walletSubscriptionTitle: String { Self.t("wallet.subscriptionTitle", "Voygo subscription") }
    static func walletRouteTitle(_ shortId: String) -> String {
        let template = Self.t("wallet.routeTitle", "Route %@")
        return String(format: template, shortId)
    }
    static func walletTxSubtitle(_ date: String, _ tier: String) -> String {
        let template = Self.t("wallet.txSubtitle", "%@ · %@")
        return String(format: template, date, tier)
    }
    static var walletLoadingBalanceA11y: String { Self.t("wallet.loadingBalance.a11y", "Loading wallet balance") }

    // Payment status badges (single source of truth)
    static var paymentStatusCharged: String { Self.t("payment.status.charged", "Charged") }
    static var paymentStatusPending: String { Self.t("payment.status.pending", "Pending") }
    static var paymentStatusFailed: String { Self.t("payment.status.failed", "Failed") }
    static var paymentStatusRefunded: String { Self.t("payment.status.refunded", "Refunded") }

    // MARK: Driver Payouts

    static var driverPayoutsNavTitle: String { Self.t("driverPayouts.navTitle", "This week") }
    static var driverPayoutsKicker: String { Self.t("driverPayouts.kicker", "Driver payouts") }
    static var driverPayoutsTitle: String { Self.t("driverPayouts.title", "Driver Payouts") }
    static func driverPayoutsWeekOf(_ start: String, _ end: String) -> String {
        let template = Self.t("driverPayouts.weekOf", "Week of %@ → %@")
        return String(format: template, start, end)
    }
    static var driverPayoutsNetPayout: String { Self.t("driverPayouts.netPayout", "Net payout") }
    static var driverPayoutsRidesCompleted: String { Self.t("driverPayouts.ridesCompleted", "Rides completed") }
    static var driverPayoutsSeatsFilled: String { Self.t("driverPayouts.seatsFilled", "Seats filled") }
    static var driverPayoutsGrossEarnings: String { Self.t("driverPayouts.grossEarnings", "Gross earnings") }
    static var driverPayoutsVoygoFee: String { Self.t("driverPayouts.voygoFee", "Voygo fee") }
    static var driverPayoutsPenaltiesHeld: String { Self.t("driverPayouts.penaltiesHeld", "Penalties held") }
    static var driverPayoutsStreakBonus: String { Self.t("driverPayouts.streakBonus", "Streak bonus") }
    static var driverPayoutsPaysOutBy: String { Self.t("driverPayouts.paysOutBy", "Pays out by Tuesday 5pm") }
    static var driverPayoutsPaidOut: String { Self.t("driverPayouts.paidOut", "Paid out · landing in your bank within 24h") }
    static var driverPayoutsReliability: String { Self.t("driverPayouts.reliability", "Reliability") }
    static func driverPayoutsOnTimePct(_ pct: Int) -> String {
        let template = Self.t("driverPayouts.onTimePct", "%d%% on-time")
        return String(format: template, pct)
    }
    static var driverPayoutsReliabilityTop: String { Self.t("driverPayouts.reliabilityTop", "Top tier. This is what gets riders to renew without thinking about it.") }
    static var driverPayoutsReliabilitySolid: String { Self.t("driverPayouts.reliabilitySolid", "Solid. A late once in a while is fine — riders see the trend, not the outlier.") }
    static var driverPayoutsReliabilityLow: String { Self.t("driverPayouts.reliabilityLow", "Below the corridor average. Quick wins: leave 5 minutes earlier and avoid one-message dropouts.") }
    static var driverPayoutsFootnote: String {
        Self.t("driverPayouts.footnote",
               "Voygo charges a flat per-seat platform fee. This is independent of your fare — your earnings scale only when you fill seats.")
    }
    static var driverPayoutsEmptyTitle: String { Self.t("driverPayouts.empty.title", "No earnings yet") }
    static var driverPayoutsEmptyBody: String { Self.t("driverPayouts.empty.body", "Drive a route this week and your payout will show up here on Tuesday.") }
    static var driverPayoutsZeroRidesTitle: String { Self.t("driverPayouts.zeroRides.title", "No rides this week") }
    static var driverPayoutsZeroRidesBody: String { Self.t("driverPayouts.zeroRides.body", "Once you complete rides on your routes, your earnings show up here on Tuesday.") }

    // Stripe Connect banner copy
    static var driverPayoutsConnectPendingTitle: String { Self.t("driverPayouts.connect.pendingTitle", "Set up bank payouts") }
    static var driverPayoutsConnectPendingBody: String { Self.t("driverPayouts.connect.pendingBody", "Stripe holds it briefly while your bank verifies. Takes ~3 minutes.") }
    static var driverPayoutsConnectPendingCTA: String { Self.t("driverPayouts.connect.pendingCTA", "Continue setup") }
    static var driverPayoutsConnectComingTitle: String { Self.t("driverPayouts.connect.comingTitle", "Bank payouts launching soon") }
    static var driverPayoutsConnectComingBody: String { Self.t("driverPayouts.connect.comingBody", "We'll notify drivers when Stripe Connect is enabled. Earnings keep accruing in the meantime.") }

    // MARK: Driver Dashboard (extras beyond ride control + edit sheet)

    static var driverDashboardTitle: String { Self.t("driver.dashboard.title", "Driver Dashboard") }
    static var driverNavRiderDemand: String { Self.t("driver.nav.riderDemand", "Rider demand") }
    static var driverNavPayouts: String { Self.t("driver.nav.payouts", "Payouts") }
    static var driverPauseAlertTitle: String { Self.t("driver.pause.alertTitle", "Pause this route?") }
    static var driverPauseAlertBody: String { Self.t("driver.pause.alertBody", "Pausing cancels every scheduled pickup on this route. Riders will be notified.") }
    static var driverPauseAlertConfirm: String { Self.t("driver.pause.alertConfirm", "Pause") }
    static var driverDepartureValidationHint: String { Self.t("driver.departureValidationHint", "Departure time must be HH:mm (e.g. 07:42).") }
    static var driverScheduleUpdatedWeekdays: String { Self.t("driver.scheduleUpdated.weekdays", "Schedule updated to weekdays.") }
    static var driverScheduleUpdatedAllDays: String { Self.t("driver.scheduleUpdated.allDays", "Schedule updated to all days.") }
    static var driverRoutePausedToast: String { Self.t("driver.route.pausedToast", "Route paused.") }
    static var driverRouteResumedToast: String { Self.t("driver.route.resumedToast", "Route resumed.") }
    static var driverCardActive: String { Self.t("driver.card.active", "Active") }
    static var driverCardPaused: String { Self.t("driver.card.paused", "Paused") }
    static var driverCardRiders: String { Self.t("driver.card.riders", "Riders") }
    static var driverCardUpcoming: String { Self.t("driver.card.upcoming", "Upcoming") }
    static var driverCardSeats: String { Self.t("driver.card.seats", "Seats") }
    static var driverCardDays: String { Self.t("driver.card.days", "Days") }
    static func driverSoloBookingsAhead(_ count: Int) -> String {
        if count == 1 {
            return Self.t("driver.solo.bookingAhead.one", "1 solo booking ahead")
        }
        let template = Self.t("driver.solo.bookingAhead.many", "%d solo bookings ahead")
        return String(format: template, count)
    }
    static func driverSoloDatesMore(_ head: String, _ more: Int) -> String {
        let template = Self.t("driver.solo.datesMore", "%@, +%d more")
        return String(format: template, head, more)
    }
    static var driverDepartureField: String { Self.t("driver.departureField", "Departure Time (HH:mm)") }
    static var driverDayPresetMonFri: String { Self.t("driver.dayPreset.monFri", "Mon\u{2013}Fri") }
    static var driverDayPresetAllDays: String { Self.t("driver.dayPreset.allDays", "All Days") }
    static var driverPauseRoute: String { Self.t("driver.pauseRoute", "Pause Route") }
    static var driverResumeRoute: String { Self.t("driver.resumeRoute", "Resume Route") }
    static var driverCalendarButton: String { Self.t("driver.calendarButton", "Calendar") }

    // CreateRoute view
    static var createRouteTitle: String { Self.t("createRoute.title", "Create Route") }
    static var createRouteSectionRouteInfo: String { Self.t("createRoute.section.routeInfo", "Route Info") }
    static var createRouteStartLabel: String { Self.t("createRoute.start.label", "Start Location") }
    static var createRouteStartPlaceholder: String { Self.t("createRoute.start.placeholder", "Pick on map · e.g. Komtar") }
    static var createRouteEndLabel: String { Self.t("createRoute.end.label", "Destination") }
    static var createRouteEndPlaceholder: String { Self.t("createRoute.end.placeholder", "Pick on map · e.g. Bayan Lepas") }
    static var createRouteDepartureLabel: String { Self.t("createRoute.departure.label", "DEPARTURE TIME") }
    static var createRouteDeparture: String { Self.t("createRoute.departure", "Departure") }
    static var createRouteSeats: String { Self.t("createRoute.seats", "SEATS") }
    static var createRoutePricePerSeat: String { Self.t("createRoute.pricePerSeat", "PRICE/SEAT") }
    static var createRoutePriceSuffix: String { Self.t("createRoute.priceSuffix", "RM") }
    static func createRouteSeatCapHint(_ maxSeats: Int, _ label: String) -> String {
        let template = Self.t("createRoute.seatCapHint", "Up to %d passengers in a %@")
        return String(format: template, maxSeats, label)
    }
    static var createRouteSectionCarType: String { Self.t("createRoute.section.carType", "Car Type") }
    static var createRouteVehicleMissingTitle: String { Self.t("createRoute.vehicleMissing.title", "Add your vehicle to Profile") }
    static var createRouteVehicleMissingBody: String { Self.t("createRoute.vehicleMissing.body", "Plate + colour go on your profile so riders can spot the right car. Set once, applies to every route.") }
    static func createRouteVehicleHint(_ plate: String) -> String {
        let template = Self.t("createRoute.vehicleHint", "Riders will see: %@")
        return String(format: template, plate)
    }
    static func createRouteVehicleHintWithDescriptor(_ plate: String, _ descriptor: String) -> String {
        let template = Self.t("createRoute.vehicleHintWithDescriptor", "Riders will see: %@ · %@")
        return String(format: template, plate, descriptor)
    }
    static var createRouteSectionDaysOfWeek: String { Self.t("createRoute.section.daysOfWeek", "Days of Week") }
    static var createRouteSectionPickupPoints: String { Self.t("createRoute.section.pickupPoints", "Pickup Points") }
    static var createRouteSectionDropPoints: String { Self.t("createRoute.section.dropPoints", "Drop Points") }
    static var createRouteAddStopLabel: String { Self.t("createRoute.addStop.label", "Add stop") }
    static var createRouteAddStopPlaceholder: String { Self.t("createRoute.addStop.placeholder", "e.g. Komtar") }
    static var createRouteSaveCTA: String { Self.t("createRoute.saveCTA", "Save Recurring Route") }
    static var createRoutePickerFrom: String { Self.t("createRoute.picker.from", "Where from?") }
    static var createRoutePickerTo: String { Self.t("createRoute.picker.to", "Where to?") }
    static func createRouteSuggestedNear(_ anchor: String) -> String {
        let template = Self.t("createRoute.suggestedNear", "Suggested near %@")
        return String(format: template, anchor)
    }
    static var createRouteSuggestedNearby: String { Self.t("createRoute.suggestedNearby", "Suggested nearby") }
    static var createRouteLookingUpHubs: String { Self.t("createRoute.lookingUpHubs", "Looking up transit hubs\u{2026}") }
    static var createRouteSuggestionPopularBadge: String { Self.t("createRoute.suggestion.popularBadge", "Popular") }
    static func createRouteStepperA11y(_ label: String, _ value: Int) -> String {
        let template = Self.t("createRoute.stepper.a11y", "%@ %d. Tap to type.")
        return String(format: template, label, value)
    }

    // MARK: - Internals

    /// Look up a string from `Localizable.strings`, falling back to
    /// the English literal we drew the value from. The fallback keeps
    /// partial translation passes safe — a missing Malay row doesn't
    /// blank the UI.
    ///
    /// Bundle resolution honours the in-app language override the
    /// rider chose via Profile → Settings → Language. When the
    /// override is `.system` (or unset) we hand the lookup to
    /// `Bundle.main`, which respects the OS-level language pref.
    /// When the rider picks "English" or "Bahasa Malaysia" inside
    /// the app, we resolve against the matching `.lproj` bundle so
    /// the choice survives without requiring the user to change
    /// their device language.
    private static func t(_ key: String, _ value: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: AppLocale.bundle, value: value, comment: "")
    }
}

// MARK: - In-app language override

/// Picks the localization bundle for `S.t(...)`. The rider can
/// override the OS-level language from Profile → Settings → Language
/// without changing their device's system language.
///
/// Three values:
///   - `.system`: follow the OS language (`Bundle.main`)
///   - `.en`: force English regardless of OS
///   - `.ms`: force Bahasa Malaysia regardless of OS
///
/// The choice is persisted in UserDefaults under `voygo.appLanguage`.
/// `RootView` reads the same key via `@AppStorage` and uses it as a
/// SwiftUI `id` so changing the language hot-remounts the view tree;
/// no app restart needed.
enum AppLocale: String, CaseIterable {
    case system
    case en
    case ms

    static let storageKey = "voygo.appLanguage"
    /// One-shot flag that LanguageSettingsView sets BEFORE writing a
    /// language change. The Profile view reads + clears it on its
    /// next `.task` after the hot-remount and re-pushes the Language
    /// route. Keeps the rider on the Language page during a switch
    /// instead of dropping them back at Profile root.
    static let restoreToLanguageKey = "voygo.restoreToLanguage"

    /// Returns the currently-selected language, falling back to
    /// `.system` if no override has been written yet.
    static var current: AppLocale {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return AppLocale(rawValue: raw) ?? .system
    }

    /// Localization bundle for the override. `nil` would fall through
    /// to `Bundle.main` (OS-language behaviour); we return a real
    /// Bundle to keep the call-site branch simple.
    static var bundle: Bundle {
        switch current {
        case .system: return .main
        case .en, .ms:
            // Look up the `.lproj` directory for the chosen language
            // inside the app bundle. If the resource isn't present
            // (build-config edge case) fall through to .main so the
            // app still shows English instead of a sea of `S.t` keys.
            if let path = Bundle.main.path(forResource: current.rawValue, ofType: "lproj"),
               let b = Bundle(path: path) {
                return b
            }
            return .main
        }
    }

    /// Locale value to push into the SwiftUI environment so native
    /// formatters (`Date.FormatStyle`, `.formatted(...)`, etc.) align
    /// with the rider's choice.
    var locale: Locale {
        switch self {
        case .system: return .current
        case .en:     return Locale(identifier: "en_MY")
        case .ms:     return Locale(identifier: "ms_MY")
        }
    }

    /// Human-readable label for the language-picker rows. Sourced
    /// through the regular `S.*` lookup so the picker itself is
    /// localized too.
    var displayName: String {
        switch self {
        case .system: return S.langSystem
        case .en:     return S.langEnglish
        case .ms:     return S.langBahasa
        }
    }
}
