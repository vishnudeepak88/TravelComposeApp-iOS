import SwiftUI

// MARK: - In-app language picker
//
// Lets the rider override the OS-level language without leaving the
// app. Three options:
//   1. Follow iPhone language (default — falls through to Bundle.main)
//   2. English (en_MY)
//   3. Bahasa Malaysia (ms_MY)
//
// The picked value is persisted in UserDefaults under
// `AppLocale.storageKey`. `RootView` watches the same key via
// `@AppStorage` and uses it as a SwiftUI `id` so changing the
// language hot-remounts the entire view tree — every `S.t(...)` call
// re-resolves against the new bundle without requiring a cold restart.

struct LanguageSettingsView: View {
    var onBack: () -> Void

    @AppStorage(AppLocale.storageKey) private var stored: String = AppLocale.system.rawValue

    private var selected: AppLocale {
        AppLocale(rawValue: stored) ?? .system
    }

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.langPickerTitle, onBack: onBack)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Subtitle explains the relationship to iPhone's
                        // language setting so the rider knows the in-app
                        // pref overrides it rather than fighting it.
                        Text(S.langPickerSubtitle)
                            .font(.caption)
                            .foregroundColor(VPalette.textSec)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)

                        VStack(spacing: 0) {
                            ForEach(Array(AppLocale.allCases.enumerated()), id: \.element) { idx, option in
                                row(option)
                                if idx < AppLocale.allCases.count - 1 {
                                    Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 16)
                                }
                            }
                        }
                        .background(VPalette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func row(_ option: AppLocale) -> some View {
        let isSelected = selected == option
        return Button {
            // Writing to @AppStorage fires RootView's id-change which
            // remounts the tree. We don't dismiss the picker — the
            // rider can verify the change live (this nav bar's title
            // flips immediately) before tapping back.
            stored = option.rawValue
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option == .system ? "iphone" :
                                  option == .en ? "textformat" : "textformat.alt")
                    .font(.subheadline.weight(.heavy))
                    .foregroundColor(isSelected ? VPalette.primary : VPalette.textSec)
                    .frame(width: 32, height: 32)
                    .background((isSelected ? VPalette.primary : VPalette.textSec).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(option.displayName)
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(VPalette.primary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("LanguageSettingsView") {
    LanguageSettingsView(onBack: {})
}
