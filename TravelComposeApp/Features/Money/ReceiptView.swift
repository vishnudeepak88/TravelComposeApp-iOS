import SwiftUI

// MARK: - Receipt (mirrors ReceiptScreen.jsx)

struct ReceiptView: View {
    let bookingId: String
    var onBack: () -> Void

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Receipt", onBack: onBack) {
                    Button {} label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(VPalette.primary)
                            .frame(width: 40, height: 40)
                            .background(VPalette.primaryContainer)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    VStack(spacing: 14) {
                        receiptCard
                        actions
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var receiptCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Voygo")
                    .font(.system(size: 22, weight: .black))
                    .tracking(-0.4)
                    .foregroundColor(VPalette.primary)
                Text("Booking #\(bookingId) · Completed")
                    .font(.system(size: 11, weight: .bold)).tracking(0.4)
                    .foregroundColor(VPalette.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(VPalette.primaryContainer)

            DashedLine()

            VMapPlaceholder(tone: .teal, label: "14 Jun · 52 min · 18.4 km", height: 140)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VRouteGlyph().frame(height: 64)
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 1) {
                            VKicker(text: "Pickup · 7:42 AM", color: VPalette.success, size: 10)
                            Text("USJ 9 LRT, Subang Jaya").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            VKicker(text: "Drop · 8:34 AM", color: VPalette.primary, size: 10)
                            Text("KLCC Tower B, Kuala Lumpur").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 18)

                DashedLine().padding(.vertical, 16)

                HStack(spacing: 10) {
                    VAvatar(initial: "A", size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Aiman Z.").font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.text)
                        Text("Tesla Model 3 · VEC 4123").font(.system(size: 10)).foregroundColor(VPalette.textSec)
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").foregroundColor(VPalette.starGold).font(.system(size: 12))
                        Text("5.0").font(.system(size: 12, weight: .bold)).foregroundColor(VPalette.text)
                    }
                }

                DashedLine().padding(.vertical, 16)

                VKicker(text: "Fare breakdown")
                    .padding(.bottom, 4)

                lineItem("Base fare (subscription)", value: "RM 14.00")
                lineItem("Voygo credit", value: "−RM 2.50", color: VPalette.success)
                lineItem("Tolls covered", value: "Included")

                Rectangle().fill(VPalette.border).frame(height: 1).padding(.vertical, 10)

                HStack {
                    Text("Total charged").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    Spacer()
                    Text("RM 11.50")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .tracking(-0.5)
                        .foregroundColor(VPalette.primary)
                }
                Text("DuitNow · Maybank ··4221")
                    .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                DashedLine().padding(.vertical, 16)

                HStack(alignment: .top, spacing: 12) {
                    QRPlaceholder().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        VKicker(text: "Verification", size: 10)
                        Text(bookingId)
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(VPalette.text)
                        Text("For expense reimbursement")
                            .font(.system(size: 10))
                            .foregroundColor(VPalette.textSec)
                    }
                    Spacer()
                }
            }
            .padding(18)
        }
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border, lineWidth: 1))
    }

    private func lineItem(_ label: String, value: String, color: Color = VPalette.text) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundColor(VPalette.textSec)
            Spacer()
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(color)
        }
        .padding(.vertical, 4)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {} label: {
                Text("Email PDF")
                    .font(.system(size: 13, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundColor(VPalette.text)
                    .background(VPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VPalette.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }.buttonStyle(.plain)
            Button {} label: {
                Text("Add to expenses")
                    .font(.system(size: 13, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundColor(VPalette.primary)
                    .background(VPalette.primaryContainer)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }.buttonStyle(.plain)
        }
    }
}

private struct DashedLine: View {
    var body: some View {
        Rectangle()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
            .foregroundColor(VPalette.border)
    }
}

private struct QRPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(VPalette.text, lineWidth: 2)
            // Pseudo-QR: fixed grid squares for a deterministic, readable look.
            Canvas { ctx, size in
                let cols = 7
                let pad: CGFloat = 6
                let cell = (min(size.width, size.height) - pad * 2) / CGFloat(cols)
                let pattern: [[Int]] = [
                    [1,1,1,0,1,1,1],
                    [1,0,1,1,1,0,1],
                    [1,1,1,0,0,1,1],
                    [0,1,0,1,0,1,0],
                    [1,1,0,0,1,0,1],
                    [1,0,1,1,1,0,1],
                    [1,1,1,0,1,1,0]
                ]
                for r in 0..<cols {
                    for c in 0..<cols where pattern[r][c] == 1 {
                        let rect = CGRect(
                            x: pad + CGFloat(c) * cell,
                            y: pad + CGFloat(r) * cell,
                            width: cell - 1, height: cell - 1
                        )
                        ctx.fill(Path(rect), with: .color(VPalette.text))
                    }
                }
            }
            .padding(2)
        }
    }
}
