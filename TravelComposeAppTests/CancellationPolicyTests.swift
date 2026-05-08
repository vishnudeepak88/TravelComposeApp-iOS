import Testing
@testable import TravelComposeApp

// MARK: - Cancellation policy engine
//
// The state machine here is what the support team will reach for when a
// rider disputes a charge or a driver disputes a payout. Engineering and
// ops MUST agree on every cell of this matrix; tests pin the behavior so
// a refactor can't quietly change a penalty without flipping a test red.
//
// Mirrors the playbook §5.3 table.

@Suite("Cancellation policy")
struct CancellationPolicyTests {

    // MARK: Driver late cancel — escalating penalty by 30-day count

    @Test("First driver late-cancel: warning, no penalty")
    func driverLateCancelFirstOffense() {
        let engine = CancellationPolicyEngine(driverLateCancelsLast30Days: 0, pricePerSeatMyr: 14)
        let outcome = engine.decide(kind: .driverCancelLate)
        #expect(outcome.penaltyMyr == 0)
        #expect(outcome.driverActions == [.warning])
        #expect(outcome.riderActions.isEmpty)
    }

    @Test("Second driver late-cancel: 48h pause, alternative offered to rider")
    func driverLateCancelSecondOffense() {
        let engine = CancellationPolicyEngine(driverLateCancelsLast30Days: 1, pricePerSeatMyr: 14)
        let outcome = engine.decide(kind: .driverCancelLate)
        #expect(outcome.penaltyMyr == 0)
        #expect(outcome.driverActions == [.pauseRoute48h])
        #expect(outcome.riderActions == [.notifyAlternative])
    }

    @Test("Third+ driver late-cancel: full per-seat penalty + reliability hit")
    func driverLateCancelRepeatOffender() {
        let engine = CancellationPolicyEngine(driverLateCancelsLast30Days: 2, pricePerSeatMyr: 14)
        let outcome = engine.decide(kind: .driverCancelLate)
        #expect(outcome.penaltyMyr == 14)
        #expect(outcome.driverActions == [.dropStreakBonus, .lowerVisibleReliability])
        #expect(outcome.riderActions == [.fullRefund])
    }

    // MARK: Driver no-show

    @Test("Driver no-show withholds half the seat fee")
    func driverNoShow() {
        let engine = CancellationPolicyEngine(driverLateCancelsLast30Days: 0, pricePerSeatMyr: 14)
        let outcome = engine.decide(kind: .driverNoShow)
        #expect(outcome.penaltyMyr == 7) // 14 / 2
        #expect(outcome.driverActions == [.holdHalfSeatFee, .lowerVisibleReliability])
        #expect(outcome.riderActions == [.fullRefund, .notifyAlternative])
    }

    // MARK: Rider mid-month cancel

    @Test("Rider mid-month cancel: 10% admin fee, capped at MYR 20")
    func riderMidMonthCancel() {
        // For RM 14 seat: 14 / 10 * 22 = 30.8 → cap at 20. Penalty is
        // negative (refund-to-rider less the fee).
        let engine = CancellationPolicyEngine(driverLateCancelsLast30Days: 0, pricePerSeatMyr: 14)
        let outcome = engine.decide(kind: .riderCancelMidMonth)
        #expect(outcome.penaltyMyr == -20)
        #expect(outcome.riderActions == [.proRatedRefundMinusAdminFee])
    }

    @Test("Rider no-show: no penalty, driver keeps the seat fee")
    func riderNoShow() {
        let engine = CancellationPolicyEngine(driverLateCancelsLast30Days: 0, pricePerSeatMyr: 14)
        let outcome = engine.decide(kind: .riderNoShow)
        #expect(outcome.penaltyMyr == 0)
        #expect(outcome.driverActions == [.markSeatTaken])
        #expect(outcome.riderActions == [.noRefund])
    }

    @Test("Force majeure: no penalty, full refund to rider")
    func forceMajeure() {
        let engine = CancellationPolicyEngine(driverLateCancelsLast30Days: 5, pricePerSeatMyr: 14)
        let outcome = engine.decide(kind: .forceMajeure)
        #expect(outcome.penaltyMyr == 0)
        #expect(outcome.driverActions.isEmpty)
        #expect(outcome.riderActions == [.fullRefund])
    }
}
