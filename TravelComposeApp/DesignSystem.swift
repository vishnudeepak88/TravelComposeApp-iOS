import SwiftUI

// MARK: - Design System

struct VoygoTheme {
    // Brand Colors
    static let primary      = Color(hue: 0.62, saturation: 0.82, brightness: 0.92)   // Rich violet-blue
    static let primaryDark  = Color(hue: 0.64, saturation: 0.88, brightness: 0.72)
    static let accent       = Color(hue: 0.52, saturation: 0.78, brightness: 0.96)   // Teal accent
    static let success      = Color(hue: 0.38, saturation: 0.72, brightness: 0.82)
    static let warning      = Color(hue: 0.10, saturation: 0.85, brightness: 0.95)
    static let danger       = Color(hue: 0.02, saturation: 0.80, brightness: 0.88)

    // Backgrounds
    static let background   = Color(hue: 0.65, saturation: 0.04, brightness: 0.07)   // Near-black
    static let surface      = Color(hue: 0.65, saturation: 0.06, brightness: 0.12)
    static let surfaceHigh  = Color(hue: 0.65, saturation: 0.08, brightness: 0.17)
    static let cardBorder   = Color.white.opacity(0.07)

    // Text
    static let textPrimary  = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textHint     = Color.white.opacity(0.30)

    // Gradient
    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [primary, primaryDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var cardGradient: LinearGradient {
        LinearGradient(colors: [surface, surfaceHigh], startPoint: .top, endPoint: .bottom)
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
                    .fill(VoygoTheme.surfaceHigh)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(VoygoTheme.cardBorder, lineWidth: 1))
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
            .padding(.vertical, 16)
            .background(isEnabled ? VoygoTheme.primaryGradient : LinearGradient(colors: [VoygoTheme.surfaceHigh], startPoint: .leading, endPoint: .trailing))
            .foregroundColor(isEnabled ? .white : VoygoTheme.textHint)
            .cornerRadius(14)
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
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).stroke(VoygoTheme.primary, lineWidth: 1.5))
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
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).stroke(VoygoTheme.danger, lineWidth: 1.5))
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(VoygoTheme.surface)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(VoygoTheme.cardBorder, lineWidth: 1))
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
            .background(VoygoTheme.primaryGradient)
            .foregroundColor(.white)
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
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(VoygoTheme.primary)
                        .frame(width: 36, height: 36)
                        .background(VoygoTheme.surfaceHigh)
                        .clipShape(Circle())
                }
            }
            Spacer()
            Text(title).font(.headline.weight(.bold)).foregroundColor(VoygoTheme.textPrimary)
            Spacer()
            if let trailing = trailingContent { trailing }
            else { Color.clear.frame(width: 36, height: 36) }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct ReliabilityBar: View {
    let value: Double // 0..1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).fill(VoygoTheme.surface).frame(height: 6)
                RoundedRectangle(cornerRadius: 4).fill(VoygoTheme.success).frame(width: geo.size.width * value, height: 6)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VoygoTextField(label: label, text: $text)
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
