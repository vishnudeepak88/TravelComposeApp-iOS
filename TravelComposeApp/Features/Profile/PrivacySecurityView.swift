import SwiftUI

// MARK: - Privacy & Security
//
// Real controls screen that replaces the previous static "security
// tips" brochure. Required for App Store guideline 5.1.1(v) (account
// deletion must be in-app) and Malaysia PDPA Section 7 (right of
// access / data export). The four sections map directly to the four
// `/users/me/...` endpoints in server.js:
//
//   1. Notifications + phone visibility + marketing → /preferences
//   2. Blocked users                                → /blocks
//   3. Download my data                              → /data-export
//   4. Delete account                                → /delete
//
// Extracted from ProfileViews.swift (which was 1947 lines and held
// 9 distinct types) as part of the Apple R&D audit's "one type per
// file" follow-up. The view is unchanged — only its home moved.

struct PrivacySecurityView: View {
    var onBack: () -> Void
    @Environment(AppStore.self) private var store

    @State private var prefs: UserPreferencesDTO? = nil
    @State private var blocks: [BlockedUserDTO] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var infoMessage: String? = nil

    @State private var showDeleteConfirm: Bool = false
    @State private var showDeleteFinal: Bool = false
    @State private var isDeleting: Bool = false
    @State private var deleteResult: DeleteAccountResponse? = nil
    @State private var isRequestingExport: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Privacy & Security", onBack: onBack)
                ScrollView {
                    VStack(spacing: 18) {
                        if isLoading && prefs == nil {
                            ProgressView().padding(.top, 60)
                        } else {
                            preferencesCard
                            blocksCard
                            dataCard
                            deleteCard
                            if let infoMessage {
                                Text(infoMessage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(VPalette.success)
                                    .padding(.horizontal, 16)
                            }
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(VPalette.danger)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, VTabBarLayout.clearance)
                }
            }
        }
        .task { await load() }
        .alert("Delete this account?", isPresented: $showDeleteConfirm) {
            Button("Continue", role: .destructive) { showDeleteFinal = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your account, routes, and subscriptions will be paused immediately. You have 30 days to sign back in to cancel. After that, your data is permanently anonymised.")
        }
        .alert("Really delete?", isPresented: $showDeleteFinal) {
            Button("Yes, delete", role: .destructive) { Task { await deleteAccount() } }
            Button("Keep my account", role: .cancel) { }
        } message: {
            Text("This is your last chance to back out. We'll email a confirmation.")
        }
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VKicker(text: "Preferences").padding(.leading, 4).padding(.bottom, 8)
            VStack(spacing: 0) {
                preferenceToggle(
                    icon: "bell.fill", color: VPalette.warning,
                    title: "Push notifications",
                    subtitle: "Receive ride reminders, chat messages, payment receipts",
                    isOn: Binding(
                        get: { prefs?.pushEnabled ?? true },
                        set: { update(.pushEnabled, $0) }
                    )
                )
                divider()
                preferenceToggle(
                    icon: "phone.fill", color: VPalette.primary,
                    title: "Share phone with subscribers",
                    subtitle: "When OFF, riders see a masked number until pickup",
                    isOn: Binding(
                        get: { prefs?.phoneVisibleToSubscribers ?? true },
                        set: { update(.phoneVisibleToSubscribers, $0) }
                    )
                )
                divider()
                preferenceToggle(
                    icon: "faceid", color: VPalette.accent,
                    title: "Lock wallet with Face ID",
                    subtitle: "Require biometric to view payments + receipts",
                    isOn: Binding(
                        get: { prefs?.biometricLock ?? false },
                        set: { update(.biometricLock, $0) }
                    )
                )
                divider()
                preferenceToggle(
                    icon: "envelope.fill", color: VPalette.secondary,
                    title: "Promotional emails",
                    subtitle: "Optional. Defaults to OFF (PDPA opt-in)",
                    isOn: Binding(
                        get: { prefs?.marketingEmails ?? false },
                        set: { update(.marketingEmails, $0) }
                    )
                )
                divider()
                preferenceToggle(
                    icon: "chart.bar.doc.horizontal.fill", color: VPalette.accentPurple,
                    title: "Product analytics",
                    subtitle: "Share usage events that help improve reliability and route matching",
                    isOn: Binding(
                        get: { prefs?.analyticsEnabled ?? TelemetryConsent.isEnabled },
                        set: { update(.analyticsEnabled, $0) }
                    )
                )
            }
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func preferenceToggle(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VIconBubble(systemName: icon, color: color, size: 32, iconSize: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                Text(subtitle).font(.caption2).foregroundColor(VPalette.textSec)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(VPalette.primary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: Blocks

    private var blocksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VKicker(text: "Blocked users")
                Spacer()
                Text("\(blocks.count)/200")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(VPalette.textHint)
            }
            .padding(.leading, 4)
            .padding(.bottom, 8)
            VStack(spacing: 0) {
                if blocks.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "person.slash")
                            .font(.title3)
                            .foregroundColor(VPalette.textHint)
                        Text("No blocked users")
                            .font(.caption.weight(.heavy))
                            .foregroundColor(VPalette.textSec)
                        Text("Block a driver from any route detail to stop being matched with them.")
                            .font(.caption2)
                            .foregroundColor(VPalette.textHint)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, b in
                        if idx > 0 { divider() }
                        HStack(spacing: 12) {
                            VAvatar(initial: String(b.displayName.prefix(1)), size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.displayName).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                                if let reason = b.reason, !reason.isEmpty {
                                    Text(reason).font(.caption2).foregroundColor(VPalette.textSec).lineLimit(1)
                                }
                            }
                            Spacer()
                            Button {
                                Task { await unblock(b.userId) }
                            } label: {
                                Text("Unblock")
                                    .font(.caption.weight(.heavy))
                                    .foregroundColor(VPalette.primary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }
            }
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Data export

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VKicker(text: "Your data").padding(.leading, 4).padding(.bottom, 8)
            Button {
                Task { await requestDataExport() }
            } label: {
                HStack(spacing: 12) {
                    VIconBubble(systemName: "square.and.arrow.down.fill", color: VPalette.primary, size: 32, iconSize: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download my data")
                            .font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                        Text("We'll email a copy of your rides, payments and profile within 7 days (PDPA s.7)")
                            .font(.caption2).foregroundColor(VPalette.textSec)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if isRequestingExport {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.heavy))
                            .foregroundColor(VPalette.textHint)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isRequestingExport)
            .background(VPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Delete account

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VKicker(text: "Danger zone").padding(.leading, 4).padding(.bottom, 8)
            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 12) {
                    VIconBubble(systemName: "trash.fill", color: VPalette.danger, size: 32, iconSize: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete account")
                            .font(.footnote.weight(.heavy)).foregroundColor(VPalette.danger)
                        Text("Permanently removes your account after 30 days. Required by App Store + PDPA.")
                            .font(.caption2).foregroundColor(VPalette.textSec)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if isDeleting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.heavy))
                            .foregroundColor(VPalette.textHint)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .background(VPalette.dangerContainer.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.danger.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func divider() -> some View {
        Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 56)
    }

    // MARK: - Network

    private enum PrefField {
        case pushEnabled, phoneVisibleToSubscribers, biometricLock, marketingEmails, analyticsEnabled
    }

    private func load() async {
        isLoading = true
        async let prefsResult = (try? await VoygoAPIClient.getPreferences())
        async let blocksResult = (try? await VoygoAPIClient.listBlocks()) ?? []
        prefs = await prefsResult
        blocks = await blocksResult
        if let prefs {
            TelemetryConsent.isEnabled = prefs.analyticsEnabled
        }
        isLoading = false
        if prefs == nil { errorMessage = "Couldn't load preferences." }
    }

    private func update(_ field: PrefField, _ newValue: Bool) {
        // Optimistic local flip + server PUT. On failure, revert.
        guard var current = prefs else { return }
        let previous = current
        switch field {
        case .pushEnabled:                current.pushEnabled = newValue
        case .phoneVisibleToSubscribers:  current.phoneVisibleToSubscribers = newValue
        case .biometricLock:              current.biometricLock = newValue
        case .marketingEmails:            current.marketingEmails = newValue
        case .analyticsEnabled:           current.analyticsEnabled = newValue
        }
        prefs = current
        if field == .analyticsEnabled {
            TelemetryConsent.isEnabled = newValue
        }
        var patch = UpdatePreferencesRequest.empty
        switch field {
        case .pushEnabled:                patch.pushEnabled = newValue
        case .phoneVisibleToSubscribers:  patch.phoneVisibleToSubscribers = newValue
        case .biometricLock:              patch.biometricLock = newValue
        case .marketingEmails:            patch.marketingEmails = newValue
        case .analyticsEnabled:           patch.analyticsEnabled = newValue
        }
        Task {
            do {
                try await VoygoAPIClient.updatePreferences(patch)
            } catch {
                await MainActor.run {
                    prefs = previous
                    if field == .analyticsEnabled {
                        TelemetryConsent.isEnabled = previous.analyticsEnabled
                    }
                    errorMessage = "Couldn't save preference. Try again."
                }
            }
        }
    }

    private func unblock(_ userId: String) async {
        do {
            try await VoygoAPIClient.removeBlock(userId: userId)
            blocks.removeAll { $0.userId == userId }
            infoMessage = "Unblocked."
        } catch {
            errorMessage = "Couldn't unblock. Try again."
        }
    }

    private func requestDataExport() async {
        guard !isRequestingExport else { return }
        isRequestingExport = true
        defer { isRequestingExport = false }
        do {
            let r = try await VoygoAPIClient.requestDataExport()
            infoMessage = r.message
        } catch {
            errorMessage = "Couldn't queue the export. Try again."
        }
    }

    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await VoygoAPIClient.deleteAccount()
            // Server has soft-deleted the account; clear local session
            // so subsequent requests 401 and the user is bounced back
            // to the auth screen. They can re-sign-in within 30 days
            // to cancel — the next /auth/me will return 410 Gone in
            // that window, which AppStore clears via APIError flow.
            store.logout()
        } catch {
            errorMessage = "Couldn't delete the account. Try again or email support."
        }
    }
}

// Pre-populated patch helper. The struct already has a memberwise
// init that takes all-nil; we just expose a named static accessor
// because writing `UpdatePreferencesRequest(pushEnabled: nil, ...)`
// at every call site is noisy.
extension UpdatePreferencesRequest {
    static var empty: UpdatePreferencesRequest {
        UpdatePreferencesRequest(
            pushEnabled: nil,
            phoneVisibleToSubscribers: nil,
            biometricLock: nil,
            marketingEmails: nil,
            analyticsEnabled: nil
        )
    }
}
