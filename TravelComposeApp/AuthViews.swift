import SwiftUI

// MARK: - Auth Screens (mirrors AuthPhoneScreen.kt + AuthOtpScreen.kt)

struct AuthPhoneView: View {
    var onSendOtp: (String) -> Void

    @State private var phone = ""
    @State private var isLoading = false
    @State private var error: String? = nil

    var body: some View {
        ZStack {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Hero top
                ZStack {
                    VoygoTheme.primaryGradient.ignoresSafeArea(edges: .top)
                    VStack(spacing: 12) {
                        Spacer().frame(height: 60)
                        Image(systemName: "car.2.fill")
                            .font(.system(size: 58, weight: .bold))
                            .foregroundColor(.white)
                        Text("Voygo")
                            .font(.system(size: 36, weight: .black))
                            .foregroundColor(.white)
                        Text("Your daily commute, simplified.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                        Spacer().frame(height: 36)
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedCorner(radius: 32, corners: [.bottomLeft, .bottomRight]))

                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 8) {
                            Text("Welcome back")
                                .font(.title2.bold())
                                .foregroundColor(VoygoTheme.textPrimary)
                            Text("Enter your Malaysia mobile number to continue")
                                .font(.subheadline)
                                .foregroundColor(VoygoTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 32)

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
                            isLoading = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isLoading = false
                                onSendOtp(phone)
                            }
                        }

                        Text("By continuing, you agree to Voygo's Terms of Service and Privacy Policy.")
                            .font(.caption2)
                            .foregroundColor(VoygoTheme.textHint)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

struct AuthOtpView: View {
    let phoneNumber: String
    var onVerify: (String) -> Void
    var onBack: () -> Void

    @State private var otp = ""
    @State private var isLoading = false
    @State private var timeLeft = 30

    var body: some View {
        ZStack {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Verify Number", showBack: true, onBack: onBack)
                    .background(VoygoTheme.surface)

                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 12) {
                            Image(systemName: "message.badge.filled.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(VoygoTheme.primaryGradient)
                                .padding(.top, 32)
                            Text("Verify Phone Number")
                                .font(.title2.bold()).foregroundColor(VoygoTheme.textPrimary)
                            Text("Enter the 6-digit code sent to +60\(phoneNumber)")
                                .font(.subheadline).foregroundColor(VoygoTheme.textSecondary).multilineTextAlignment(.center)
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
                                .onChange(of: otp) { _, v in otp = String(v.filter(\.isNumber).prefix(6)) }
                                .padding(.vertical, 18)
                                .background(VoygoTheme.surface)
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(otp.count == 6 ? VoygoTheme.primary : VoygoTheme.cardBorder, lineWidth: 1.5))
                        }

                        PrimaryButton("Verify", isLoading: isLoading, isEnabled: otp.count == 6) {
                            isLoading = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isLoading = false
                                onVerify(otp)
                            }
                        }

                        Button(action: { timeLeft = 30 }) {
                            Text(timeLeft > 0 ? "Resend code in \(timeLeft)s" : "Resend Code")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(timeLeft == 0 ? VoygoTheme.primary : VoygoTheme.textHint)
                        }
                        .disabled(timeLeft > 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
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
