import Foundation

// MARK: - Payment & payout models.
//
// Closes the commercial gap from playbook §3: subscriptions were priced but
// not yet collected. These models ride alongside the existing trust + tier
// models in Trust.swift; nothing in here couples to Billplz specifically so
// we can swap providers later without touching the iOS app.

enum PaymentStatus: String, Codable {
    case pending  = "PENDING"
    case paid     = "PAID"
    case failed   = "FAILED"
    case refunded = "REFUNDED"

    var label: String {
        switch self {
        case .pending:  return "Pending"
        case .paid:     return "Paid"
        case .failed:   return "Failed"
        case .refunded: return "Refunded"
        }
    }
}

struct PaymentRecord: Codable, Identifiable, Equatable {
    var id: String
    var subscriptionId: String?
    var routeId: String?
    var amountMyr: Int
    var currency: String
    var status: PaymentStatus
    var tier: String?
    /// Billplz hosted-checkout URL when status is `.pending`. Nil in mock mode.
    var paymentUrl: String?
    var paidAt: Date?
    var createdAt: Date
}

struct PayoutStatement: Codable, Equatable {
    var driverId: String
    var weekStart: String     // "YYYY-MM-DD"
    var weekEnd: String
    var grossMyr: Int
    var voygoFeeMyr: Int
    var penaltyMyr: Int
    var streakBonusMyr: Int
    var netMyr: Int
    var seatsFilled: Int
    var ridesCount: Int
    var onTimeRate: Double
    var status: String        // "PENDING" | "PAID"
}

/// Result of starting a charge. In mock mode the server resolves immediately
/// to PAID; in production this carries the Billplz redirect URL the rider
/// must visit before we activate the subscription.
struct PaymentChargeResult: Codable, Equatable {
    var paymentId: String
    var status: PaymentStatus
    var paymentUrl: String?
    var billId: String?
    var mockMode: Bool?
}
