import Foundation

// MARK: - Long-haul (one-off inter-city trips)
//
// Orthogonal to the recurring-routes commute product. A driver posts a
// single trip ("KL → Penang, Friday 6pm, 3 seats, RM 60/seat"); riders
// book N seats in one shot. Payments reuse the Billplz subscription
// pipeline server-side (`tier="LONGHAUL"`, `subscription_id=null`),
// so the `Payment` model on the iOS side already covers it without
// a parallel ledger.

struct LongHaulTrip: Identifiable, Codable, Equatable {
    var id: String
    var driverId: String
    var driverName: String?
    var driverPhone: String?
    var driverRating: Double?
    var origin: String
    var destination: String
    var departAt: Date
    var seatsTotal: Int
    var seatsAvailable: Int
    var pricePerSeatMyr: Int
    var status: String
    var notes: String

    var isOpen: Bool { status == "OPEN" && seatsAvailable > 0 }
}

struct LongHaulBooking: Identifiable, Codable, Equatable {
    var id: String
    var tripId: String
    var seats: Int
    var status: String
    var paymentId: String?
    var origin: String
    var destination: String
    var departAt: Date
    var pricePerSeatMyr: Int
    var driverName: String?
    var driverPhone: String?

    var totalMyr: Int { pricePerSeatMyr * seats }
}

/// Response from `POST /longhaul/trips/:id/book`. The `payment` block
/// re-uses the existing `PaymentChargeResult` so the rider can be
/// routed straight into Billplz hosted-checkout when applicable.
struct LongHaulBookingResponse: Decodable {
    var bookingId: String
    var tripId: String
    var seats: Int
    var amountMyr: Int
    var payment: PaymentChargeResult
}
