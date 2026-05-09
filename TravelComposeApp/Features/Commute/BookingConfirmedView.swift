import SwiftUI

// MARK: - Booking Confirmation (mirrors BookingConfirmedScreen.jsx)

struct BookingConfirmedView: View {
    let bookingId: String
    let pickup: String
    let driverName: String
    var onViewReceipt: () -> Void
    var onSeeSubscription: () -> Void
    /// Pop-to-root closer. Confirmation screens shouldn't have a back
    /// chevron (the previous screen was the payment sheet, returning
    /// there is wrong) but they MUST have *some* exit other than the
    /// two CTAs — earlier UX audit flagged this as a P0 dead-end.
    /// Wired to `path = []` from `AppRouteDestinations`.
    var onDone: () -> Void = {}

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    detail
                        .padding(.horizontal, 16)
                        .offset(y: -20)
                    whatsNext
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    actions
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 30)
                }
            }
            // Done pill in the top-right of the hero. Floats over the
            // gradient so it stays visible even when the user scrolls.
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
            }
            .padding(.top, 56)
            .padding(.trailing, 16)
        }
        .navigationBarHidden(true)
    }

    private var hero: some View {
        ZStack(alignment: .top) {
            VPalette.primaryGradient
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 60)
                .offset(y: -100)

            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(.white.opacity(0.22))
                        .frame(width: 88, height: 88)
                        .overlay(Circle().stroke(.white.opacity(0.45), lineWidth: 2))
                    Image(systemName: "checkmark")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 60)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 8)

                VKicker(text: "You're in", color: .white.opacity(0.92))
                    .padding(.top, 12)

                Text("Subscription confirmed")
                    .font(.system(size: 28, weight: .black))
                    .tracking(-0.8)
                    .foregroundColor(.white)

                Group {
                    Text("\(driverName) will pick you up at ")
                        .foregroundColor(.white.opacity(0.92))
                    + Text(pickup).fontWeight(.heavy).foregroundColor(.white)
                }
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .padding(.bottom, 40)
                .padding(.horizontal, 24)
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    VKicker(text: "Subscription", size: 10)
                    Text("Subang Jaya → KLCC")
                        .font(.system(size: 17, weight: .heavy)).tracking(-0.3).foregroundColor(VPalette.text)
                    Text("Booking #\(bookingId)")
                        .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                VBadge(text: "Active", color: VPalette.success, container: VPalette.successContainer)
            }

            HStack {
                stack("First ride", value: "Mon, Jun 17", sub: "07:42 AM", subMono: true)
                divider()
                stack("Days", value: "Mon–Fri", sub: "20 rides/mo")
                divider()
                stack("Total / mo", value: "RM 280", sub: "Save RM 80", valueColor: VPalette.primary, subColor: VPalette.success)
            }
            .padding(14)
            .background(VPalette.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                Text("💳").font(.system(size: 20))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Charged to DuitNow · Maybank ··4221")
                        .font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.primary)
                    Text("First charge on Jun 17 — auto-renews monthly")
                        .font(.system(size: 11)).foregroundColor(VPalette.primary.opacity(0.85))
                }
                Spacer()
            }
            .padding(12)
            .background(VPalette.primaryContainer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 22, y: 8)
    }

    private func stack(_ label: String, value: String, sub: String, subMono: Bool = false, valueColor: Color = VPalette.text, subColor: Color = VPalette.textSec) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            VKicker(text: label, size: 10)
            Text(value).font(.system(size: 15, weight: .heavy)).foregroundColor(valueColor)
            Text(sub)
                .font(.system(size: 11, weight: subMono ? .semibold : .semibold, design: subMono ? .monospaced : .default))
                .foregroundColor(subColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func divider() -> some View {
        Rectangle().fill(VPalette.border).frame(width: 1, height: 44)
    }

    private var whatsNext: some View {
        VStack(alignment: .leading, spacing: 8) {
            VKicker(text: "What's next").padding(.leading, 4)
            ForEach(items, id: \.title) { row in
                HStack(spacing: 12) {
                    Text(row.icon).font(.system(size: 17))
                        .frame(width: 36, height: 36)
                        .background(row.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                        Text(row.subtitle).font(.system(size: 11)).foregroundColor(VPalette.textSec)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(VPalette.textHint)
                }
                .padding(12)
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            }
        }
        .padding(.top, 20)
    }

    private struct NextRow {
        let icon: String
        let title: String
        let subtitle: String
        let color: Color
    }

    /// Generic CTAs anchored on the actual booking. Earlier copy
    /// referenced specific times ("Daily 7:42 AM") and seats ("1 seat
    /// left") that were aspirational; keeping the list cards but with
    /// honest, action-shaped subtitles instead.
    private var items: [NextRow] {
        [
            .init(icon: "📍", title: "Add a backup pickup", subtitle: "Set a fallback in case you miss \(pickup)", color: VPalette.accent),
            .init(icon: "📅", title: "Sync to your calendar", subtitle: "Pickup events with the driver's contact info", color: VPalette.secondary),
            .init(icon: "👥", title: "Invite a colleague", subtitle: "Refer someone to ride with \(driverName)", color: VPalette.primary)
        ]
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onViewReceipt) {
                Text("View receipt")
                    .font(.system(size: 14, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundColor(VPalette.text)
                    .background(VPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(VPalette.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            VPrimaryButton("See subscription", action: onSeeSubscription)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview("BookingConfirmedView") {
    BookingConfirmedView(
        bookingId:        "demo-123",
        pickup:           "USJ 9 LRT",
        driverName:       "Aiman",
        onViewReceipt:    {},
        onSeeSubscription:{},
        onDone:           {}
    )
    .environment(AppStore())
}
