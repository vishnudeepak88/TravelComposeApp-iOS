import SwiftUI

// MARK: - Auth Screens (mirrors AuthPhoneScreen.jsx + AuthOtpScreen.jsx in Voygo Prototype)

struct AuthPhoneView: View {
    @Environment(AppStore.self) private var store
    var onSent: (String) -> Void

    @State private var phone = ""
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Voygo")
                                .font(.system(size: 40, weight: .black))
                                .tracking(-1.2)
                                .foregroundColor(VPalette.text)
                            Text("Your recurring commute, made dependable")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(VPalette.textSec)
                                .frame(maxWidth: 240, alignment: .leading)
                        }
                        Spacer()
                        ZStack {
                            VPalette.primaryGradient
                            Image(systemName: "car.fill").font(.system(size: 26)).foregroundColor(.white)
                        }
                        .frame(width: 58, height: 58)
                        .clipShape(Circle())
                        .shadow(color: VPalette.primary.opacity(0.55), radius: 18, x: 0, y: 8)
                    }

                    HStack(spacing: 8) {
                        featureChip(icon: "clock.fill",  label: "Daily routes")
                        featureChip(icon: "shield.fill", label: "Trusted drivers")
                        featureChip(icon: "person.fill", label: "Reserve seats")
                    }

                    VStack(alignment: .center, spacing: 6) {
                        Text("Enter your mobile number")
                            .font(.system(size: 20, weight: .bold)).foregroundColor(VPalette.text)
                        Text("We'll send a verification code")
                            .font(.system(size: 13)).foregroundColor(VPalette.textSec)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        VKicker(text: "Phone number")
                        HStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Text("🇲🇾").font(.system(size: 16))
                                Text("+60").font(.system(size: 15, weight: .heavy))
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
                                .font(.system(size: 17, weight: .semibold))
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
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundColor(VPalette.danger)
                            Text(err).font(.system(size: 12)).foregroundColor(VPalette.danger)
                        }
                    }

                    VPrimaryButton("Send OTP", isLoading: isLoading, isEnabled: phone.count >= 9) {
                        sendOtp()
                    }

                    Group {
                        Text("By continuing, you agree to Voygo's ")
                            .foregroundColor(VPalette.textHint)
                        + Text("Terms").foregroundColor(VPalette.primary).fontWeight(.semibold)
                        + Text(" and ").foregroundColor(VPalette.textHint)
                        + Text("Privacy Policy").foregroundColor(VPalette.primary).fontWeight(.semibold)
                        + Text(".").foregroundColor(VPalette.textHint)
                    }
                    .font(.system(size: 11))
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
                    .font(.system(size: 9, weight: .black))
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
                        .font(.system(size: 13, weight: .bold))
                    Text("Skip login → home screen")
                        .font(.system(size: 13, weight: .heavy))
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
                .font(.system(size: 10))
                .foregroundColor(VPalette.textHint)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
    #endif

    /// Shared by the Send-OTP button and the keyboard-Send return key.
    /// Disables itself if a request is already in flight (rapid taps).
    private func sendOtp() {
        guard !isLoading, phone.count >= 9 else { return }
        Task {
            isLoading = true
            let result = await store.requestOtp(phone: phone)
            isLoading = false
            switch result {
            case .success:
                error = nil
                onSent(phone)
            case .failure(let err):
                error = err.localizedDescription
            }
        }
    }

    private func featureChip(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 14, weight: .heavy))
            Text(label).font(.system(size: 11, weight: .heavy))
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
    @State private var error: String? = nil
    @State private var timeLeft = 30
    /// Holds a reference to the running countdown task so we can cancel it
    /// in `.onDisappear`. The previous Timer.publish autoconnect leaked
    /// indefinitely after the view unmounted.
    @State private var countdownTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Verify Number", onBack: onBack)

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 18) {
                            ZStack {
                                Circle().fill(VPalette.primaryContainer).frame(width: 76, height: 76)
                                Image(systemName: "message.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(VPalette.primary)
                            }
                            VStack(spacing: 6) {
                                Text("Verify Phone Number")
                                    .font(.system(size: 22, weight: .black))
                                    .tracking(-0.4)
                                    .foregroundColor(VPalette.text)
                                Group {
                                    Text("Enter the 6-digit code sent to ")
                                    + Text(phoneNumber).fontWeight(.heavy).foregroundColor(VPalette.text)
                                }
                                .font(.system(size: 14))
                                .foregroundColor(VPalette.textSec)
                                .multilineTextAlignment(.center)

                                if let dev = store.devOtpCode {
                                    Text("Dev code: \(dev)")
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundColor(VPalette.textHint)
                                }
                            }
                        }
                        .padding(.top, 16)

                        otpField

                        if let err = error {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill").foregroundColor(VPalette.danger)
                                Text(err).font(.system(size: 12)).foregroundColor(VPalette.danger)
                            }
                        }

                        VPrimaryButton("Verify", isLoading: isLoading, isEnabled: otp.count == 6) {
                            Task {
                                isLoading = true
                                let result = await store.verifyOtp(code: otp)
                                isLoading = false
                                if case .failure(let err) = result {
                                    error = err.localizedDescription
                                }
                            }
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
                                    error = e.localizedDescription
                                }
                            }
                        } label: {
                            if timeLeft > 0 {
                                (Text("Resend code in ").foregroundColor(VPalette.textHint)
                                 + Text("0:\(String(format: "%02d", timeLeft))").fontWeight(.heavy).foregroundColor(VPalette.text))
                                    .font(.system(size: 13))
                            } else {
                                Text(isResending ? "Resending…" : "Resend Code")
                                    .font(.system(size: 13, weight: .heavy))
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
            if let dev = store.devOtpCode, otp.isEmpty { otp = dev }
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
                                .font(.system(size: 22, weight: .black, design: .monospaced))
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
        .accessibilityLabel("OTP code")
        .accessibilityValue(otp.isEmpty ? "Empty" : otp)
    }

    @FocusState private var otpFocused: Bool
}
