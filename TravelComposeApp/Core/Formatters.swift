import Foundation

// MARK: - Centralized formatters
//
// QA flagged drift across screens — Wallet showed "RM 42.50", Driver
// Payouts "RM 392", Trip History "RM 14". One canonical money formatter
// here, picked up by every screen that displays monetary amounts.
//
// Same story for dates: "14 JUN" / "Jun 14" / "Jun, 14" all coexisted in
// shipped UI. `Formatters.shortDate` is the single rendition for trip
// rows and receipts; longer renditions delegate to dedicated helpers.

enum Formatters {

    // MARK: Money

    /// Renders an integer MYR amount with 2-decimal precision when it has
    /// fractional sen, omits decimals when it's a whole ringgit. Backend
    /// stores integer MYR today (PaymentRecord.amountMyr) so this mostly
    /// renders "RM 14" and "RM 280", but the formatter accepts a Double
    /// flavor when the receipt later wants to show RM 11.50.
    static func ringgit(_ amountMyr: Int) -> String {
        // Whole ringgit — display without trailing ".00" so the column
        // doesn't look heavy ("RM 14.00" vs "RM 14").
        return "RM \(amountMyr)"
    }

    /// Decimal flavor for screens that need cents (receipts, refunds).
    /// 2 decimals always so "RM 11.50" and "RM 14.00" line up.
    static func ringgit(_ amountMyr: Double) -> String {
        return String(format: "RM %.2f", amountMyr)
    }

    /// Signed amount — negative for debits, positive for credits, used
    /// in transaction lists ("−RM 14", "+RM 7").
    static func ringgitSigned(_ amountMyr: Int, debit: Bool) -> String {
        let prefix = debit ? "−" : "+"
        return "\(prefix)RM \(amountMyr)"
    }

    // MARK: Dates

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_MY")
        f.dateFormat = "d MMM"
        return f
    }()

    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_MY")
        f.dateFormat = "EEE, d MMM"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_MY")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "14 Jun"
    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    /// "Mon, 14 Jun"
    static func longDate(_ date: Date) -> String {
        longDateFormatter.string(from: date)
    }

    /// "07:42" — 24-hour clock to match the rest of the app.
    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Day-of-week abbreviation, locale-aware.
    /// Index 1 (Monday) through 7 (Sunday).
    static func weekday(short: Bool = true, weekdayIndex1Based: Int) -> String {
        let cal = Calendar(identifier: .gregorian)
        var symbols = short ? cal.shortWeekdaySymbols : cal.weekdaySymbols
        // Swift Calendar uses Sunday = 1; we want Monday = 1.
        symbols = Array(symbols[1...]) + [symbols[0]]
        let idx = max(0, min(symbols.count - 1, weekdayIndex1Based - 1))
        return symbols[idx]
    }
}
