import SwiftUI

// MARK: - Auth Screens (mirrors AuthPhoneScreen.kt + AuthOtpScreen.kt)

struct AuthPhoneView: View {
    @EnvironmentObject var store: AppStore
    var onSent: (String) -> Void

    @State private var phone = ""
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        ZStack {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Welcome")

                ScrollView {
                    VStack(spacing: 28) {
                        Spacer(minLength: 120)

                        VStack(spacing: 8) {
                            Text("Enter your mobile number")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(VoygoTheme.textPrimary)
                            Text("We will send you a verification code")
                                .font(.subheadline)
                                .foregroundColor(VoygoTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }

                        VoygoTextField(label: "Phone Number", text: $phone, placeholder: "12-3456789",
                                       keyboardType: .phonePad, prefix: "+60")
                            .onChange(of: phone) { _, v in
                                phone = String(v.filter(\.isNumber).prefix(11))
                                error = nil
                            }

                        if let err = error {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill").foregroundColor(VoygoTheme.danger)
                                Text(err).font(.caption).foregroundColor(VoygoTheme.danger)
                                Spacer()
                            }
                        }

                        PrimaryButton("Send OTP", isLoading: isLoading, isEnabled: phone.count >= 9) {
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

                        Text("By continuing, you agree to Voygo's Terms of Service and Privacy Policy.")
                            .font(.caption2)
                            .foregroundColor(VoygoTheme.textHint)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

struct AuthOtpView: View {
    @EnvironmentObject var store: AppStore
    let phoneNumber: String
    var onBack: () -> Void

    @State private var otp = ""
    @State private var isLoading = false
    @State private var isResending = false
    @State private var error: String? = nil
    @State private var timeLeft = 30

    var body: some View {
        ZStack {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Verify Number", showBack: true, onBack: onBack)
                    .background(VoygoTheme.background)

                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 12) {
                            Image(systemName: "message.badge.filled.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(VoygoTheme.primaryGradient)
                                .padding(.top, 32)
                            Text("Verify Phone Number")
                                .font(.title2.bold()).foregroundColor(VoygoTheme.textPrimary)
                            Text("Enter the 6-digit code sent to \(phoneNumber)")
                                .font(.subheadline).foregroundColor(VoygoTheme.textSecondary).multilineTextAlignment(.center)
                            if let dev = store.devOtpCode {
                                Text("Dev mode code: \(dev)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(VoygoTheme.textHint)
                            }
                        }

                        // OTP input
                        VStack(alignment: .leading, spacing: 6) {
                            Text("OTP CODE")
                                .font(.caption.weight(.bold)).tracking(1.2).foregroundColor(VoygoTheme.textHint)
                            TextField("", text: $otp)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                .foregroundColor(VoygoTheme.textPrimary)
                                .tint(VoygoTheme.primary)
                                .onChange(of: otp) { _, v in
                                    otp = String(v.filter(\.isNumber).prefix(6))
                                    error = nil
                                }
                                .padding(.vertical, 18)
                                .background(VoygoTheme.surface)
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(otp.count == 6 ? VoygoTheme.primary : VoygoTheme.cardBorder, lineWidth: 1.5))
                        }

                        if let err = error {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill").foregroundColor(VoygoTheme.danger)
                                Text(err).font(.caption).foregroundColor(VoygoTheme.danger)
                                Spacer()
                            }
                        }

                        PrimaryButton("Verify", isLoading: isLoading, isEnabled: otp.count == 6) {
                            Task {
                                isLoading = true
                                let result = await store.verifyOtp(code: otp)
                                isLoading = false
                                if case .failure(let err) = result {
                                    error = err.localizedDescription
                                }
                                // Success transitions automatically via store.isAuthenticated.
                            }
                        }

                        Button(action: {
                            Task {
                                isResending = true
                                let result = await store.requestOtp(phone: phoneNumber)
                                isResending = false
                                switch result {
                                case .success:
                                    timeLeft = 30
                                    error = nil
                                case .failure(let err):
                                    error = err.localizedDescription
                                }
                            }
                        }) {
                            Text(timeLeft > 0 ? "Resend code in \(timeLeft)s" : (isResending ? "Resending..." : "Resend Code"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(timeLeft == 0 ? VoygoTheme.primary : VoygoTheme.textHint)
                        }
                        .disabled(timeLeft > 0 || isResending)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            // Pre-fill with the dev-mode OTP echoed by the backend so testing
            // doesn't require an SMS provider.
            if let dev = store.devOtpCode, otp.isEmpty { otp = dev }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if timeLeft > 0 { timeLeft -= 1 }
        }
    }
}

// MARK: - Rounded Corner Helper
struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
