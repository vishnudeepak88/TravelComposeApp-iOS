import SwiftUI

// MARK: - V Polished Design System
// Mirrors the `V` token set + atoms used in the Voygo Prototype HTML/JSX.
// Lives alongside VoygoTheme so the original components keep working while
// new screens compose against this richer set.

enum VPalette {
    // Vibrant super-app palette — ported from the design handoff
    // (`car-pool/project/tokens.jsx`). Replaces the previous trust-forward
    // teal direction with energetic green primary + forest ink. See
    // `docs/REDESIGN.md` for the full mapping rationale.
    static let primary           = Color(hex: 0x00B14F)
    static let primaryDark       = Color(hex: 0x008F3F)
    static let primaryContainer  = Color(hex: 0xE5F7ED)
    static let onPrimary         = Color.white
    static let secondary         = Color(hex: 0x1F8A5C)
    static let secondaryContainer = Color(hex: 0xDBF1E5)
    static let accent            = Color(hex: 0x7B5CD6)
    static let accentContainer   = Color(hex: 0xEFE9FA)
    static let success           = Color(hex: 0x3A8F6F)
    static let successContainer  = Color(hex: 0xE0F0E8)
    static let warning           = Color(hex: 0xC77A3A)
    static let warningContainer  = Color(hex: 0xFFF4D1)
    static let danger            = Color(hex: 0xB84B4B)
    static let dangerContainer   = Color(hex: 0xFBE3E0)
    static let bg                = Color(hex: 0xF2F5F4)
    static let surface           = Color.white
    static let surfaceHigh       = Color(hex: 0xF7FAF8)
    // Forest-tinted hairline; `T.divider` from the design at ~7% alpha
    // over the `#0A2920` ink reads as a faint warm border — better
    // than the cold gray we had before.
    static let border            = Color(red: 10/255, green: 41/255, blue: 32/255, opacity: 0.07)
    static let outline           = Color(hex: 0xAEBDB7)
    static let text              = Color(hex: 0x0A2920)
    static let textSec           = Color(hex: 0x37514A)
    // Held at #5A6E74 instead of the design's lighter #7A8E88 — round-2
    // QA flagged the lighter value at ~3.6:1 contrast on the new
    // `#F2F5F4` bg, which fails WCAG 2.1 AA for body text. The redesign
    // doc covers this trade-off explicitly.
    static let textHint          = Color(hex: 0x5A6E74)
    static let starGold          = Color(hex: 0xFCD24A)

    // New accent tokens for service grids, promo banners, and "NEW" pills.
    static let accentCoral           = Color(hex: 0xFF6B6B)
    static let accentCoralContainer  = Color(hex: 0xFFE5E5)
    static let accentAmber           = Color(hex: 0xFFB800)
    static let accentAmberContainer  = Color(hex: 0xFFF4D1)
    // Alias of `accent` — clearer at service-tile callsites.
    static let accentPurple          = Color(hex: 0x7B5CD6)
    static let accentPurpleContainer = Color(hex: 0xEFE9FA)

    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primary, primaryDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var creditGradient: LinearGradient {
        // Deep sage → vibrant primary so the Wallet hero reads as
        // "money, but on-brand" rather than a separate visual island.
        LinearGradient(
            colors: [Color(hex: 0x0E5C3C), primary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

// MARK: - Atoms

/// Small uppercase pill (e.g. "ACTIVE", "VERIFIED", "EV").
struct VBadge: View {
    let text: String
    var color: Color = VPalette.primary
    var container: Color? = nil

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black))
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((container ?? color.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
            .foregroundColor(color)
    }
}

/// All-caps tracking-out micro label used as section kickers.
struct VKicker: View {
    let text: String
    var color: Color = VPalette.textHint
    var size: CGFloat = 11

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .black))
            .tracking(1.2)
            .foregroundColor(color)
    }
}

/// Gradient avatar circle used everywhere (driver hero, profile, chat header).
struct VAvatar: View {
    let initial: String
    var size: CGFloat = 44
    var accent: Color = VPalette.primary

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [accent, VPalette.secondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
    }
}

/// Primary action button — 54pt height, gradient-grade shadow.
struct VPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void

    init(_ title: String, icon: String? = nil, isLoading: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title).font(.system(size: 15, weight: .bold)).tracking(-0.2)
                    if let icon { Image(systemName: icon).font(.system(size: 15, weight: .bold)) }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isEnabled ? AnyShapeStyle(VPalette.primary) : AnyShapeStyle(VPalette.surfaceHigh))
            .foregroundColor(isEnabled ? .white : VPalette.textHint)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Glowing green CTA per the super-app spec
            // (`0 8px 22px rgba(0,177,79,0.35)`).
            .shadow(color: isEnabled ? VPalette.primary.opacity(0.35) : .clear, radius: 22, x: 0, y: 8)
        }
        .disabled(!isEnabled || isLoading)
    }
}

struct VSecondaryButton: View {
    let title: String
    var color: Color = VPalette.primary
    var action: () -> Void

    init(_ title: String, color: Color = VPalette.primary, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .foregroundColor(color)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Light card surface with hairline border — title slot is a kicker label.
struct VPolishedCard<Content: View>: View {
    let title: String?
    let action: String?
    var padded: Bool = true
    let content: Content

    init(title: String? = nil, action: String? = nil, padded: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.action = action
        self.padded = padded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack {
                    VKicker(text: title)
                    Spacer()
                    if let action {
                        Text(action)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(VPalette.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            if padded {
                content
                    .padding(.horizontal, title == nil ? 14 : 16)
                    .padding(.bottom, title == nil ? 14 : 14)
                    .padding(.top, title == nil ? 14 : 0)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VPalette.border, lineWidth: 1)
        )
    }
}

/// Polished nav header with optional back chip, optional kicker, big title, optional trailing.
struct VPolishedNavBar<Trailing: View>: View {
    let title: String
    var kicker: String? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(VPalette.text)
                        .frame(width: 40, height: 40)
                        .background(VPalette.surface)
                        .overlay(Circle().stroke(VPalette.border, lineWidth: 1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let kicker { VKicker(text: kicker, size: 10) }
                Text(title)
                    .font(.system(size: 22, weight: .black))
                    .tracking(-0.4)
                    .foregroundColor(VPalette.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

extension VPolishedNavBar where Trailing == EmptyView {
    init(title: String, kicker: String? = nil, onBack: (() -> Void)? = nil) {
        self.init(title: title, kicker: kicker, onBack: onBack, trailing: { EmptyView() })
    }
}

/// Circular icon chip used in the new Profile/Wallet/Notification rows.
struct VIconBubble: View {
    let systemName: String
    var color: Color = VPalette.primary
    var size: CGFloat = 32
    var iconSize: CGFloat = 14

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Pickup→drop vertical glyph (small dot + line + square).
struct VRouteGlyph: View {
    var dotColor: Color = VPalette.success
    var squareColor: Color = VPalette.primary
    var lineColor: Color = VPalette.border

    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(dotColor).frame(width: 9, height: 9)
            Rectangle().fill(lineColor).frame(width: 1.5).frame(maxHeight: .infinity)
                .padding(.vertical, 3)
            RoundedRectangle(cornerRadius: 2).fill(squareColor).frame(width: 10, height: 10)
        }
    }
}

/// iOS-style toggle styled in the V palette.
struct VToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: VPalette.primary))
    }
}

/// Faux map background with grid + diagonal road + pickup/drop pins.
struct VMapPlaceholder: View {
    enum Tone { case teal, indigo, cream, dark }
    var tone: Tone = .teal
    var label: String? = "Map"
    var height: CGFloat = 180

    private var palette: (bg: Color, line: Color, pin: Color, road: Color) {
        switch tone {
        case .teal:   return (Color(hex: 0xDBEAE3), Color(hex: 0xBCD1C8), VPalette.primary, Color(hex: 0x9BB5AB))
        case .indigo: return (Color(hex: 0xE6E3F2), Color(hex: 0xCDC9E0), Color(hex: 0x3B2F73), Color(hex: 0xA89DC4))
        case .cream:  return (Color(hex: 0xF1EDE4), Color(hex: 0xDFD9CB), Color(hex: 0x1A1A1A), Color(hex: 0xBDB6A4))
        case .dark:   return (Color(hex: 0x1A2226), Color(hex: 0x293439), Color(hex: 0x7CE0D1), Color(hex: 0x384850))
        }
    }

    var body: some View {
        let p = palette
        ZStack(alignment: .bottomTrailing) {
            p.bg

            // Grid
            Canvas { ctx, size in
                let step: CGFloat = 42
                var gridPath = Path()
                var x: CGFloat = 0
                while x < size.width { gridPath.move(to: .init(x: x, y: 0)); gridPath.addLine(to: .init(x: x, y: size.height)); x += step }
                var y: CGFloat = 0
                while y < size.height { gridPath.move(to: .init(x: 0, y: y)); gridPath.addLine(to: .init(x: size.width, y: y)); y += step }
                ctx.stroke(gridPath, with: .color(p.line), lineWidth: 1)

                // Diagonal road (rough quadratic curve)
                var road = Path()
                let h = size.height
                let w = size.width
                road.move(to: .init(x: -10, y: h * 0.7))
                road.addQuadCurve(to: .init(x: w * 0.5, y: h * 0.85), control: .init(x: w * 0.2, y: h * 0.5))
                road.addQuadCurve(to: .init(x: w + 10, y: h * 0.45), control: .init(x: w * 0.8, y: h * 0.95))
                ctx.stroke(road, with: .color(p.road.opacity(0.7)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                ctx.stroke(road, with: .color(p.bg.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 8]))
            }

            // Pickup pin (circle, lower-left)
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(p.pin)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .position(x: geo.size.width * 0.18, y: geo.size.height * 0.55)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(p.pin)
                        .frame(width: 18, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: 3))
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .position(x: geo.size.width * 0.78, y: geo.size.height * 0.32)
                }
            }

            if let label {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(p.pin.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
        .frame(height: height)
        .clipShape(Rectangle())
    }
}

// MARK: - Tab bar (custom, replaces the native TabView pill design)

struct VPolishedTabBar: View {
    enum Tab: Hashable { case routes, calendar, inbox, profile }
    @Binding var selection: Tab

    private struct Item: Identifiable {
        let id: Tab
        let label: String
        let icon: String
    }

    private let items: [Item] = [
        .init(id: .routes,   label: "Routes",   icon: "car.fill"),
        .init(id: .calendar, label: "Calendar", icon: "clock.fill"),
        .init(id: .inbox,    label: "Inbox",    icon: "bubble.left.fill"),
        .init(id: .profile,  label: "Profile",  icon: "person.fill")
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        selection = item.id
                    }
                } label: {
                    let on = item.id == selection
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 22, weight: on ? .bold : .regular))
                            .foregroundColor(on ? VPalette.primary : VPalette.textHint)
                        Text(item.label)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.2)
                            .foregroundColor(on ? VPalette.primary : VPalette.textHint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 28)
        .background(.ultraThinMaterial)
        .background(VPalette.surface.opacity(0.6))
        .overlay(Rectangle().fill(VPalette.border).frame(height: 1), alignment: .top)
    }
}

// MARK: - Helpers

/// Inline kicker + value stat block (used in Home hero and Profile).
struct VStatBlock: View {
    let value: String
    let label: String
    var color: Color = VPalette.primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .black))
                .tracking(-0.4)
                .foregroundColor(color)
            VKicker(text: label, size: 10)
        }
    }
}

/// Hero gradient card body used in Home / Booking Confirmed / Driver dashboard.
struct VHeroGradient<Content: View>: View {
    var corner: CGFloat = 22
    let content: Content

    init(corner: CGFloat = 22, @ViewBuilder content: () -> Content) {
        self.corner = corner
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VPalette.primaryGradient
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: 60, y: -80)
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: VPalette.primary.opacity(0.45), radius: 22, x: 0, y: 12)
    }
}
