---
name: ios-design-system-port
description: Port an HTML/JSX/Figma design into a SwiftUI design-token system — palette enum, atoms (badge, kicker, avatar, primary button, error banner), semantic Dynamic-Type fonts, and gradients. Use when starting from a designer's HTML mock or migrating between design directions.
---

## When to use

- A designer hands you an HTML/JSX prototype, a Figma file, or a
  screenshot deck and wants the tokens reflected in the app.
- You're mid-migration between two design systems (e.g. teal to
  vibrant green) and want every screen to flip from one source.
- You're adding Dynamic Type / semantic fonts to a system that
  currently uses `.font(.system(size: N, weight: .X))` literals.

## Prerequisites

- `ios-swiftui-bootstrap` already done (or equivalent).
- A `Color` ladder from the design (hex values for primary, surfaces,
  text, accents, semantic states).

## Recipe

### 1 · Token enum

Single source of truth, all hex inputs:

```swift
extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >>  8) & 0xff) / 255,
                  blue:  Double( hex        & 0xff) / 255,
                  opacity: 1)
    }
}

enum VPalette {
    static let primary           = Color(hex: 0x00B14F)
    static let primaryDark       = Color(hex: 0x008F3F)
    static let primaryContainer  = Color(hex: 0xE5F7ED)
    static let onPrimary         = Color.white
    // ... full ladder

    static let bg        = Color(hex: 0xF2F5F4)
    static let surface   = Color.white
    static let surfaceHigh = Color(hex: 0xF7FAF8)
    static let border    = Color(red: 10/255, green: 41/255, blue: 32/255, opacity: 0.07)
    static let text      = Color(hex: 0x0A2920)
    static let textSec   = Color(hex: 0x37514A)
    static let textHint  = Color(hex: 0x5A6E74)  // verify ≥ 4.5:1 vs `bg` for WCAG AA

    static let success   = Color(hex: 0x3A8F6F)
    static let warning   = Color(hex: 0xC77A3A)
    static let danger    = Color(hex: 0xB84B4B)
    static let starGold  = Color(hex: 0xFCD24A)

    static let accentCoral  = Color(hex: 0xFF6B6B)
    static let accentAmber  = Color(hex: 0xFFB800)
    static let accentPurple = Color(hex: 0x7B5CD6)

    static var primaryGradient: LinearGradient {
        LinearGradient(colors: [primary, primaryDark],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
```

**WCAG check for `textHint`:** any "muted" text color must hit at
least 4.5:1 contrast against `bg`. Verify with the WebAIM checker
before shipping. If the design picks a too-light hint, darken it
yourself and document the deviation.

### 2 · Atom set

Build these once; every screen uses them:

```swift
struct VBadge: View {                  // small uppercase pill
    let text: String
    var color: Color = VPalette.primary
    var container: Color? = nil
    var body: some View { /* … */ }
}

struct VKicker: View {                 // all-caps tracking-out section header
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

struct VAvatar: View {                 // gradient initial circle (brand-loud)
    let initial: String
    var size: CGFloat = 44
    var accent: Color = VPalette.primary
    // body uses primaryGradient on a Circle with white initial
}

struct HueAvatar: View {               // pastel initial circle (list rows)
    let name: String
    var hue: Double = 210
    var size: CGFloat = 36
}

struct VPolishedNavBar<Trailing: View>: View {
    let title: String
    var kicker: String? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing
}

struct VPrimaryButton: View {          // 54pt, glow shadow, haptic on tap
    let title: String
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void
    @State private var hapticTrigger: Int = 0

    var body: some View {
        Button { hapticTrigger &+= 1; action() } label: {
            Text(title)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(isEnabled ? AnyShapeStyle(VPalette.primary)
                                       : AnyShapeStyle(VPalette.surfaceHigh))
                .foregroundColor(isEnabled ? .white : VPalette.textHint)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: isEnabled ? VPalette.primary.opacity(0.35) : .clear,
                        radius: 22, x: 0, y: 8)
        }
        .disabled(!isEnabled || isLoading)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticTrigger)
    }
}

struct VErrorBanner: View {            // typed-error surface — see below
    let error: AppError
    var onRetry: (() -> Void)? = nil
    var onSignIn: (() -> Void)? = nil
}

struct VSkeleton: View {               // animated grey placeholder
    var height: CGFloat = 14
    var corner: CGFloat = 8
    @State private var phase: Double = 0
    // body: shimmer gradient on `surfaceHigh`
}
```

### 3 · `VErrorBanner` — typed-error surface

```swift
struct VErrorBanner: View {
    let error: AppError
    var onRetry: (() -> Void)? = nil
    var onSignIn: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(VPalette.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .heavy))
                Text(error.errorDescription ?? "Try again in a moment.")
                    .font(.system(size: 12))
                    .foregroundColor(VPalette.textSec)
            }
            Spacer()
            actionButton
        }
        .padding(12)
        .background(VPalette.dangerContainer)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var actionButton: some View {
        if case .unauthorized = error, let onSignIn { /* "Sign in" pill */ }
        else if isRetryable, let onRetry { /* "Retry" pill */ }
    }

    private var icon: String { /* per-case symbol */ }
    private var title: String { /* per-case title */ }
    private var isRetryable: Bool {
        switch error {
        case .unauthorized, .validation, .message: return false
        case .network, .server, .decoding: return true
        }
    }
}
```

### 4 · Semantic font ladder (Dynamic Type)

```swift
extension Font {
    static let vTitle      = Font.system(.title,    design: .default).weight(.black)
    static let vHeadline   = Font.system(.headline, design: .default).weight(.heavy)
    static let vBodyHeavy  = Font.system(.body,     design: .default).weight(.heavy)
    static let vBody       = Font.system(.body,     design: .default)
    static let vCaption    = Font.system(.caption,  design: .default)
    static let vMonoSmall  = Font.system(.caption,  design: .monospaced).weight(.heavy)
}
```

Sweep callsites mechanically:

| Was | Becomes |
|---|---|
| `.font(.system(size: 28, weight: .black))` | `.font(.vTitle)` |
| `.font(.system(size: 18, weight: .heavy))` | `.font(.vHeadline)` |
| `.font(.system(size: 13, weight: .heavy))` | `.font(.vBodyHeavy)` |
| `.font(.system(size: 13))` | `.font(.vBody)` |
| `.font(.system(size: 11))` | `.font(.vCaption)` |
| `.font(.system(size: 14, design: .monospaced).weight(.heavy))` | `.font(.vMonoSmall)` |

Drop bespoke `.tracking(...)` — semantic fonts manage their own
metrics. Test at AX1 + AX5; budget time for `monospaced` numbers
running out of horizontal space (use `.minimumScaleFactor(0.7)`).

### 5 · Localization via `Strings.swift`

Centralize copy through `NSLocalizedString` with English fallbacks:

```swift
enum S {
    static var homeBookARide: String { t("home.bookARide", "Book a ride") }
    static func subscribeAndPay(amount: Int) -> String {
        let template = t("subscribe.payCTA", "Subscribe & pay RM %d")
        return String(format: template, amount)
    }
    private static func t(_ key: String, _ value: String) -> String {
        NSLocalizedString(key, value: value, comment: "")
    }
}
```

Add a `PBXVariantGroup` for `Localizable.strings` with `en.lproj`
(source) and one or more target locales. Missing keys fall back to
the English literal so partial translation passes never blank the UI.

## Pitfalls

- **`textHint` contrast** — common mistake to copy a too-light gray
  from the design. Always check WCAG AA (≥ 4.5:1 for body, ≥ 3:1 for
  large text) against your `bg`.
- **Two competing nav-bar components.** If you migrate from a legacy
  `Bar1` to a new `Bar2`, delete `Bar1` after the last call site
  flips. Otherwise both will drift visually over time.
- **Bespoke `.tracking()` on semantic fonts.** Tracking values are
  designed for specific point sizes; semantic fonts scale with
  Dynamic Type, so the tracking drifts visually. Drop it.
- **Hard-coded RGB hex everywhere.** Any color literal that's not in
  the palette enum is a token leak. Grep for `Color(hex:` after
  big migrations.

## Adjacent skills

- `ios-swiftui-bootstrap` — chrome (NavigationStack, AppRoute) the
  atoms are styled inside.
- `ios-ux-audit-and-fix` — the audit doc that documents the
  before/after of a migration.

## Reference implementation

Voygo at commit `599dd5b`:
- `TravelComposeApp/Core/Polished.swift` — `VPalette` + every atom
  in this skill (~600 lines, single file).
- `TravelComposeApp/Core/Strings.swift` + `Resources/{en,ms}.lproj/`
  — localization scaffold.
- `docs/REDESIGN.md` — pre-migration palette mapping doc; useful
  template for the next migration.
