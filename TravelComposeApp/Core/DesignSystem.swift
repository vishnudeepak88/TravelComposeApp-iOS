import SwiftUI

// MARK: - Design System

struct VoygoTheme {
    // KL Morning Commute palette.
    static let primary      = Color.adaptive(light: 0x0E6B62, dark: 0x7CE0D1)
    static let onPrimary    = Color.adaptive(light: 0xFFFFFF, dark: 0x073B36)
    static let primaryContainer = Color.adaptive(light: 0xD7F2EA, dark: 0x164E48)
    static let onPrimaryContainer = Color.adaptive(light: 0x12302D, dark: 0xD7F2EA)
    static let secondary    = Color.adaptive(light: 0x47736C, dark: 0xA9D4CC)
    static let secondaryContainer = Color.adaptive(light: 0xE2F0EC, dark: 0x244B46)
    static let accent       = Color.adaptive(light: 0x2E7D72, dark: 0x8FE6D7)
    static let success      = Color.adaptive(light: 0x2F855A, dark: 0x8ED9AD)
    static let warning      = Color.adaptive(light: 0xC27803, dark: 0xF6C85F)
    static let danger       = Color.adaptive(light: 0xC53030, dark: 0xFFB4AB)

    static let background   = Color.adaptive(light: 0xF7FAF8, dark: 0x102522)
    static let surface      = Color.adaptive(light: 0xFFFFFF, dark: 0x183530)
    static let surfaceHigh  = Color.adaptive(light: 0xE7F3EF, dark: 0x244B46)
    static let cardBorder   = Color.adaptive(light: 0xC9DCD6, dark: 0x3D665F)
    static let outline      = Color.adaptive(light: 0x6D8A84, dark: 0x90B8B0)

    static let textPrimary  = Color.adaptive(light: 0x12302D, dark: 0xE7F3EF)
    static let textSecondary = Color.adaptive(light: 0x47736C, dark: 0xA9D4CC)
    static let textHint     = Color.adaptive(light: 0x6D8A84, dark: 0xC7DED8).opacity(0.82)

    // Gradient
    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var cardGradient: LinearGradient {
        LinearGradient(colors: [surface, surface], startPoint: .top, endPoint: .bottom)
    }
}

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

// MARK: - Reusable Components

struct VoygoCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16
    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(VoygoTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(VoygoTheme.cardBorder.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)
            )
    }
}

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
                if isLoading { ProgressView().tint(.white) }
                else { Text(title).fontWeight(.semibold) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(isEnabled ? VoygoTheme.primary : VoygoTheme.primary.opacity(0.45))
            .foregroundColor(isEnabled ? VoygoTheme.onPrimary : VoygoTheme.onPrimary.opacity(0.6))
            .cornerRadius(12)
        }
        .disabled(!isEnabled || isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 12).stroke(VoygoTheme.outline, lineWidth: 1))
                .foregroundColor(VoygoTheme.primary)
        }
    }
}

struct DestructiveButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 12).stroke(VoygoTheme.danger, lineWidth: 1))
                .foregroundColor(VoygoTheme.danger)
        }
    }
}

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
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(VoygoTheme.textSecondary)
            HStack {
                if let prefix { Text(prefix).foregroundColor(VoygoTheme.primary).fontWeight(.semibold) }
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .foregroundColor(VoygoTheme.textPrimary)
                    .tint(VoygoTheme.primary)
                if let trailingIcon, let onTrailingTap {
                    Button(action: onTrailingTap) {
                        ZStack {
                            if isTrailingLoading {
                                ProgressView()
                                    .tint(VoygoTheme.primary)
                            } else {
                                Image(systemName: trailingIcon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(VoygoTheme.primary)
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .disabled(isTrailingLoading)
                    .accessibilityLabel("Use current location")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(VoygoTheme.surface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VoygoTheme.outline.opacity(0.7), lineWidth: 1))
        }
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

struct AvatarView: View {
    let initial: String
    var size: CGFloat = 44
    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .bold))
            .frame(width: size, height: size)
            .background(VoygoTheme.secondaryContainer)
            .foregroundColor(VoygoTheme.onPrimaryContainer)
            .clipShape(Circle())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundColor(VoygoTheme.textHint)
            Text(title).font(.headline).foregroundColor(VoygoTheme.textSecondary)
            Text(subtitle).font(.subheadline).foregroundColor(VoygoTheme.textHint).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().tint(VoygoTheme.primary).scaleEffect(1.4)
            Text("Loading…").font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundColor(VoygoTheme.warning)
            Text(message).font(.subheadline).foregroundColor(VoygoTheme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundColor(VoygoTheme.textHint)
            .padding(.horizontal, 4)
    }
}

struct VoygoNavBar: View {
    let title: String
    var showBack: Bool = false
    var onBack: (() -> Void)? = nil
    var trailingContent: AnyView? = nil
    var body: some View {
        HStack {
            if showBack, let back = onBack {
                Button(action: back) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(VoygoTheme.textPrimary)
                        .frame(width: 44, height: 44)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Spacer()
            Text(title).font(.title3.weight(.semibold)).foregroundColor(VoygoTheme.textPrimary).lineLimit(1)
            Spacer()
            if let trailing = trailingContent { trailing.frame(width: 44, height: 44) }
            else { Color.clear.frame(width: 44, height: 44) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(VoygoTheme.background)
    }
}

struct ReliabilityBar: View {
    let value: Double // 0..1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(VoygoTheme.surface).frame(height: 6)
                RoundedRectangle(cornerRadius: 4).fill(VoygoTheme.primary).frame(width: geo.size.width * value, height: 6)
            }
        }.frame(height: 6)
    }
}

struct DayChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.bold))
                .frame(width: 36, height: 36)
                .background(selected ? VoygoTheme.primary : VoygoTheme.surfaceHigh)
                .foregroundColor(selected ? .white : VoygoTheme.textSecondary)
                .clipShape(Circle())
                .overlay(Circle().stroke(selected ? VoygoTheme.primary : VoygoTheme.cardBorder, lineWidth: 1))
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
                            .fill(isActive ? VoygoTheme.primary : (isDone ? VoygoTheme.success : VoygoTheme.surfaceHigh))
                            .frame(width: 32, height: 32)
                        if isDone {
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundColor(.white)
                        } else {
                            Text("\(stepNum)").font(.caption.weight(.bold))
                                .foregroundColor(isActive ? .white : VoygoTheme.textHint)
                        }
                    }
                    Text(i < titles.count ? titles[i] : "").font(.caption2).foregroundColor(isActive ? VoygoTheme.primary : VoygoTheme.textHint)
                }
                if i < totalSteps - 1 {
                    Rectangle().fill(isDone ? VoygoTheme.success : VoygoTheme.surfaceHigh).frame(height: 2).padding(.bottom, 18)
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
                HStack { ProgressView().tint(VoygoTheme.primary).padding(8); Spacer() }
                    .background(VoygoTheme.surface).cornerRadius(10)
            } else if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { s in
                        Button(action: { onSuggestionTap(s) }) {
                            HStack {
                                Image(systemName: "mappin.circle.fill").foregroundColor(VoygoTheme.primary).font(.subheadline)
                                Text(s.displayName).font(.subheadline).foregroundColor(VoygoTheme.textPrimary).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        }
                        Divider().background(VoygoTheme.cardBorder).padding(.horizontal, 14)
                    }
                }
                .background(VoygoTheme.surface).cornerRadius(10)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
        }
    }
}
