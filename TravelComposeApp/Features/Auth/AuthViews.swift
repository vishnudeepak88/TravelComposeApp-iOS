import SwiftUI
import AuthenticationServices

// MARK: - Auth Screens (mirrors AuthPhoneScreen.jsx + AuthOtpScreen.jsx in Voygo Prototype)

struct AuthPhoneView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    var onSent: (String) -> Void

    @State private var phone = ""
    @State private var isLoading = false
    /// Typed AppError so we can render a `VErrorBanner` that branches on
    /// the case (network → Retry; unauthorized → Sign in again; etc.)
    /// instead of a flat red string.
    @State private var error: AppError? = nil
    /// Surfaces Sign-in-with-Apple results to the user — succeeded /
    /// cancelled / failed — until the backend `/auth/apple` exchange
    /// endpoint lands.
    @State private var appleStatus: String? = nil

    /// SignInWithAppleButtonStyle — pick the variant that contrasts
    /// best with the current color scheme. White-on-dark in light
    /// mode, white-bordered on dark mode.
    private var siwaStyle: SignInWithAppleButton.Style {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(S.authBrandName)
                                .font(.largeTitle.weight(.black))
                                .tracking(-1.2)
                                .foregroundColor(VPalette.text)
                                .minimumScaleFactor(0.6)
                            Text(S.authTagline)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(VPalette.textSec)
                                .frame(maxWidth: 240, alignment: .leading)
                        }
                        Spacer()
                        ZStack {
                            VPalette.primaryGradient
                            Image(systemName: "car.fill").font(.title2).foregroundColor(.white).accessibilityHidden(true)
                        }
                        .frame(width: 58, height: 58)
                        .clipShape(Circle())
                        .shadow(color: VPalette.primary.opacity(0.55), radius: 18, x: 0, y: 8)
                    }

                    HStack(spacing: 8) {
                        featureChip(icon: "clock.fill",  label: S.authFeatureDailyRoutes)
                        featureChip(icon: "shield.fill", label: S.authFeatureTrustedDrivers)
                        featureChip(icon: "person.fill", label: S.authFeatureReserveSeats)
                    }

                    VStack(alignment: .center, spacing: 6) {
                        Text(S.enterPhone)
                            .font(.title3.weight(.bold))
                            .foregroundColor(VPalette.text)
                            .minimumScaleFactor(0.8)
                        Text(S.authPhoneCaption)
                            .font(.footnote)
                            .foregroundColor(VPalette.textSec)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        VKicker(text: S.authPhoneFieldLabel)
                        HStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Text("🇲🇾").font(.callout)
                                Text("+60").font(.subheadline.weight(.heavy))
                            }
                            .foregroundColor(VPalette.text)
                            .frame(height: 54)
                            .padding(.horizontal, 14)
                            .background(VPalette.surfaceHigh)
                            .overlay(Rectangle().fill(VPalette.border).frame(width: 1), alignment: .trailing)

                            TextField("12-3456789", text: $phone)
                                .keyboardType(.numberPad)
                                .textContentType(.telephoneNumber)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                                .font(.body.weight(.semibold))
                                .tint(VPalette.primary)
                                .foregroundColor(VPalette.text)
                                .padding(.horizontal, 14)
                                .frame(height: 54)
                                .submitLabel(.send)
                                .onSubmit {
                                    if phone.count >= 9 { sendOtp() }
                                }
                                .onChange(of: phone) { _, v in
                                    // Strip everything except digits, then
                                    // cap at 11. Pasting "+60 12-3456789"
                                    // from a contact lands as "60123456789"
                                    // — we deliberately keep the prefix
                                    // because normalizePhone collapses it.
                                    phone = String(v.filter(\.isNumber).prefix(11))
                                    error = nil
                                }
                        }
                        .background(VPalette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.primary, lineWidth: 1.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if let err = error {
                        VErrorBanner(error: err, onRetry: { sendOtp() })
                    }

                    VPrimaryButton(S.authSendOtp, isLoading: isLoading, isEnabled: phone.count >= 9) {
                        sendOtp()
                    }

                    // Sign in with Apple is wired in code (SwiftUI button +
                    // identity handler), but the actual sign-in capability
                    // requires the `com.apple.developer.applesignin`
                    // entitlement, which requires a paid Apple Developer
                    // Program team (Personal Team free accounts can't add
                    // this capability). The button stays gated behind
                    // `AppCapabilities.signInWithAppleAvailable` so:
                    //   - Personal Team builds compile and run cleanly
                    //   - Once the team upgrades + re-enables the
                    //     entitlement, flipping the flag surfaces SIWA
                    //     with zero further code changes.
                    if AppCapabilities.signInWithAppleAvailable {
                        HStack(spacing: 12) {
                            Rectangle().fill(VPalette.border).frame(height: 1)
                            Text(S.authOr)
                                .font(.caption.weight(.bold))
                                .foregroundColor(VPalette.textHint)
                            Rectangle().fill(VPalette.border).frame(height: 1)
                        }
                        .padding(.vertical, 4)

                        SignInWithAppleButton(
                            .signIn,
                            onRequest: { request in
                                request.requestedScopes = [.email]
                            },
                            onCompletion: { result in
                                handleAppleSignIn(result)
                            }
                        )
                        .signInWithAppleButtonStyle(siwaStyle)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHint(Text(S.authAppleSignInHint))

                        if let appleStatus {
                            Text(appleStatus)
                                .font(.caption)
                                .foregroundColor(VPalette.textSec)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                    }

                    // Real, tappable links — previously these were styled `Text`
                    // segments concatenated with `+` which can't be tapped, so
                    // riders had no way to read the policies they were agreeing
                    // to. PDPA + App Store review both flag this.
                    HStack(spacing: 4) {
                        Text(S.authTermsLead)
                            .foregroundColor(VPalette.textHint)
                        Link(S.authTermsLink,
                             destination: URL.staticURL("https://voygo.app/terms"))
                            .foregroundColor(VPalette.primary)
                            .fontWeight(.semibold)
                        Text(S.authTermsAnd)
                            .foregroundColor(VPalette.textHint)
                        Link(S.authPrivacyLink,
                             destination: URL.staticURL("https://voygo.app/privacy"))
                            .foregroundColor(VPalette.primary)
                            .fontWeight(.semibold)
                    }
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                    #if DEBUG
                    devShortcut
                    #endif
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
        }
    }

    #if DEBUG
    /// Dev-only shortcut into the authenticated home screen. Compiled out
    /// of release builds via the `#if DEBUG` guard, so the App Store binary
    /// will never see this UI or call `signInForDevelopment`.
    private var devShortcut: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Rectangle().fill(VPalette.border).frame(height: 1).frame(maxWidth: .infinity)
                Text("DEV ONLY")
                    .font(.caption2.weight(.black))
                    .tracking(1.4)
                    .foregroundColor(VPalette.textHint)
                Rectangle().fill(VPalette.border).frame(height: 1).frame(maxWidth: .infinity)
            }
            .padding(.top, 4)

            Button {
                store.signInForDevelopment()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "hammer.fill")
                        .font(.footnote.weight(.bold))
                    Text("Skip login → home screen")
                        .font(.footnote.weight(.heavy))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundColor(VPalette.accent)
                .background(VPalette.accent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(VPalette.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("Server-backed actions (subscribe, charge, KYC) won't work without a real session.")
                .font(.caption2)
                .foregroundColor(VPalette.textHint)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
    #endif

    /// Handle the Sign in with Apple completion. Pilot scope: capture
    /// the Apple credential and surface a "we'll wire backend exchange
    /// soon" status to the user — full `/auth/apple` exchange (verify
    /// identityToken, mint Voygo JWT) is a follow-up. The button is
    /// in the app now so:
    ///   - App Review can see SIWA is offered (boosts review tier)
    ///   - Privacy manifest's NSPrivacyTracking=false story matches
    ///     (Apple-relay email keeps the user's real address hidden)
    ///   - Real users can opt-in to a friction-free auth on day 1.
    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                appleStatus = S.authAppleCredentialMissing
                return
            }
            // Apple gives us:
            //   - .user      (stable opaque id; the only persistent value)
            //   - .email     (Apple-relay or real, only on first sign-in)
            //   - .identityToken (JWT we send to the backend for verification)
            //   - .authorizationCode (one-time code for refresh-token exchange)
            // For pilot we surface to the user that we received it;
            // backend exchange lands when `/auth/apple` ships.
            let suffix = String(credential.user.suffix(8))
            appleStatus = S.authAppleCredentialReceived(suffix)
            // Telemetry breadcrumb so we can measure how many users
            // attempt SIWA before backend exchange exists.
            Telemetry.track("auth.apple.credential_received")
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                // User cancelled — don't show an error banner, just clear.
                appleStatus = nil
            } else {
                appleStatus = S.authAppleSignInFailed(error.localizedDescription)
            }
        }
    }

    /// Shared by the Send-OTP button and the keyboard-Send return key.
    /// Disables itself if a request is already in flight (rapid taps).
    private func sendOtp() {
        guard !isLoading, phone.count >= 9 else { return }
        Task {
            isLoading = true
            let result = await store.requestOtp(phone: phone)
            switch result {
            case .success:
                error = nil
                // Staging fast-path: when SMS / email aren't configured
                // the backend echoes the OTP back as `devCode`. Skip
                // the manual code-entry screen and verify immediately
                // so signing in is one tap, not three. The OTP screen
                // is still presented if devCode is missing (i.e. real
                // SMS/email is wired up).
                if let dev = store.devOtpCode, !dev.isEmpty {
                    let verifyResult = await store.verifyOtp(code: dev)
                    isLoading = false
                    switch verifyResult {
                    case .success:
                        // RootView swaps to MainTabView automatically
                        // when isAuthenticated flips. Nothing to push.
                        return
                    case .failure(let err):
                        // Something went wrong with auto-verify — fall
                        // back to the manual OTP screen so the user
                        // can read the dev code + retype it.
                        error = err
                        onSent(phone)
                        return
                    }
                }
                isLoading = false
                onSent(phone)
            case .failure(let err):
                isLoading = false
                error = err
            }
        }
    }

    private func featureChip(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.subheadline.weight(.heavy))
            Text(label).font(.caption2.weight(.heavy))
        }
        .foregroundColor(VPalette.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(VPalette.primaryContainer)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct AuthOtpView: View {
    @Environment(AppStore.self) private var store
    let phoneNumber: String
    var onBack: () -> Void

    @State private var otp = ""
    @State private var isLoading = false
    @State private var isResending = false
    @State private var error: AppError? = nil
    @State private var timeLeft = 30
    /// Holds a reference to the running countdown task so we can cancel it
    /// in `.onDisappear`. The previous Timer.publish autoconnect leaked
    /// indefinitely after the view unmounted.
    @State private var countdownTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.authVerifyNumberNav, onBack: onBack)

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 18) {
                            ZStack {
                                Circle().fill(VPalette.primaryContainer).frame(width: 76, height: 76)
                                Image(systemName: "message.fill")
                                    .font(.title)
                                    .foregroundColor(VPalette.primary)
                            }
                            VStack(spacing: 6) {
                                Text(S.authOtpTitle)
                                    .font(.title3.weight(.black))
                                    .tracking(-0.4)
                                    .foregroundColor(VPalette.text)
                                Text(S.authOtpBody(phoneNumber))
                                    .font(.subheadline)
                                    .foregroundColor(VPalette.textSec)
                                    .multilineTextAlignment(.center)

                                if let dev = store.devOtpCode {
                                    Text(S.authOtpDevCode(dev))
                                        .font(.caption2.weight(.heavy))
                                        .foregroundColor(VPalette.textHint)
                                }
                            }
                        }
                        .padding(.top, 16)

                        otpField

                        if let err = error {
                            VErrorBanner(error: err, onRetry: { verify() })
                                .padding(.horizontal, 24)
                        }

                        VPrimaryButton(S.authVerify, isLoading: isLoading, isEnabled: otp.count == 6) {
                            verify()
                        }
                        .padding(.horizontal, 24)

                        Button {
                            Task {
                                isResending = true
                                let result = await store.requestOtp(phone: phoneNumber)
                                isResending = false
                                switch result {
                                case .success:
                                    timeLeft = 30
                                    error = nil
                                    // Restart the countdown — the previous
                                    // task drained to zero already.
                                    startCountdown()
                                case .failure(let e):
                                    // Don't reset the cooldown if the resend
                                    // failed — user shouldn't have to wait
                                    // 30s before retrying.
                                    error = e
                                }
                            }
                        } label: {
                            if timeLeft > 0 {
                                Text(S.authResendIn(timeLeft))
                                    .font(.footnote)
                                    .foregroundColor(VPalette.textHint)
                            } else {
                                Text(isResending ? S.authResending : S.authResendCode)
                                    .font(.footnote.weight(.heavy))
                                    .foregroundColor(VPalette.primary)
                            }
                        }
                        .disabled(timeLeft > 0 || isResending)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            if let dev = store.devOtpCode, otp.isEmpty {
                otp = dev
                // Belt-and-braces auto-verify: AuthPhoneView.sendOtp()
                // already short-circuits straight to verifyOtp when
                // devCode is set, but if a user arrives here via Resend
                // (devCode arrives later via Resend OTP screen flow)
                // or refreshes the OTP, kick off verify automatically.
                Task {
                    let result = await store.verifyOtp(code: dev)
                    if case .failure(let err) = result {
                        error = err
                    }
                }
            }
            startCountdown()
        }
        .onDisappear {
            // Cancel the countdown so we don't leak a Task firing 1Hz
            // updates against a deallocated state.
            countdownTask?.cancel()
            countdownTask = nil
        }
        // When the user taps Resend, AppStore.requestOtp updates devOtpCode
        // with the new code. Watch the published value so the field
        // auto-fills with the *new* OTP, not the stale one from first load.
        .onChange(of: store.devOtpCode) { _, newValue in
            guard let newCode = newValue, otp != newCode else { return }
            otp = newCode
            error = nil
        }
    }

    /// Replaces the previous `Timer.publish(...).autoconnect()` which
    /// never stopped. `Task.sleep` is cooperatively cancellable, so
    /// `.onDisappear` reliably tears it down.
    private func verify() {
        guard !isLoading, otp.count == 6 else { return }
        Task {
            isLoading = true
            let result = await store.verifyOtp(code: otp)
            isLoading = false
            if case .failure(let err) = result {
                error = err
            }
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task {
            while !Task.isCancelled && timeLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { if timeLeft > 0 { timeLeft -= 1 } }
            }
        }
    }

    private var otpField: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    let ch = i < otp.count ? String(otp[otp.index(otp.startIndex, offsetBy: i)]) : ""
                    let active = i == otp.count
                    let filled = !ch.isEmpty
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(filled ? VPalette.primaryContainer : VPalette.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(active || filled ? VPalette.primary : VPalette.border, lineWidth: 2)
                            )
                        if filled {
                            Text(ch)
                                .font(.system(.title3, design: .monospaced).weight(.black))
                                .foregroundColor(VPalette.primary)
                        } else if active {
                            Rectangle().fill(VPalette.primary).frame(width: 1.5, height: 22)
                        }
                    }
                    .frame(width: 44, height: 56)
                }
            }
            // Hidden TextField captures keyboard input. iOS auto-fill of
            // SMS one-time codes is wired via .textContentType(.oneTimeCode).
            TextField("", text: Binding(
                get: { otp },
                set: { newValue in
                    otp = String(newValue.filter(\.isNumber).prefix(6))
                    error = nil
                }
            ))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($otpFocused)
            .opacity(0.01)
            .frame(width: 0.01, height: 0.01)
        }
        // The previous `HStack(spacing: 8)` left dead zones between cells
        // where taps wouldn't focus the hidden field. Wrapping the whole
        // ZStack in a single tap target fixes that without changing the
        // visual spacing.
        .contentShape(Rectangle())
        .onTapGesture { otpFocused = true }
        .onAppear { otpFocused = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(S.authOtpA11yLabel))
        // Read back "3 of 6 entered" rather than the raw digits —
        // protects user privacy when VoiceOver is paired with a
        // speaker, and reduces verbal noise for sighted-with-VO
        // users.
        .accessibilityValue(Text(
            otp.isEmpty
                ? S.authOtpA11yEmpty
                : S.authOtpA11yEntered(otp.count)
        ))
        .accessibilityHint(Text(S.authOtpA11yHint))
    }

    @FocusState private var otpFocused: Bool
}

#Preview("AuthPhoneView") {
    AuthPhoneView { _ in }
        .environment(AppStore())
}

#Preview("AuthOtpView") {
    AuthOtpView(phoneNumber: "+60 11 2345 6789", onBack: {})
        .environment(AppStore())
}
