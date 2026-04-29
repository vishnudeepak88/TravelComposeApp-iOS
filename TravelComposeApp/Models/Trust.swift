import Foundation

// MARK: - Trust, KYC, pricing tier, and cancellation policy models.
//
// Closes Operations gaps #5.1 (driver onboarding gates), #5.3 (cancellation
// & no-show with monetary teeth), and Pricing §3.2 (subscription tiers). The
// existing `KycStatus` enum stays untouched for backwards compatibility; we
// just add the structured submission and policy types around it.

// MARK: - KYC document submission

enum KycDocumentKind: String, Codable, CaseIterable, Identifiable {
    case nricFront      = "NRIC_FRONT"
    case nricBack       = "NRIC_BACK"
    case selfie         = "SELFIE"
    case drivingLicense = "DRIVING_LICENSE"
    case vehicleRegistration = "VEHICLE_REGISTRATION"
    case insurance      = "INSURANCE"
    case vehiclePhoto   = "VEHICLE_PHOTO"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nricFront:           return "NRIC (front)"
        case .nricBack:            return "NRIC (back)"
        case .selfie:              return "Selfie"
        case .drivingLicense:      return "Driving license"
        case .vehicleRegistration: return "Vehicle registration"
        case .insurance:           return "Insurance certificate"
        case .vehiclePhoto:        return "Vehicle photo"
        }
    }

    /// Required for any rider account — minimum proof of personhood.
    static let riderRequired: [KycDocumentKind] = [.nricFront, .nricBack, .selfie]

    /// Required additionally for a driver going live with a route.
    static let driverRequired: [KycDocumentKind] =
        riderRequired + [.drivingLicense, .vehicleRegistration, .insurance, .vehiclePhoto]
}

struct KycDocument: Codable, Identifiable, Equatable {
    var id: String
    var kind: KycDocumentKind
    /// Backend storage URL (S3/CDN). Local-only drafts can leave this nil.
    var storageUrl: String?
    var uploadedAt: Date
    var verifiedAt: Date?
    var rejectionReason: String?
}

struct KycSubmission: Codable, Equatable {
    var userId: String
    var role: Role
    var status: KycStatus
    var documents: [KycDocument]
    var lastUpdated: Date
    var rejectionReason: String?

    enum Role: String, Codable { case rider = "RIDER", driver = "DRIVER" }

    var requiredKinds: [KycDocumentKind] {
        role == .driver ? KycDocumentKind.driverRequired : KycDocumentKind.riderRequired
    }

    var isComplete: Bool {
        let uploaded = Set(documents.map(\.kind))
        return Set(requiredKinds).isSubset(of: uploaded)
    }

    var missingKinds: [KycDocumentKind] {
        let uploaded = Set(documents.map(\.kind))
        return requiredKinds.filter { !uploaded.contains($0) }
    }
}

// MARK: - Subscription tier (pricing §3.2)
//
// Tier governs renewal cadence and the discount the rider sees. The migration
// path is deliberately conservative: existing RouteSubscription rows keep
// their default tier (.monthly) and nothing changes until a tier is set
// explicitly.

enum SubscriptionTier: String, Codable, CaseIterable, Identifiable {
    case daily     = "DAILY"
    case monthly   = "MONTHLY"
    case quarterly = "QUARTERLY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily:     return "Daily"
        case .monthly:   return "Monthly"
        case .quarterly: return "Quarterly"
        }
    }

    /// Discount applied to the driver's per-seat list price for this tier.
    /// Daily is full price (try-before-you-commit); monthly gets 10% off;
    /// quarterly gets 15% off and becomes the default after first month.
    var discountFactor: Double {
        switch self {
        case .daily:     return 1.00
        case .monthly:   return 0.90
        case .quarterly: return 0.85
        }
    }

    /// Number of working days the tier represents for billing math.
    var billingWorkingDays: Int {
        switch self {
        case .daily:     return 1
        case .monthly:   return 22
        case .quarterly: return 66
        }
    }
}

// MARK: - Subscription pricing math
//
// Single source of truth for "how much does this subscription cost?" so the
// rider, the receipt, and the driver payout statement always agree.

enum SubscriptionPricing {
    /// Effective MYR/seat after the tier discount. Rounded to whole ringgit
    /// because the rest of the model carries integer MYR.
    static func discountedPricePerSeat(pricePerSeatMyr: Int, tier: SubscriptionTier) -> Int {
        let raw = Double(pricePerSeatMyr) * tier.discountFactor
        return max(1, Int(raw.rounded()))
    }

    /// Working days (Mon–Fri) within `[start, end]` inclusive. Caller can use
    /// this when the user picks an explicit date range; for tier-based
    /// signups, fall back to `tier.billingWorkingDays`.
    static func workingDaysBetween(_ start: Date, _ end: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        guard start <= end else { return 0 }
        var count = 0
        var cursor = cal.startOfDay(for: start)
        let stop = cal.startOfDay(for: end)
        while cursor <= stop {
            let weekday = cal.component(.weekday, from: cursor)
            if weekday >= 2 && weekday <= 6 { count += 1 } // Mon–Fri
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? stop.addingTimeInterval(86_400)
        }
        return count
    }

    /// Total MYR a rider pays for this tier × days × seat price.
    static func totalForTier(pricePerSeatMyr: Int, tier: SubscriptionTier, days: Int) -> Int {
        let perSeat = discountedPricePerSeat(pricePerSeatMyr: pricePerSeatMyr, tier: tier)
        let billable = max(1, min(days, tier.billingWorkingDays))
        return perSeat * billable
    }

    /// Money saved vs. paying daily for the same period. Useful for the
    /// "Daily would cost RM X — you're saving RM Y" upsell on the tier picker.
    static func savingsVsDaily(pricePerSeatMyr: Int, tier: SubscriptionTier, days: Int) -> Int {
        let dailyTotal = pricePerSeatMyr * max(1, min(days, tier.billingWorkingDays))
        let tierTotal = totalForTier(pricePerSeatMyr: pricePerSeatMyr, tier: tier, days: days)
        return max(0, dailyTotal - tierTotal)
    }
}

// MARK: - Cancellation & no-show policy (ops §5.3)
//
// The state machine of who-broke-it is deliberately separate from
// `CommuteRideStatus`. The ride can be COMPLETED while a CancellationRecord
// is still being adjudicated — keeping these orthogonal avoids tangling the
// rider's calendar with Trust & Safety workflow.

enum CancellationActor: String, Codable {
    case driver = "DRIVER"
    case rider  = "RIDER"
    case system = "SYSTEM"
}

enum CancellationKind: String, Codable {
    case driverCancelLate    = "DRIVER_CANCEL_LATE"     // <12h before departure
    case driverNoShow        = "DRIVER_NO_SHOW"
    case riderCancelMidMonth = "RIDER_CANCEL_MID_MONTH"
    case riderNoShow         = "RIDER_NO_SHOW"
    case forceMajeure        = "FORCE_MAJEURE"           // weather, accident, no penalty
}

struct CancellationRecord: Codable, Identifiable, Equatable {
    var id: String
    var rideInstanceId: String
    var subscriptionId: String?
    var routeId: String
    var actor: CancellationActor
    var kind: CancellationKind
    var reportedAt: Date
    var resolvedAt: Date?
    /// Penalty in MYR. Negative means refund-to-rider; positive means held
    /// from driver payout. Zero for no-fault / force majeure.
    var penaltyAmount: Int
    var notes: String?
}

/// Pure function: given the type of cancellation and the driver's recent
/// history, what does our policy say should happen?
///
/// Mirrors the playbook §5.3 table exactly so support / ops cannot apply a
/// different policy than the engineering implementation.
struct CancellationPolicyEngine {
    /// Number of late-cancels by this driver in the last 30 days.
    var driverLateCancelsLast30Days: Int

    /// Per-seat price on the route in MYR.
    var pricePerSeatMyr: Int

    func decide(kind: CancellationKind) -> Outcome {
        switch kind {
        case .driverCancelLate:
            switch driverLateCancelsLast30Days {
            case 0:  return Outcome(penaltyMyr: 0,                  driverActions: [.warning],                   riderActions: [])
            case 1:  return Outcome(penaltyMyr: 0,                  driverActions: [.pauseRoute48h],              riderActions: [.notifyAlternative])
            default: return Outcome(penaltyMyr: pricePerSeatMyr,    driverActions: [.dropStreakBonus, .lowerVisibleReliability],
                                    riderActions: [.fullRefund])
            }
        case .driverNoShow:
            return Outcome(penaltyMyr: pricePerSeatMyr / 2,
                           driverActions: [.holdHalfSeatFee, .lowerVisibleReliability],
                           riderActions: [.fullRefund, .notifyAlternative])
        case .riderCancelMidMonth:
            // 10% admin fee, capped at MYR 20.
            return Outcome(penaltyMyr: -min(20, pricePerSeatMyr / 10 * 22),
                           driverActions: [],
                           riderActions: [.proRatedRefundMinusAdminFee])
        case .riderNoShow:
            return Outcome(penaltyMyr: 0,
                           driverActions: [.markSeatTaken],
                           riderActions: [.noRefund])
        case .forceMajeure:
            return Outcome(penaltyMyr: 0,
                           driverActions: [],
                           riderActions: [.fullRefund])
        }
    }

    struct Outcome: Equatable {
        var penaltyMyr: Int
        var driverActions: [DriverAction]
        var riderActions: [RiderAction]
    }

    enum DriverAction: String, Codable {
        case warning
        case pauseRoute48h
        case dropStreakBonus
        case lowerVisibleReliability
        case holdHalfSeatFee
        case markSeatTaken
    }

    enum RiderAction: String, Codable {
        case notifyAlternative
        case fullRefund
        case proRatedRefundMinusAdminFee
        case noRefund
    }
}

// MARK: - Per-pickup-cluster reliability (engineering gap #10)
//
// A driver can be 95% on-time *overall* but 60% on-time at *your* pickup point.
// This was identified in the playbook as a churn-causing blind spot. We model
// it now so the matching engine can use it once we have data.

struct PickupClusterReliability: Codable, Equatable {
    var clusterId: String
    var onTimeRate: Double
    var ridesObserved: Int
}
