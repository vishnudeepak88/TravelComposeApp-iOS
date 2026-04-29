import SwiftUI

// MARK: - Profile (mirrors ProfileScreen.kt)

enum ProfileRoute: Hashable {
    case wallet
    case tripHistory
    case notifications
    case receipt(id: String)
    case driverDashboard
    case driverPayouts
    case kyc
}

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @State private var path: [ProfileRoute] = []
    @State private var notificationsEnabled = true
    @State private var showVerification = false
    @State private var showPrivacy = false
    @State private var showHelp = false
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                VPalette.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    VPolishedNavBar(title: "Profile")

                    ScrollView {
                        VStack(spacing: 18) {
                            identityRow
                            kycCard
                            quickStats
                            walletStatsRow
                            settingsCard
                            driverModeCard
                            logoutPill
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 108)
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .wallet:
                    WalletView(onBack: { path.removeLast() })
                        .navigationBarHidden(true)
                case .tripHistory:
                    TripHistoryView(
                        onBack: { path.removeLast() },
                        onOpenReceipt: { id in path.append(.receipt(id: id)) }
                    )
                    .navigationBarHidden(true)
                case .notifications:
                    NotificationsView(onBack: { path.removeLast() })
                        .navigationBarHidden(true)
                case .receipt(let id):
                    ReceiptView(bookingId: id, onBack: { path.removeLast() })
                        .navigationBarHidden(true)
                case .driverDashboard:
                    DriverDashboardView(
                        onBack: { path.removeLast() },
                        onOpenCalendar: { _ in },
                        onOpenPayouts: { path.append(.driverPayouts) }
                    )
                    .navigationBarHidden(true)
                case .driverPayouts:
                    DriverPayoutsView(onBack: { path.removeLast() })
                        .navigationBarHidden(true)
                case .kyc:
                    KycVerificationView(onBack: { path.removeLast() })
                        .navigationBarHidden(true)
                }
            }
            .sheet(isPresented: $showVerification) { VerificationView(onBack: { showVerification = false }) }
            .sheet(isPresented: $showPrivacy)      { PrivacySecurityView(onBack: { showPrivacy = false }) }
            .sheet(isPresented: $showHelp)         { HelpCenterView(onBack: { showHelp = false }) }
            .alert("Log Out", isPresented: $showLogoutAlert) {
                Button("Log Out", role: .destructive, action: store.logout)
                Button("Cancel", role: .cancel, action: {})
            } message: { Text("You'll need to sign in again.") }
            .task { await store.refreshMe() }
        }
    }

    private var identityRow: some View {
        HStack(spacing: 14) {
            VAvatar(initial: store.currentUser.initial.isEmpty ? "?" : store.currentUser.initial, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.currentUser.name.isEmpty ? "Welcome" : store.currentUser.name)
                    .font(.system(size: 20, weight: .heavy)).tracking(-0.4)
                    .foregroundColor(VPalette.text)
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 13)).foregroundColor(VPalette.primary)
                    Text(String(format: "%.1f rating", store.currentUser.rating))
                        .font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.textSec)
                    Circle().fill(VPalette.textHint).frame(width: 3, height: 3)
                    Text("0 rides").font(.system(size: 12)).foregroundColor(VPalette.textSec)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private var kycCard: some View {
        Button { path.append(.kyc) } label: {
            HStack(spacing: 12) {
                VIconBubble(systemName: kycIcon, color: kycColor, size: 44, iconSize: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Identity Verification")
                        .font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    Text(kycMessage).font(.system(size: 11)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                VBadge(text: kycBadge, color: kycColor, container: kycColor.opacity(0.15))
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var walletStatsRow: some View {
        Button { path.append(.wallet) } label: {
            HStack(spacing: 12) {
                VIconBubble(systemName: "creditcard.fill", color: VPalette.primary, size: 44, iconSize: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallet & payment methods")
                        .font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    Text("RM 42.50 credit · DuitNow default")
                        .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.textHint)
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var quickStats: some View {
        Button { path.append(.tripHistory) } label: {
            HStack(spacing: 0) {
                statCell("RM 1,820", "Saved")
                Rectangle().fill(VPalette.border).frame(width: 1, height: 32)
                statCell("412", "Trips")
                Rectangle().fill(VPalette.border).frame(width: 1, height: 32)
                statCell("97%", "On-time")
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 18, weight: .black)).tracking(-0.3).foregroundColor(VPalette.primary)
            VKicker(text: label, size: 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            VKicker(text: "Settings").padding(.leading, 4)
            VStack(spacing: 0) {
                row(icon: "bell.fill", color: VPalette.warning, title: "Notifications", trailing: AnyView(Toggle("", isOn: $notificationsEnabled).labelsHidden().tint(VPalette.primary)))
                divider()
                row(icon: "shield.lefthalf.filled", color: VPalette.accent, title: "Privacy & Security", chevron: true) { showPrivacy = true }
                divider()
                row(icon: "creditcard.fill", color: VPalette.primary, title: "Payment methods", trailingText: "DuitNow · TNG") { path.append(.wallet) }
                divider()
                row(icon: "bell.badge.fill", color: VPalette.secondary, title: "Notifications center", chevron: true) { path.append(.notifications) }
                divider()
                row(icon: "doc.text.fill", color: VPalette.accent, title: "Trip history", chevron: true) { path.append(.tripHistory) }
                divider()
                row(icon: "questionmark.circle.fill", color: VPalette.secondary, title: "Help Center", chevron: true) { showHelp = true }
            }
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func divider() -> some View {
        Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 60)
    }

    @ViewBuilder
    private func row(
        icon: String,
        color: Color,
        title: String,
        chevron: Bool = false,
        trailing: AnyView? = nil,
        trailingText: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        Button { action?() } label: {
            HStack(spacing: 12) {
                VIconBubble(systemName: icon, color: color, size: 32, iconSize: 14)
                Text(title).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                Spacer()
                if let trailingText {
                    Text(trailingText).font(.system(size: 11, weight: .bold)).foregroundColor(VPalette.textSec)
                }
                if let trailing {
                    trailing
                }
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.textHint)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var driverModeCard: some View {
        Button { path.append(.driverDashboard) } label: {
            HStack(spacing: 12) {
                VIconBubble(systemName: "car.fill", color: VPalette.primary, size: 44, iconSize: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver mode").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    Text("Manage your routes & earnings").font(.system(size: 11)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.textHint)
            }
            .padding(14)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var logoutPill: some View {
        Button { showLogoutAlert = true } label: {
            HStack {
                Image(systemName: "arrow.up.right.square.fill").foregroundColor(VPalette.danger)
                Text("Log out").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.danger)
                Spacer()
            }
            .padding(14)
            .background(VPalette.dangerContainer)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.danger.opacity(0.2), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var kycIcon: String {
        switch store.kycStatus {
        case .approved: return "checkmark.seal.fill"
        case .pending:  return "clock.badge.fill"
        case .rejected: return "xmark.seal.fill"
        default:        return "person.badge.key.fill"
        }
    }
    private var kycColor: Color {
        switch store.kycStatus {
        case .approved: return VPalette.success
        case .pending:  return VPalette.warning
        case .rejected: return VPalette.danger
        default:        return VPalette.primary
        }
    }
    private var kycMessage: String {
        switch store.kycStatus {
        case .approved: return "You are fully verified · MyKad on file"
        case .pending:  return "Verification under review"
        case .rejected: return "Verification rejected – resubmit"
        default:        return "Complete verification to drive"
        }
    }
    private var kycBadge: String {
        switch store.kycStatus {
        case .approved: return "Verified"
        case .pending:  return "Pending"
        case .rejected: return "Rejected"
        default:        return "Not Started"
        }
    }
}

private struct SettingsRow<T: View>: View {
    let icon: String; let title: String; let color: Color
    let trailing: T
    var action: (() -> Void)? = nil

    init(icon: String, title: String, color: Color, @ViewBuilder trailing: () -> T, action: (() -> Void)? = nil) {
        self.icon = icon; self.title = title; self.color = color; self.trailing = trailing(); self.action = action
    }
    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.subheadline)
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title).font(.subheadline).foregroundColor(VoygoTheme.textPrimary)
                Spacer()
                trailing
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Identity Verification (mirrors VerificationScreen.kt)

@MainActor
final class VerificationViewModel: ObservableObject {
    @Published var step = 1
    @Published var make = ""
    @Published var model = ""
    @Published var licensePlate = ""
    @Published var isSubmitting = false
    @Published var error: String? = nil
    var store: AppStore?

    func nextStep() { if step < 3 { step += 1 } }

    func submit() {
        guard let store else { return }
        Task {
            isSubmitting = true
            let result = await store.submitKyc(status: .pending)
            isSubmitting = false
            if case .failure(let err) = result {
                error = err.localizedDescription
            }
        }
    }
}

struct VerificationView: View {
    var onBack: () -> Void
    @EnvironmentObject var store: AppStore
    @StateObject private var vm = VerificationViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Identity Verification", showBack: true, onBack: onBack)
                    .background(VoygoTheme.background)

                StepperHeaderView(currentStep: vm.step, totalSteps: 3, titles: ["Documents", "Selfie", "Vehicle"])
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .background(VoygoTheme.surface)

                if store.kycStatus == .pending {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundColor(VoygoTheme.success)
                        Text("Verification Submitted!").font(.title2.bold()).foregroundColor(VoygoTheme.textPrimary)
                        Text("We'll review your documents within 24 hours.")
                            .font(.subheadline).foregroundColor(VoygoTheme.textSecondary).multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            switch vm.step {
                            case 1: DocumentUploadSection()
                            case 2: SelfieSection()
                            case 3: VehicleSection(make: $vm.make, model: $vm.model, licensePlate: $vm.licensePlate)
                            default: EmptyView()
                            }

                            if let err = vm.error {
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(VoygoTheme.danger)
                                    Text(err).font(.caption).foregroundColor(VoygoTheme.danger)
                                    Spacer()
                                }
                            }

                            PrimaryButton(vm.step < 3 ? "Next" : "Submit", isLoading: vm.isSubmitting) {
                                if vm.step < 3 { vm.nextStep() } else { vm.submit() }
                            }
                        }
                        .padding(24)
                    }
                }
            }
        }
        .onAppear { vm.store = store }
    }
}

private struct DocumentUploadSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Upload ID").font(.title3.bold()).foregroundColor(VoygoTheme.textPrimary)
                Text("Government issued ID required").font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
            }
            VoygoCard(cornerRadius: 14) {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.up.doc.fill").font(.system(size: 40)).foregroundStyle(VoygoTheme.primaryGradient)
                    Text("Tap to upload front side").font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                    Text("JPG, PNG or PDF · Max 5MB").font(.caption2).foregroundColor(VoygoTheme.textHint)
                }
                .frame(maxWidth: .infinity).frame(height: 160).padding()
            }
        }
    }
}

private struct SelfieSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Take a Selfie").font(.title3.bold()).foregroundColor(VoygoTheme.textPrimary)
                Text("Make sure your face is clearly visible").font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
            }
            VoygoCard(cornerRadius: 14) {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 52)).foregroundStyle(VoygoTheme.primaryGradient)
                    Text("Tap to open camera").font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                }
                .frame(maxWidth: .infinity).frame(height: 200).padding()
            }
        }
    }
}

private struct VehicleSection: View {
    @Binding var make: String
    @Binding var model: String
    @Binding var licensePlate: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vehicle Details").font(.title3.bold()).foregroundColor(VoygoTheme.textPrimary)
            VoygoTextField(label: "Make", text: $make, placeholder: "e.g. Toyota")
            VoygoTextField(label: "Model", text: $model, placeholder: "e.g. Vios")
            VoygoTextField(label: "License Plate", text: $licensePlate, placeholder: "e.g. VCC 1234")
        }
    }
}

// MARK: - Privacy & Security (mirrors PrivacySecurityScreen.kt)

struct PrivacySecurityView: View {
    var onBack: () -> Void
    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Privacy & Security", showBack: true, onBack: onBack).background(VoygoTheme.background)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Privacy Controls").font(.title3.bold()).foregroundColor(VoygoTheme.textPrimary)
                        Text("Manage data sharing, account security, and app permissions.")
                            .font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                        VoygoCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Security Tips").font(.subheadline.bold()).foregroundColor(VoygoTheme.textPrimary)
                                ForEach(["Keep your OTP private.", "Use only your own phone number.", "Report suspicious activity from Help Center."], id: \.self) { tip in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "shield.checkmark.fill").foregroundColor(VoygoTheme.success).font(.caption)
                                        Text(tip).font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

// MARK: - Help Center (mirrors HelpCenterScreen.kt)

struct HelpCenterView: View {
    var onBack: () -> Void
    var body: some View {
        ZStack(alignment: .top) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VoygoNavBar(title: "Help Center", showBack: true, onBack: onBack).background(VoygoTheme.background)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "questionmark.bubble.fill").font(.system(size: 40)).foregroundStyle(VoygoTheme.primaryGradient)
                            VStack(alignment: .leading) {
                                Text("Need Help?").font(.title3.bold()).foregroundColor(VoygoTheme.textPrimary)
                                Text("We're here for you").font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                            }
                        }
                        VoygoCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HelpRow(icon: "envelope.fill", title: "Email Support", value: "support@voygo.app")
                                Divider().background(VoygoTheme.cardBorder)
                                HelpRow(icon: "bubble.left.and.bubble.right.fill", title: "In-App Chat", value: "Available from Inbox tab")
                                Divider().background(VoygoTheme.cardBorder)
                                HelpRow(icon: "doc.text.fill", title: "FAQ", value: "voygo.app/help")
                            }
                            .padding(16)
                        }
                        Text("For commute subscriptions, route issues, or payment questions, contact our support team. We typically respond within 2 hours.")
                            .font(.subheadline).foregroundColor(VoygoTheme.textSecondary)
                    }
                    .padding(20)
                }
            }
        }
    }
}

private struct HelpRow: View {
    let icon: String; let title: String; let value: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.subheadline).foregroundColor(VoygoTheme.primary)
                .frame(width: 28, height: 28).background(VoygoTheme.primary.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).foregroundColor(VoygoTheme.textSecondary)
                Text(value).font(.subheadline).foregroundColor(VoygoTheme.textPrimary)
            }
        }
    }
}

// MARK: - Live Trip (mirrors LiveTripScreen.kt)

struct LiveTripView: View {
    let tripId: String
    var isDriver: Bool = false
    var onBack: () -> Void
    var onMessageDriver: (() -> Void)? = nil
    var onEndTrip: (() -> Void)? = nil

    @State private var pickupConfirmed = false
    @State private var dropoffConfirmed = false
    @State private var sosPressed = false

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    VMapPlaceholder(tone: .teal, label: "Live · Subang → KLCC", height: 360)

                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(VPalette.text)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        HStack(spacing: 8) {
                            Circle().fill(VPalette.success).frame(width: 8, height: 8)
                            Text("En route").font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.text)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                        Spacer()

                        Button {} label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(VPalette.text)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 54)

                    GeometryReader { geo in
                        ZStack {
                            Circle().fill(VPalette.primary).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .shadow(color: VPalette.primary.opacity(0.5), radius: 12, y: 4)
                            Image(systemName: "car.fill").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        }
                        .position(x: geo.size.width * 0.47, y: geo.size.height * 0.55)
                    }
                }
                .frame(height: 360)
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer()
                bottomSheet
            }
        }
        .navigationBarHidden(true)
    }

    private var bottomSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(VPalette.border).frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 14)

            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    VKicker(text: "ETA")
                    Text("12 min")
                        .font(.system(size: 36, weight: .black))
                        .tracking(-1.2)
                        .foregroundStyle(VPalette.primaryGradient)
                    Text("Arriving 8:34 AM · 8.4 km")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                HStack(spacing: 6) {
                    iconButton("flag.fill",            color: VPalette.danger,  bg: VPalette.dangerContainer)
                    iconButton("square.and.arrow.up",  color: VPalette.primary, bg: VPalette.primaryContainer)
                }
            }

            Rectangle().fill(VPalette.border).frame(height: 1).padding(.vertical, 16)

            HStack(alignment: .top, spacing: 12) {
                VRouteGlyph().frame(height: 64)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        VKicker(text: "Pickup · 7:42 ✓", color: VPalette.success, size: 10)
                        Text("USJ 9 LRT, Subang Jaya").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        VKicker(text: "Drop · 8:34", color: VPalette.primary, size: 10)
                        Text("KLCC Tower B, Kuala Lumpur").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    }
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(VPalette.border).frame(height: 1).padding(.vertical, 16)

            HStack(spacing: 12) {
                VAvatar(initial: "A", size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Aiman Z.").font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    Text("Tesla Model 3 · VEC 4123")
                        .font(.system(size: 11)).foregroundColor(VPalette.textSec)
                }
                Spacer()
                Button {} label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(VPalette.success).clipShape(Circle())
                        .shadow(color: VPalette.success.opacity(0.5), radius: 8, y: 3)
                }.buttonStyle(.plain)
                Button { onMessageDriver?() } label: {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(VPalette.primary).clipShape(Circle())
                        .shadow(color: VPalette.primary.opacity(0.5), radius: 8, y: 3)
                }.buttonStyle(.plain)
            }
            .padding(12)
            .background(VPalette.surfaceHigh)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button { sosPressed.toggle() } label: {
                HStack(spacing: 8) {
                    Text("🆘").font(.system(size: 18))
                    Text("Hold for SOS")
                        .font(.system(size: 14, weight: .black))
                        .tracking(0.3)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundColor(VPalette.danger)
                .background(VPalette.dangerContainer)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VPalette.danger.opacity(0.35), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            if let onEndTrip {
                VPrimaryButton("End trip → rate", action: onEndTrip)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 30, y: -10)
    }

    private func iconButton(_ system: String, color: Color, bg: Color) -> some View {
        Button {} label: {
            Image(systemName: system).font(.system(size: 14, weight: .bold)).foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(bg)
                .clipShape(Circle())
        }.buttonStyle(.plain)
    }
}

private struct _LiveTripDeprecatedHelpers: View {
    var body: some View {
        EmptyView()
    }
}
