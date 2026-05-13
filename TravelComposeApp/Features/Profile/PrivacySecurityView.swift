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
                VPolishedNavBar(title: S.privacyTitle, onBack: onBack)
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
        .alert(S.privacyDeleteConfirmTitle, isPresented: $showDeleteConfirm) {
            Button(S.privacyDeleteContinue, role: .destructive) { showDeleteFinal = true }
            Button(S.cancel, role: .cancel) { }
        } message: {
            Text(S.privacyDeleteConfirmBody)
        }
        .alert(S.privacyDeleteFinalTitle, isPresented: $showDeleteFinal) {
            Button(S.privacyDeleteYes, role: .destructive) { Task { await deleteAccount() } }
            Button(S.privacyDeleteKeep, role: .cancel) { }
        } message: {
            Text(S.privacyDeleteFinalBody)
        }
    }

    // MARK: Preferences

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VKicker(text: S.privacyPreferences).padding(.leading, 4).padding(.bottom, 8)
            VStack(spacing: 0) {
                preferenceToggle(
                    icon: "bell.fill", color: VPalette.warning,
                    title: S.privacyPushNotifications,
                    subtitle: S.privacyPushSubtitle,
                    isOn: Binding(
                        get: { prefs?.pushEnabled ?? true },
                        set: { update(.pushEnabled, $0) }
                    )
                )
                divider()
                preferenceToggle(
                    icon: "phone.fill", color: VPalette.primary,
                    title: S.privacyPhoneShare,
                    subtitle: S.privacyPhoneShareSubtitle,
                    isOn: Binding(
                        get: { prefs?.phoneVisibleToSubscribers ?? true },
                        set: { update(.phoneVisibleToSubscribers, $0) }
                    )
                )
                divider()
                // Face ID lock toggle removed — the preference persisted
                // but no LAContext gate was ever wired up in WalletView,
                // so toggling on did nothing. Restoring this requires
                // adding the biometric prompt in WalletView.body before
                // the credit hero renders. Until then a placebo toggle
                // is worse than no toggle.
                preferenceToggle(
                    icon: "envelope.fill", color: VPalette.secondary,
                    title: S.privacyMarketing,
                    subtitle: S.privacyMarketingSubtitle,
                    isOn: Binding(
                        get: { prefs?.marketingEmails ?? false },
                        set: { update(.marketingEmails, $0) }
                    )
                )
                divider()
                preferenceToggle(
                    icon: "chart.bar.doc.horizontal.fill", color: VPalette.accentPurple,
                    title: S.privacyAnalyticsTitle,
                    subtitle: S.privacyAnalyticsSubtitle,
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
                VKicker(text: S.privacyBlockedTitle)
                Spacer()
                Text(S.privacyBlocksCounter(blocks.count))
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
                        Text(S.privacyBlockedEmpty)
                            .font(.caption.weight(.heavy))
                            .foregroundColor(VPalette.textSec)
                        Text(S.privacyBlockedEmptyBody)
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
                                Text(S.privacyUnblock)
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
            VKicker(text: S.privacyDataTitle).padding(.leading, 4).padding(.bottom, 8)
            Button {
                Task { await requestDataExport() }
            } label: {
                HStack(spacing: 12) {
                    VIconBubble(systemName: "square.and.arrow.down.fill", color: VPalette.primary, size: 32, iconSize: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.privacyDataDownload)
                            .font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                        Text(S.privacyDataDownloadSubtitle)
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
            VKicker(text: S.privacyDangerTitle).padding(.leading, 4).padding(.bottom, 8)
            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 12) {
                    VIconBubble(systemName: "trash.fill", color: VPalette.danger, size: 32, iconSize: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(S.privacyDelete)
                            .font(.footnote.weight(.heavy)).foregroundColor(VPalette.danger)
                        Text(S.privacyDeleteSubtitle)
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
        if prefs == nil { errorMessage = S.privacyLoadFailed }
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
                    errorMessage = S.privacySaveFailed
                }
            }
        }
    }

    private func unblock(_ userId: String) async {
        do {
            try await VoygoAPIClient.removeBlock(userId: userId)
            blocks.removeAll { $0.userId == userId }
            infoMessage = S.privacyUnblockedToast
        } catch {
            errorMessage = S.privacyUnblockFailed
        }
    }

    private func requestDataExport() async {
        guard !isRequestingExport else { return }
        isRequestingExport = true
        defer { isRequestingExport = false }
        do {
            let r = try await VoygoAPIClient.requestDataExport()
            // Surface the server's confirmation message when present —
            // it carries the actual SLA + email channel the queue
            // dispatched to. Falls back to the localised subtitle if
            // the server response is empty so the user always sees
            // something readable.
            infoMessage = r.message.isEmpty ? S.privacyDataDownloadSubtitle : r.message
        } catch {
            errorMessage = S.privacyExportFailed
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
            errorMessage = S.privacyDeleteFailed
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
