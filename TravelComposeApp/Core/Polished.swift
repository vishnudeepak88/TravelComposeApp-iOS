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

    @State private var hapticTrigger: Int = 0

    var body: some View {
        Button {
            // Primary CTAs are the highest-stakes taps in the app
            // (Subscribe & pay, Send OTP, Submit review). A short
            // medium-strength impact gives confirmation without
            // being intrusive — modern iOS apps universally do this.
            hapticTrigger &+= 1
            action()
        } label: {
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
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
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

// (Legacy `VMapPlaceholder` removed — every callsite now uses
// `VRouteDiagram` from `Core/RouteDiagram.swift`.)

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

// MARK: - Tab bar safe-area
//
// `VoygoTabBar` floats above the home indicator at ~80–88pt total
// height. Every tab root used to set its own `padding(.bottom, X)`
// with hand-tuned values (96, 108, 110) that drifted as the bar
// design changed. One constant + one modifier — change once, every
// tab adapts.

enum VTabBarLayout {
    /// Visible content height of the floating tab bar (icon + label +
    /// vertical padding) PLUS extra clearance for the home indicator.
    /// Adjust this if the bar's chrome changes.
    static let clearance: CGFloat = 110
}

extension View {
    /// Reserves bottom padding so floating tab bar doesn't overlap the
    /// last row of scrolled content. Apply at the bottom of any
    /// `ScrollView` whose parent is a tab root.
    func tabBarClearance() -> some View {
        self.padding(.bottom, VTabBarLayout.clearance)
    }
}

// MARK: - Skeleton placeholder
//
// Page-shaped grey shimmer for primary loading states. SwiftUI alone
// can't do a moving gradient on a single view at consistent speed, so
// we phase a `.repeatForever(autoreverses: true)` mask on top of a
// solid grey rectangle.

struct VSkeleton: View {
    var height: CGFloat = 14
    var corner: CGFloat = 8
    @State private var phase: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(VPalette.surfaceHigh)
            .frame(height: height)
            .overlay(
                LinearGradient(
                    colors: [
                        VPalette.surfaceHigh.opacity(0.0),
                        VPalette.text.opacity(0.04),
                        VPalette.surfaceHigh.opacity(0.0)
                    ],
                    startPoint: UnitPoint(x: phase - 0.4, y: 0.5),
                    endPoint:   UnitPoint(x: phase + 0.4, y: 0.5)
                )
                .blendMode(.plusDarker)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Typed-error banner
//
// Surfaces `AppError` cases with case-aware copy + retry behavior.
// Most call sites used to show `Text(err.localizedDescription)` in
// red, which lost the structural meaning of the typed enum we
// introduced in commit 34aaea9. This banner restores that:
//   .unauthorized → "Sign in again" (no retry)
//   .network      → "Offline" (with retry)
//   .validation   → "Check your input" (no retry)
//   .server       → "Server error" (with retry)
//   .decoding     → "Unexpected response" (with retry)
//   .message      → catch-all "Something went wrong"

struct VErrorBanner: View {
    let error: AppError
    var onRetry: (() -> Void)? = nil
    var onSignIn: (() -> Void)? = nil

    /// Convenience for legacy call sites that store the error as a
    /// composed `String` (e.g. "Payment failed (X) and pause also
    /// failed: Y. Try again."). Wraps the message into
    /// `AppError.message(...)` so the typed branching still works:
    /// these are always non-retryable composed strings, so the
    /// banner renders icon + title + the message verbatim.
    init(message: String,
         onRetry: (() -> Void)? = nil,
         onSignIn: (() -> Void)? = nil) {
        self.error = .message(message)
        self.onRetry = onRetry
        self.onSignIn = onSignIn
    }

    /// Primary init taking a typed `AppError`. Default retry/sign-in
    /// closures are nil so the banner just displays a non-actionable
    /// alert; pass them when the view knows how to retry.
    init(error: AppError,
         onRetry: (() -> Void)? = nil,
         onSignIn: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
        self.onSignIn = onSignIn
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(VPalette.danger)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(VPalette.text)
                Text(error.errorDescription ?? "Try again in a moment.")
                    .font(.system(size: 12))
                    .foregroundColor(VPalette.textSec)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            actionButton
        }
        .padding(12)
        .background(VPalette.dangerContainer)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(VPalette.danger.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actionButton: some View {
        if case .unauthorized = error, let onSignIn {
            Button(action: onSignIn) {
                Text("Sign in")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(VPalette.primary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(VPalette.primaryContainer)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else if isRetryable, let onRetry {
            Button(action: onRetry) {
                Text("Retry")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(VPalette.primary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(VPalette.primaryContainer)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var icon: String {
        switch error {
        case .unauthorized: return "lock.slash.fill"
        case .network:      return "wifi.slash"
        case .server:       return "exclamationmark.icloud.fill"
        case .decoding:     return "arrow.triangle.2.circlepath"
        case .validation, .message: return "exclamationmark.triangle.fill"
        }
    }

    private var title: String {
        switch error {
        case .unauthorized: return "Sign in again"
        case .network:      return "You're offline"
        case .validation:   return "Check your input"
        case .server:       return "Server error"
        case .decoding:     return "Unexpected response"
        case .message:      return "Something went wrong"
        }
    }

    private var isRetryable: Bool {
        switch error {
        case .unauthorized, .validation, .message: return false
        case .network, .server, .decoding:         return true
        }
    }
}

// MARK: - Dynamic-Type-aware semantic font ladder
//
// Most of the existing `.font(.system(size: N))` literals don't scale
// with iOS Dynamic Type — large-text users see the same 11pt the
// designer drew. These wrappers hand the OS a semantic role so the
// system can scale within reason while preserving the design weight.
//
// Use sites convert mechanically:
//   .font(.system(size: 28, weight: .black))    → .font(.vTitle)
//   .font(.system(size: 18, weight: .heavy))    → .font(.vHeadline)
//   .font(.system(size: 13, weight: .heavy))    → .font(.vBodyHeavy)
//   .font(.system(size: 13))                    → .font(.vBody)
//   .font(.system(size: 11))                    → .font(.vCaption)
//   .font(.system(size: 14, design: .monospaced).weight(.heavy))
//                                              → .font(.vMonoSmall)
//
// Bespoke `.tracking(...)` is intentionally dropped — visually a wash
// at scale, accessibility cheaper to maintain.

extension Font {
    static let vTitle      = Font.system(.title,    design: .default).weight(.black)
    static let vHeadline   = Font.system(.headline, design: .default).weight(.heavy)
    static let vBodyHeavy  = Font.system(.body,     design: .default).weight(.heavy)
    static let vBody       = Font.system(.body,     design: .default)
    static let vCaption    = Font.system(.caption,  design: .default)
    static let vMonoSmall  = Font.system(.caption,  design: .monospaced).weight(.heavy)
}
