import SwiftUI

// MARK: - Profile (mirrors ProfileScreen.kt)

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @State private var notificationsEnabled = true
    @State private var showVerification = false
    @State private var showPrivacy = false
    @State private var showHelp = false
    @State private var showLogoutAlert = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VoygoTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    VoygoNavBar(title: "Profile")

                    ScrollView {
                        VStack(spacing: 24) {
                            HStack(spacing: 16) {
                                AvatarView(initial: store.currentUser.initial, size: 80)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(store.currentUser.name)
                                        .font(.title2.weight(.bold))
                                        .foregroundColor(VoygoTheme.textPrimary)
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.subheadline)
                                            .foregroundColor(VoygoTheme.primary)
                                        Text("\(store.currentUser.rating, specifier: "%.1f") Rating")
                                            .font(.subheadline)
                                            .foregroundColor(VoygoTheme.textSecondary)
                                    }
                                }
                                Spacer()
                            }

                            // KYC card
                            Button(action: { showVerification = true }) {
                                VoygoCard {
                                    HStack(spacing: 14) {
                                        Image(systemName: kycIcon)
                                            .font(.title2)
                                            .foregroundColor(kycColor)
                                            .frame(width: 44, height: 44)
                                            .background(kycColor.opacity(0.15))
                                            .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Identity Verification").font(.subheadline.bold()).foregroundColor(VoygoTheme.textPrimary)
                                            Text(kycMessage).font(.caption).foregroundColor(VoygoTheme.textSecondary)
                                        }
                                        Spacer()
                                        StatusBadge(text: kycBadge, color: kycColor)
                                        Image(systemName: "chevron.right").font(.caption).foregroundColor(VoygoTheme.textHint)
                                    }
                                    .padding(16)
                                }
                            }
                            .buttonStyle(.plain)

                            // Settings
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Settings")
                                    .font(.headline)
                                    .foregroundColor(VoygoTheme.textPrimary)

                                VoygoCard {
                                    VStack(spacing: 0) {
                                    SettingsRow(icon: "bell.fill", title: "Notifications", color: VoygoTheme.warning) {
                                        HStack {
                                            Toggle("", isOn: $notificationsEnabled).labelsHidden().tint(VoygoTheme.primary)
                                        }
                                    }
                                    Divider().background(VoygoTheme.cardBorder).padding(.horizontal, 16)
                                    SettingsRow(icon: "shield.lefthalf.filled", title: "Privacy & Security", color: VoygoTheme.accent) {
                                        Image(systemName: "chevron.right").font(.caption).foregroundColor(VoygoTheme.textHint)
                                    } action: { showPrivacy = true }
                                    Divider().background(VoygoTheme.cardBorder).padding(.horizontal, 16)
                                    SettingsRow(icon: "questionmark.circle.fill", title: "Help Center", color: VoygoTheme.primary) {
                                        Image(systemName: "chevron.right").font(.caption).foregroundColor(VoygoTheme.textHint)
                                    } action: { showHelp = true }
                                    Spacer().frame(height: 8)
                                    }
                                }
                            }

                            // Logout
                            Button(action: { showLogoutAlert = true }) {
                                HStack {
                                    Image(systemName: "rectangle.portrait.and.arrow.right").foregroundColor(VoygoTheme.danger)
                                    Text("Log Out").font(.subheadline.weight(.semibold)).foregroundColor(VoygoTheme.danger)
                                    Spacer()
                                }
                                .padding(16)
                                .background(VoygoTheme.danger.opacity(0.08))
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(VoygoTheme.danger.opacity(0.25), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 108)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showVerification) { VerificationView(onBack: { showVerification = false }) }
            .sheet(isPresented: $showPrivacy)      { PrivacySecurityView(onBack: { showPrivacy = false }) }
            .sheet(isPresented: $showHelp)         { HelpCenterView(onBack: { showHelp = false }) }
            .alert("Log Out", isPresented: $showLogoutAlert) {
                Button("Log Out", role: .destructive, action: store.logout)
                Button("Cancel", role: .cancel, action: {})
            } message: { Text("You'll need to sign in again.") }
        }
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
        case .approved: return VoygoTheme.success
        case .pending:  return VoygoTheme.warning
        case .rejected: return VoygoTheme.danger
        default:        return VoygoTheme.primary
        }
    }
    private var kycMessage: String {
        switch store.kycStatus {
        case .approved: return "You are fully verified"
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
    var store: AppStore?

    func nextStep() { if step < 3 { step += 1 } }
    func submit() {
        isSubmitting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isSubmitting = false
            self.store?.kycStatus = .pending
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

    @State private var pickupConfirmed = false
    @State private var dropoffConfirmed = false
    @State private var eta = "12 min"
    @State private var sosPressed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Map placeholder
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [VoygoTheme.primaryContainer.opacity(0.8), VoygoTheme.background],
                                   startPoint: .top, endPoint: .bottom)
                    VStack {
                        HStack {
                            Button(action: onBack) {
                                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(.black.opacity(0.4)).clipShape(Circle())
                            }
                            .padding(20)
                            Spacer()
                        }
                        Spacer()
                        Image(systemName: "map.fill")
                            .font(.system(size: 52)).foregroundColor(.white.opacity(0.15))
                        Text("Map view — wire MapKit here").font(.caption).foregroundColor(.white.opacity(0.3))
                        Spacer()
                    }
                }
                .frame(height: 280)

                // Bottom panel
                VoygoCard(cornerRadius: 24) {
                    VStack(spacing: 20) {
                        // ETA header
                        HStack {
                            VStack(alignment: .leading) {
                                Text("ETA").font(.caption.weight(.semibold)).foregroundColor(VoygoTheme.textHint)
                                Text(eta).font(.system(size: 32, weight: .black)).foregroundStyle(VoygoTheme.primaryGradient)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                ActionIconButton(icon: "flag.fill", color: VoygoTheme.danger)
                                ActionIconButton(icon: "square.and.arrow.up.fill", color: VoygoTheme.primary)
                            }
                        }

                        Divider().background(VoygoTheme.cardBorder)

                        if isDriver {
                            // Driver checklist
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Trip Checklist").font(.subheadline.bold()).foregroundColor(VoygoTheme.textPrimary)
                                ChecklistRow(label: "Passenger Boarded", isChecked: $pickupConfirmed)
                                ChecklistRow(label: "Reached Destination", isChecked: $dropoffConfirmed, isEnabled: pickupConfirmed)
                                PrimaryButton("End Trip", isEnabled: dropoffConfirmed) {}
                            }
                        } else {
                            // Rider info
                            VStack(spacing: 10) {
                                TripLeg(icon: "circle.fill", label: "Pickup", location: "Downtown Station", color: VoygoTheme.success)
                                Rectangle().fill(VoygoTheme.cardBorder).frame(width: 1, height: 20).padding(.leading, 12)
                                TripLeg(icon: "flag.fill", label: "Drop", location: "KLCC Office Park", color: VoygoTheme.primary)
                            }
                        }

                        // Contact + SOS
                        HStack(spacing: 12) {
                            HStack(spacing: 10) {
                                AvatarView(initial: isDriver ? "R" : "N", size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(isDriver ? "Rider" : "Nina Cruz").font(.subheadline.bold()).foregroundColor(VoygoTheme.textPrimary)
                                    Text(isDriver ? "Passenger" : "Your driver").font(.caption2).foregroundColor(VoygoTheme.textHint)
                                }
                            }
                            Spacer()
                            ActionIconButton(icon: "phone.fill", color: VoygoTheme.success)
                            ActionIconButton(icon: "bubble.left.fill", color: VoygoTheme.primary)
                        }

                        // SOS
                        Button(action: { sosPressed.toggle() }) {
                            HStack {
                                Image(systemName: "sos.circle.fill").font(.title3)
                                Text("Hold for SOS")
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(VoygoTheme.danger.opacity(0.15))
                            .foregroundColor(VoygoTheme.danger)
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(VoygoTheme.danger.opacity(0.4), lineWidth: 1.5))
                        }
                    }
                    .padding(24)
                }
                .shadow(color: .black.opacity(0.4), radius: 20, y: -8)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

private struct ActionIconButton: View {
    let icon: String; let color: Color
    var body: some View {
        Button(action: {}) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12))
                .clipShape(Circle())
        }
    }
}

private struct ChecklistRow: View {
    let label: String
    @Binding var isChecked: Bool
    var isEnabled: Bool = true
    var body: some View {
        HStack(spacing: 12) {
            Button(action: { if isEnabled { isChecked.toggle() } }) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isChecked ? VoygoTheme.success : (isEnabled ? VoygoTheme.textHint : VoygoTheme.textHint.opacity(0.4)))
            }
            .disabled(!isEnabled)
            Text(label).font(.subheadline).foregroundColor(isEnabled ? VoygoTheme.textPrimary : VoygoTheme.textHint)
        }
    }
}

private struct TripLeg: View {
    let icon: String; let label: String; let location: String; let color: Color
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(color).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundColor(VoygoTheme.textHint)
                Text(location).font(.subheadline.weight(.medium)).foregroundColor(VoygoTheme.textPrimary)
            }
        }
    }
}
