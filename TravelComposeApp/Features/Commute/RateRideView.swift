import SwiftUI

// MARK: - Rate & Review (mirrors RateRideScreen.jsx)

struct RateRideView: View {
    let driverInitial: String
    let driverName: String
    let routeSummary: String
    let dateLabel: String
    let durationLabel: String
    var onSubmit: (Int, [String], Int) -> Void
    /// Pop one level — go back to LiveTrip. Bound to the chevron.
    var onBack: () -> Void = {}
    /// Skip rating entirely and pop to root. Bound to the visible
    /// "Skip" pill in the trailing nav slot. Previously the chevron
    /// did this implicitly which surprised users.
    var onSkip: () -> Void

    @State private var rating: Int = 5
    @State private var selectedTags: Set<String> = ["On time", "Smooth driving", "Friendly"]
    @State private var tip: Int = 5

    private let tagOptions = ["On time", "Smooth driving", "Friendly", "Clean car", "Good music", "Quiet ride"]

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Rate your ride", onBack: onBack) {
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(VPalette.textSec)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(VPalette.surfaceHigh)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip rating")
                }
                ScrollView {
                    VStack(spacing: 22) {
                        header
                        stars
                        tagsSection
                        tipSection
                        noteSection
                        VPrimaryButton("Submit review") {
                            onSubmit(rating, Array(selectedTags), tip)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        VStack(spacing: 10) {
            VAvatar(initial: driverInitial, size: 86)
            Text("How was your ride with \(driverName)?")
                .font(.system(size: 18, weight: .heavy))
                .tracking(-0.3)
                .foregroundColor(VPalette.text)
                .multilineTextAlignment(.center)
            Text("\(routeSummary) · \(dateLabel) · \(durationLabel)")
                .font(.system(size: 12)).foregroundColor(VPalette.textSec)
        }
    }

    private var stars: some View {
        VStack(spacing: 10) {
            // Whole row is exposed as a single accessibility element
            // with `.adjustable` trait — VoiceOver users can swipe up/
            // down to change the rating instead of having to tap five
            // separate buttons. Standard pattern for star raters.
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { i in
                    Button { rating = i } label: {
                        ZStack {
                            Circle()
                                .fill(i <= rating ? Color(hex: 0xFFF8DC) : VPalette.surfaceHigh)
                                .frame(width: 48, height: 48)
                                .overlay(Circle().strokeBorder(i <= rating ? VPalette.starGold : VPalette.border, lineWidth: 1.5))
                            Image(systemName: "star.fill")
                                .font(.system(size: 22))
                                .foregroundColor(i <= rating ? VPalette.starGold : VPalette.outline)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true) // grouped on the HStack below
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Ride rating"))
            .accessibilityValue(Text("\(rating) of 5 stars"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: rating = min(5, rating + 1)
                case .decrement: rating = max(1, rating - 1)
                @unknown default: break
                }
            }
            Text(verdict)
                .font(.subheadline.weight(.heavy))
                .foregroundColor(VPalette.success)
        }
    }

    private var verdict: String {
        switch rating {
        case 5: return "⭐ Excellent · 5/5"
        case 4: return "Great ride · 4/5"
        case 3: return "Decent · 3/5"
        case 2: return "Not great · 2/5"
        case 1: return "Poor · 1/5"
        default: return ""
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VKicker(text: "What stood out")
            FlowLayout(spacing: 8) {
                ForEach(tagOptions, id: \.self) { tag in
                    let on = selectedTags.contains(tag)
                    Button {
                        if on { selectedTags.remove(tag) } else { selectedTags.insert(tag) }
                    } label: {
                        HStack(spacing: 6) {
                            if on {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                            }
                            Text(tag).font(.system(size: 12, weight: .bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundColor(on ? .white : VPalette.textSec)
                        .background(on ? VPalette.primary : VPalette.surface)
                        .overlay(Capsule().stroke(on ? Color.clear : VPalette.border))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                VKicker(text: "Add a tip")
                Text("· 100% goes to \(driverName)")
                    .font(.system(size: 12))
                    .foregroundColor(VPalette.textSec)
            }
            HStack(spacing: 8) {
                ForEach([2, 5, 10, -1], id: \.self) { val in
                    let label = val == -1 ? "Custom" : "RM \(val)"
                    let on = val == tip
                    Button { if val != -1 { tip = val } } label: {
                        Text(label)
                            .font(.system(size: val == -1 ? 13 : 16, weight: .heavy))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundColor(on ? VPalette.primary : VPalette.text)
                            .background(on ? VPalette.primaryContainer : VPalette.surface)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? VPalette.primary : VPalette.border, lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                VKicker(text: "Note")
                Text("· optional").font(.system(size: 12)).foregroundColor(VPalette.textSec)
            }
            VStack(alignment: .leading) {
                Text("Always punctual and the EV ride is super smooth — already looking forward to Monday.")
                    .font(.system(size: 13))
                    .foregroundColor(VPalette.textSec)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .background(VPalette.surfaceHigh)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Tiny flow layout (for tag chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > w {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: w == .infinity ? 0 : w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

#Preview("RateRideView") {
    RateRideView(
        driverInitial: "A",
        driverName:    "Aiman",
        routeSummary:  "Subang Jaya → KLCC",
        dateLabel:     "8 May",
        durationLabel: "52 min",
        onSubmit:      { _, _, _ in },
        onBack:        {},
        onSkip:        {}
    )
    .environment(AppStore())
}
