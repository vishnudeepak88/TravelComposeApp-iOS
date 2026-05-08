import Testing
@testable import TravelComposeApp

// MARK: - Phone normalization (Malaysian carriers)
//
// Two production bugs lived in this routine before the regression net
// existed: trailing-space autocorrect on the auth screen, and 9-digit
// Sabah/Sarawak numbers getting truncated when the leading-zero strip
// fired before the country-code strip. Tests exercise both, plus the
// E.164 happy path and a few obvious mis-paste shapes.

@Suite("Phone normalization")
struct PhoneNormalizationTests {

    @Test("Already-formatted international numbers pass through")
    func e164PassesThrough() {
        #expect(Voygo.normalizePhoneNumber("+60123456789") == "+60123456789")
        #expect(Voygo.normalizePhoneNumber("+1 555 123 4567") == "+15551234567")
    }

    @Test("Local 0-prefixed paste form gets +60")
    func localZeroPrefix() {
        #expect(Voygo.normalizePhoneNumber("0123456789")  == "+60123456789")
        #expect(Voygo.normalizePhoneNumber("012-3456789") == "+60123456789")
        #expect(Voygo.normalizePhoneNumber("012 345 6789") == "+60123456789")
    }

    @Test("Country-code-without-plus form gets +60")
    func sixtyPrefixWithoutPlus() {
        #expect(Voygo.normalizePhoneNumber("60123456789") == "+60123456789")
    }

    @Test("Bare local form gets +60")
    func bareLocal() {
        #expect(Voygo.normalizePhoneNumber("123456789") == "+60123456789")
    }

    @Test("9-digit Sabah/Sarawak numbers are not truncated")
    /// Regression: previous implementation stripped both the leading zero
    /// and the leading '60' even when '60' was actually part of the
    /// subscriber number (e.g. Kota Kinabalu landlines starting "60xxx"
    /// when prefixed with the trunk zero). The fix only strips '60' when
    /// it's at the very start of the cleaned string, before the
    /// leading-zero pass.
    func sabahSarawakNotTruncated() {
        // 088 is the Sabah area code; the 7-digit subscriber number
        // makes up a 9-digit local form.
        #expect(Voygo.normalizePhoneNumber("088234567") == "+6088234567")
    }

    @Test("Trailing spaces / autocorrect artifacts get trimmed")
    func trailingSpacesTrimmed() {
        #expect(Voygo.normalizePhoneNumber("0123456789 ") == "+60123456789")
        #expect(Voygo.normalizePhoneNumber(" 0123456789") == "+60123456789")
    }

    @Test("Empty / whitespace-only input returns empty string")
    func emptyInput() {
        #expect(Voygo.normalizePhoneNumber("") == "")
        #expect(Voygo.normalizePhoneNumber("   ") == "")
    }

    @Test("Non-digit garbage is filtered before normalization")
    func garbageFiltered() {
        #expect(Voygo.normalizePhoneNumber("abc 012-345-6789 xyz") == "+60123456789")
    }
}
