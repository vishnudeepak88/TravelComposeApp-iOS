import SwiftUI

// MARK: - Design System (legacy aliases over the V token set)
//
// Originally `VoygoTheme` was a parallel design system with its own color
// values, dark-mode adaptive ramps, and component styling. The polished
// prototype work introduced `VPalette` (in Polished.swift) with the V tokens
// from the Voygo Polished design and the cleaner atom set (VPolishedCard,
// VPolishedNavBar, VPrimaryButton, VAvatar, VBadge, etc.).
//
// Two systems running side-by-side meant two visual languages on the same
// screen — the QA report flagged this as the single biggest "this feels
// unfinished" tell. Rather than rewrite every existing call site to use
// the new atoms, this file makes `VoygoTheme.*` source its values directly
// from `VPalette`, and re-skins the legacy components (VoygoCard,
// PrimaryButton, VoygoNavBar, VoygoTextField, StatusBadge, AvatarView,
// DayChip, SectionHeader) to match the polished look. Every screen using
// the legacy tokens or atoms gets the unified palette automatically with
// no per-screen edits.
//
// Trade-off: VoygoTheme used to support dark mode via `Color.adaptive`.
// VPalette is light-mode-only (the prototype was light-only). Dark mode
// is therefore disabled until the design intent is re-decided. The
// `Color.adaptive` helper stays in the file in case it's needed later.

struct VoygoTheme {
    // Brand
    static let primary           = VPalette.primary
    static let primaryDark       = VPalette.primaryDark
    static let primaryContainer  = VPalette.primaryContainer
    static let onPrimary         = VPalette.onPrimary
    static let onPrimaryContainer = VPalette.primary
    static let secondary         = VPalette.secondary
    static let secondaryContainer = VPalette.secondaryContainer
    static let accent            = VPalette.accent

    // Status
    static let success           = VPalette.success
    static let warning           = VPalette.warning
    static let danger            = VPalette.danger

    // Surfaces
    static let background        = VPalette.bg
    static let surface           = VPalette.surface
    static let surfaceHigh       = VPalette.surfaceHigh
    static let cardBorder        = VPalette.border
    static let outline           = VPalette.outline

    // Text
    static let textPrimary       = VPalette.text
    static let textSecondary     = VPalette.textSec
    static let textHint          = VPalette.textHint

    // Gradients
    static var primaryGradient: LinearGradient { VPalette.primaryGradient }
    static var cardGradient: LinearGradient {
        LinearGradient(colors: [VPalette.surface, VPalette.surface], startPoint: .top, endPoint: .bottom)
    }
}

// Held for future dark-mode revival; nothing currently calls into it.
private extension Color {
    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

// MARK: - Reusable Components — re-skinned to match VPolishedCard /
// VPrimaryButton / VAvatar / VBadge so legacy screens look unified
// without per-screen rewrites.

/// Card surface with hairline border + barely-there shadow. Matches
/// VPolishedCard so screens that mix the two atoms feel cohesive.
struct VoygoCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16
    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    var body: some View {
        content
            .background(VPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(VPalette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 54pt gradient-shadow primary action button. Matches VPrimaryButton.
struct PrimaryButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void
    init(_ title: String, isLoading: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title; self.isLoading = isLoading; self.isEnabled = isEnabled; self.action = action
    }
    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .tracking(-0.2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isEnabled ? VPalette.primary : VPalette.surfaceHigh)
            .foregroundColor(isEnabled ? .white : VPalette.textHint)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // Match VPrimaryButton — glowing green super-app CTA.
            .shadow(color: isEnabled ? VPalette.primary.opacity(0.35) : .clear, radius: 22, x: 0, y: 8)
        }
        .disabled(!isEnabled || isLoading)
    }
}

/// Outline-style secondary action — uses the polished container tint.
struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundColor(VPalette.primary)
                .background(VPalette.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct DestructiveButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundColor(VPalette.danger)
                .background(VPalette.dangerContainer)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

/// Polished input — matches the form rows on Profile / Wallet / KYC.
struct VoygoTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default
    var prefix: String? = nil
    var trailingIcon: String? = nil
    var isTrailingLoading = false
    var onTrailingTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(VPalette.textHint)
            HStack(spacing: 8) {
                if let prefix {
                    Text(prefix)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(VPalette.text)
                }
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .foregroundColor(VPalette.text)
                    .tint(VPalette.primary)
                if let trailingIcon, let onTrailingTap {
                    Button(action: onTrailingTap) {
                        ZStack {
                            if isTrailingLoading {
                                ProgressView().tint(VPalette.primary)
                            } else {
                                Image(systemName: trailingIcon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(VPalette.primary)
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .disabled(isTrailingLoading)
                    .accessibilityLabel("Use current location")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .background(VPalette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(VPalette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Pill chip — matches VBadge so a screen that opens a sheet with VBadge
/// alongside an existing StatusBadge doesn't show two visual languages.
struct StatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black))
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Gradient avatar — matches VAvatar so a screen mixing both renders one
/// look. The gradient direction matches the polished hero cards.
struct AvatarView: View {
    let initial: String
    var size: CGFloat = 44
    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [VPalette.primary, VPalette.secondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundColor(VPalette.textHint)
            Text(title)
                .font(.system(size: 15, weight: .heavy))
                .foregroundColor(VPalette.textSec)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(VPalette.textHint)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().tint(VPalette.primary).scaleEffect(1.3)
            Text("Loading…")
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(VPalette.textSec)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(VPalette.warning)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(VPalette.textSec)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// All-caps tracking-out micro label — same shape as VKicker so they read
/// the same on a screen that mixes both.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.2)
            .foregroundColor(VPalette.textHint)
            .padding(.horizontal, 4)
    }
}

/// Polished nav bar — single back chip, big title, optional trailing.
/// Matches VPolishedNavBar's typography (22pt black, -0.4 tracking).
struct VoygoNavBar: View {
    let title: String
    var showBack: Bool = false
    var onBack: (() -> Void)? = nil
    var trailingContent: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            if showBack, let back = onBack {
                Button(action: back) {
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
            Text(title)
                .font(.system(size: 22, weight: .black))
                .tracking(-0.4)
                .foregroundColor(VPalette.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let trailing = trailingContent {
                trailing.frame(minWidth: 40, minHeight: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(VPalette.bg)
    }
}

struct ReliabilityBar: View {
    let value: Double // 0..1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(VPalette.surfaceHigh)
                    .frame(height: 6)
                Capsule()
                    .fill(VPalette.primaryGradient)
                    .frame(width: geo.size.width * max(0, min(1, value)), height: 6)
            }
        }.frame(height: 6)
    }
}

/// Day chip — soft container fill when selected, hairline border. Matches
/// the polished schedule chips on Search Filters / Create Route.
struct DayChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .heavy))
                .frame(width: 38, height: 38)
                .foregroundColor(selected ? VPalette.primary : VPalette.textHint)
                .background(selected ? VPalette.primaryContainer : VPalette.surface)
                .overlay(
                    Circle().stroke(
                        selected ? VPalette.primary : VPalette.border,
                        lineWidth: 1
                    )
                )
                .clipShape(Circle())
        }
    }
}

struct StepperHeaderView: View {
    let currentStep: Int
    let totalSteps: Int
    let titles: [String]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<totalSteps, id: \.self) { i in
                let stepNum = i + 1
                let isDone = stepNum < currentStep
                let isActive = stepNum == currentStep
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isActive ? VPalette.primary : (isDone ? VPalette.success : VPalette.surfaceHigh))
                            .frame(width: 32, height: 32)
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundColor(.white)
                        } else {
                            Text("\(stepNum)")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundColor(isActive ? .white : VPalette.textHint)
                        }
                    }
                    Text(i < titles.count ? titles[i] : "")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isActive ? VPalette.primary : VPalette.textHint)
                }
                if i < totalSteps - 1 {
                    Rectangle()
                        .fill(isDone ? VPalette.success : VPalette.surfaceHigh)
                        .frame(height: 2)
                        .padding(.bottom, 18)
                }
            }
        }
    }
}

struct PlaceAutocompleteField: View {
    let label: String
    @Binding var text: String
    let suggestions: [PlaceSuggestion]
    let isLoading: Bool
    let onSuggestionTap: (PlaceSuggestion) -> Void
    var onCommit: (() -> Void)? = nil
    var trailingIcon: String? = nil
    var isTrailingLoading = false
    var onTrailingTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VoygoTextField(
                label: label,
                text: $text,
                trailingIcon: trailingIcon,
                isTrailingLoading: isTrailingLoading,
                onTrailingTap: onTrailingTap
            )
            if isLoading {
                HStack {
                    ProgressView().tint(VPalette.primary).padding(8)
                    Spacer()
                }
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { s in
                        Button(action: { onSuggestionTap(s) }) {
                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(VPalette.primary)
                                    .font(.system(size: 14, weight: .heavy))
                                Text(s.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(VPalette.text)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        Divider()
                            .background(VPalette.border)
                            .padding(.horizontal, 14)
                    }
                }
                .background(VPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(VPalette.border, lineWidth: 1)
                )
            }
        }
    }
}
