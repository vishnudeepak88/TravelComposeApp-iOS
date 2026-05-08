import Testing
import Foundation
@testable import TravelComposeApp

// MARK: - Subscription pricing
//
// Single source of truth — the rider's tier-picker, the receipt, and the
// driver payout statement all read from `SubscriptionPricing`. If these
// expectations drift, any of those surfaces silently disagree with the
// others and trust collapses fast.

@Suite("Subscription pricing")
struct SubscriptionPricingTests {

    @Test("Daily tier is full list price")
    func dailyIsFullPrice() {
        #expect(SubscriptionPricing.discountedPricePerSeat(pricePerSeatMyr: 14, tier: .daily) == 14)
    }

    @Test("Monthly tier applies 10% discount, rounded to whole ringgit")
    func monthlyDiscount() {
        // 14 * 0.90 = 12.6 → round to 13
        #expect(SubscriptionPricing.discountedPricePerSeat(pricePerSeatMyr: 14, tier: .monthly) == 13)
        // 10 * 0.90 = 9.0 → exactly 9
        #expect(SubscriptionPricing.discountedPricePerSeat(pricePerSeatMyr: 10, tier: .monthly) == 9)
    }

    @Test("Quarterly tier applies 15% discount")
    func quarterlyDiscount() {
        // 14 * 0.85 = 11.9 → 12
        #expect(SubscriptionPricing.discountedPricePerSeat(pricePerSeatMyr: 14, tier: .quarterly) == 12)
    }

    @Test("Per-seat price never rounds to zero")
    func neverZero() {
        // Even nonsensical inputs (RM 1 quarterly = 0.85 → 1 after max) keep
        // the line item visible so the user understands they were charged.
        #expect(SubscriptionPricing.discountedPricePerSeat(pricePerSeatMyr: 1, tier: .quarterly) == 1)
    }

    @Test("Total caps at the tier's billable working days")
    func totalCappedAtTierDays() {
        // Monthly is 22 working days. Even if the user picks 60 days,
        // the rider should not be charged for 60 — they're charged for
        // the tier's billing period, not the calendar window.
        let total = SubscriptionPricing.totalForTier(pricePerSeatMyr: 14, tier: .monthly, days: 60)
        // 13 (discounted) * 22 = 286
        #expect(total == 286)
    }

    @Test("Total honors shorter ranges (mid-month signup)")
    func totalHonorsShortRange() {
        let total = SubscriptionPricing.totalForTier(pricePerSeatMyr: 14, tier: .monthly, days: 10)
        // 13 * min(10, 22) = 130
        #expect(total == 130)
    }

    @Test("Savings vs daily computed correctly")
    func savings() {
        // Daily 22 days @ 14 = 308; monthly 22 days = 286 → 22 saved.
        #expect(SubscriptionPricing.savingsVsDaily(pricePerSeatMyr: 14, tier: .monthly, days: 22) == 22)
    }

    @Test("Savings never go negative")
    func savingsNonNegative() {
        // Daily tier vs daily tier = no savings, but never negative.
        #expect(SubscriptionPricing.savingsVsDaily(pricePerSeatMyr: 14, tier: .daily, days: 5) == 0)
    }

    @Test("Working days excludes weekends inclusively")
    func workingDaysExcludesWeekends() {
        let cal = Calendar(identifier: .gregorian)
        // Monday → Friday of the same week → 5 working days.
        let monday = cal.date(from: DateComponents(year: 2026, month: 5, day: 4))!  // Mon
        let friday = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))!  // Fri
        #expect(SubscriptionPricing.workingDaysBetween(monday, friday) == 5)
    }

    @Test("Working days handles weekend-only ranges")
    func workingDaysWeekendOnly() {
        let cal = Calendar(identifier: .gregorian)
        let sat = cal.date(from: DateComponents(year: 2026, month: 5, day: 9))!
        let sun = cal.date(from: DateComponents(year: 2026, month: 5, day: 10))!
        #expect(SubscriptionPricing.workingDaysBetween(sat, sun) == 0)
    }

    @Test("Working days handles inverted ranges gracefully")
    func workingDaysInvertedRange() {
        let cal = Calendar(identifier: .gregorian)
        let later  = cal.date(from: DateComponents(year: 2026, month: 5, day: 8))!
        let earlier = cal.date(from: DateComponents(year: 2026, month: 5, day: 4))!
        // start > end → 0, no crash.
        #expect(SubscriptionPricing.workingDaysBetween(later, earlier) == 0)
    }
}
