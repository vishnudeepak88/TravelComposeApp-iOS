import SwiftUI

// MARK: - Trust-aware KYC verification flow.
//
// Replaces the mock VerificationViewModel that flipped a single KYC enum.
// Drives off `store.kycDocuments` (per-kind submissions) and the typed
// `KycDocumentKind` checklist from Trust.swift. The user picks rider vs
// driver role, sees a checklist of required documents, taps "Upload"
// to submit each one (no real photo picker yet — that's a follow-up;
// the call records the kind so the backend flips status to PENDING).

struct KycVerificationView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void

    @State private var role: KycSubmission.Role = .rider
    @State private var inFlightKind: KycDocumentKind? = nil
    @State private var error: String? = nil
    @State private var info: String? = nil
    /// The document the picker is currently feeding. When non-nil
    /// the PHPicker sheet is presented; the closure handler hands
    /// the picked image bytes to `upload(_:imageData:)`.
    @State private var pickerKind: KycDocumentKind? = nil

    private var requiredKinds: [KycDocumentKind] {
        role == .driver ? KycDocumentKind.driverRequired : KycDocumentKind.riderRequired
    }

    private var docByKind: [KycDocumentKind: KycDocument] {
        Dictionary(uniqueKeysWithValues: store.kycDocuments.map { ($0.kind, $0) })
    }

    private var completion: (uploaded: Int, required: Int) {
        store.kycCompletion(role: role)
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: S.kycTitle, kicker: S.kycKicker, onBack: onBack)

                ScrollView {
                    VStack(spacing: 16) {
                        statusCard
                        // Stuck-PENDING escape hatch — a driver whose
                        // docs are sitting in the review queue for
                        // more than 48 hours can email support
                        // directly. Without this they have no
                        // recourse; the previous "We typically respond
                        // within 24 hours" copy promised a SLA that
                        // had no real path behind it.
                        if store.kycStatus == .pending {
                            pendingSupportBanner
                        }
                        roleSwitcher
                        progressBar
                        if let error { VErrorBanner(message: error) }
                        if let info { banner(info, color: VPalette.success) }
                        documentList
                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await store.refreshKycDocuments()
            await store.refreshMe()
        }
        .sheet(item: Binding(
            get: { pickerKind.map(KycPickKind.init) },
            set: { if $0 == nil { pickerKind = nil } }
        )) { wrapper in
            PhotoPicker { data in
                let kind = wrapper.kind
                pickerKind = nil
                // Real upload pipeline:
                //   1. PHPicker → image bytes
                //   2. POST /users/me/kyc-documents/upload → storageUri
                //   3. POST /users/me/kyc-documents { kind, storageUri }
                guard let imageData = data else { return } // cancelled
                Task { await upload(kind, imageData: imageData) }
            }
        }
    }

    /// Sheet identifier wrapper — `pickerKind` doubles as both the
    /// upload target and the sheet trigger.
    private struct KycPickKind: Identifiable {
        let kind: KycDocumentKind
        var id: String { kind.rawValue }
    }

    // MARK: - Sections

    private var statusCard: some View {
        HStack(spacing: 14) {
            VIconBubble(systemName: statusIcon, color: statusColor, size: 48, iconSize: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline.weight(.heavy))
                    .foregroundColor(VPalette.text)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundColor(VPalette.textSec)
            }
            Spacer()
            VBadge(text: store.kycStatus.label, color: statusColor, container: statusColor.opacity(0.15))
        }
        .padding(14)
        .background(VPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var roleSwitcher: some View {
        VStack(alignment: .leading, spacing: 8) {
            VKicker(text: S.kycWhoVerifying).padding(.leading, 4)
            HStack(spacing: 6) {
                // Counts derive from the checklist so they never drift
                // out of sync with what the document list actually
                // renders. The trailing "documents" word is pluralised
                // via `S.kycDocsCount(_:)`.
                roleChip(label: S.kycRider,
                         value: .rider,
                         subtitle: S.kycDocsCount(KycDocumentKind.riderRequired.count))
                roleChip(label: S.kycDriver,
                         value: .driver,
                         subtitle: S.kycDocsCount(KycDocumentKind.driverRequired.count))
            }
        }
    }

    private func roleChip(label: String, value: KycSubmission.Role, subtitle: String) -> some View {
        let on = role == value
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { role = value }
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.subheadline.weight(.heavy))
                Text(subtitle).font(.caption2).opacity(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundColor(on ? .white : VPalette.text)
            .background(on ? AnyShapeStyle(VPalette.primaryGradient) : AnyShapeStyle(VPalette.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? Color.clear : VPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        let pair = completion
        // Guard divide-by-zero AND clamp the ratio so a malformed input
        // (uploaded > required) doesn't blow past 100%.
        let pct: Double = {
            guard pair.required > 0 else { return pair.uploaded > 0 ? 1.0 : 0.0 }
            return min(1.0, Double(pair.uploaded) / Double(pair.required))
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VKicker(text: S.kycDocsUploaded)
                Spacer()
                Text("\(pair.uploaded) / \(pair.required)")
                    .font(.caption.weight(.heavy)).foregroundColor(VPalette.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(VPalette.surfaceHigh).frame(height: 8)
                    Capsule().fill(VPalette.primaryGradient)
                        .frame(width: geo.size.width * CGFloat(pct), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 4)
    }

    private var documentList: some View {
        VStack(spacing: 0) {
            ForEach(Array(requiredKinds.enumerated()), id: \.element.id) { idx, kind in
                docRow(kind)
                if idx < requiredKinds.count - 1 {
                    Rectangle().fill(VPalette.border).frame(height: 1).padding(.leading, 56)
                }
            }
        }
        .background(VPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func docRow(_ kind: KycDocumentKind) -> some View {
        let doc = docByKind[kind]
        let state = docState(for: doc)
        let isLoading = inFlightKind == kind
        let wasRejected = (doc?.rejectionReason?.isEmpty == false)
        let buttonLabel: String = {
            if wasRejected { return S.kycReupload }
            return doc == nil ? S.kycUpload : S.kycReplace
        }()
        let buttonTint: Color = wasRejected ? VPalette.danger : VPalette.primary
        let buttonBg: Color = wasRejected ? VPalette.danger.opacity(0.12) : VPalette.primaryContainer

        return HStack(spacing: 12) {
            VIconBubble(systemName: state.icon, color: state.color, size: 32, iconSize: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.label).font(.footnote.weight(.heavy)).foregroundColor(VPalette.text)
                Text(state.subtitle).font(.caption2)
                    .foregroundColor(wasRejected ? VPalette.danger : VPalette.textSec)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Button {
                pickerKind = kind
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView().tint(buttonTint)
                    } else {
                        Text(buttonLabel)
                            .font(.footnote.weight(.heavy))
                            .foregroundColor(buttonTint)
                    }
                }
                // Bumped to 88×44 — the 78×32 chip was below the 44pt
                // tap-target spec for VoiceOver / motor accessibility.
                .frame(minWidth: 88, minHeight: 44)
                .background(buttonBg)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel(wasRejected ? "Re-upload \(kind.label) — \(doc?.rejectionReason ?? "rejected")" : "\(buttonLabel) \(kind.label)")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // Honest copy: until durable+encrypted storage (S3 with SSE
            // and a documented retention policy) is wired through to
            // production we don't claim "encrypted at rest". The
            // backend gates uploads behind `KYC_S3_BUCKET` in
            // production so we can't lie by accident.
            Text(S.kycFooterBlurb)
                .font(.caption2)
                .foregroundColor(VPalette.textHint)
                .multilineTextAlignment(.center)

            if !store.kycDocuments.isEmpty {
                Button {
                    Task { await store.submitKycForReview() }
                } label: {
                    Text(S.kycSubmitForReview)
                        .font(.footnote.weight(.heavy))
                        .foregroundColor(VPalette.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private struct DocState {
        var icon: String
        var color: Color
        var subtitle: String
    }

    private func docState(for doc: KycDocument?) -> DocState {
        guard let doc else {
            return DocState(icon: "tray.fill", color: VPalette.textHint, subtitle: S.kycNotUploaded)
        }
        if doc.verifiedAt != nil {
            return DocState(icon: "checkmark.seal.fill", color: VPalette.success, subtitle: S.kycVerified)
        }
        if let reason = doc.rejectionReason, !reason.isEmpty {
            return DocState(icon: "xmark.seal.fill", color: VPalette.danger, subtitle: S.kycRejected(reason: reason))
        }
        return DocState(icon: "clock.fill", color: VPalette.warning, subtitle: S.kycUnderReview)
    }

    private func banner(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundColor(color)
            Text(text).font(.caption.weight(.semibold)).foregroundColor(VPalette.text)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func upload(_ kind: KycDocumentKind, imageData: Data) async {
        inFlightKind = kind
        defer { inFlightKind = nil }

        // Two-step: upload bytes first to durable storage, then link
        // the resulting `storageUri` into a kyc_documents row. Failing
        // step 1 surfaces a "couldn't upload" error; failing step 2
        // surfaces a "uploaded but didn't link" error so support can
        // recover the orphan upload from `kyc_uploads` if needed.
        let storageUri: String
        do {
            let upload = try await VoygoAPIClient.uploadKycDocument(kind: kind, imageData: imageData)
            storageUri = upload.storageUri
        } catch APIError.unauthorized {
            await store.handleUnauthorizedFromExternalCall()
            return
        } catch {
            info = nil
            self.error = S.kycUploadFailed(error.localizedDescription)
            return
        }

        let result = await store.submitKycDocument(kind: kind, storageUrl: storageUri)
        switch result {
        case .success:
            error = nil
            info = S.kycUploadedToast(kind.label)
        case .failure(let err):
            info = nil
            self.error = err.errorDescription ?? S.kycUploadLinkFailed
        }
    }

    // MARK: - Status copy

    private var statusIcon: String {
        switch store.kycStatus {
        case .approved: return "checkmark.seal.fill"
        case .pending:  return "clock.fill"
        case .rejected: return "xmark.seal.fill"
        default:        return "person.badge.key.fill"
        }
    }

    private var statusColor: Color {
        switch store.kycStatus {
        case .approved: return VPalette.success
        case .pending:  return VPalette.warning
        case .rejected: return VPalette.danger
        default:        return VPalette.primary
        }
    }

    private var statusTitle: String {
        switch store.kycStatus {
        case .approved: return S.kycStatusApprovedTitle
        case .pending:  return S.kycStatusPendingTitle
        case .rejected: return S.kycStatusRejectedTitle
        default:        return S.kycStatusNotStartedTitle
        }
    }

    private var statusSubtitle: String {
        switch store.kycStatus {
        case .approved: return S.kycStatusApprovedSubtitle
        case .pending:  return S.kycStatusPendingSubtitle
        case .rejected: return S.kycStatusRejectedSubtitle
        default:        return S.kycStatusNotStartedSubtitle
        }
    }

    /// Escape hatch for stuck-PENDING users. Without it the rider /
    /// driver has no recourse beyond refreshing the screen. mailto
    /// is enough for pilot; once we have in-app support chat the
    /// link can switch to that AppRoute.
    private var pendingSupportBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "envelope.fill")
                .font(.subheadline.weight(.heavy))
                .foregroundColor(VPalette.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(S.kycStuckTitle)
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.text)
                Text(S.kycStuckBody)
                    .font(.caption2)
                    .foregroundColor(VPalette.textSec)
                Button {
                    // Use the SafeOpen helper — `mailto:` silently
                    // fails on devices without Mail installed (iPads,
                    // and users who deleted Mail). The helper copies
                    // the address to the clipboard as a fallback so
                    // the user can paste into Gmail / Outlook / etc.
                    SafeOpen.mailto("support@voygo.app", subject: "KYC review stuck")
                } label: {
                    Text(S.kycEmailSupport)
                        .font(.caption.weight(.heavy))
                        .foregroundColor(VPalette.warning)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(VPalette.warning.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VPalette.warning.opacity(0.3)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension KycStatus {
    /// Visible badge label on the status card. Wired through the
    /// localized `profile.kyc.badge.*` keys so EN and MS stay in sync
    /// with the badge text shown on the Profile screen.
    var label: String {
        switch self {
        case .approved: return S.profileKycBadgeVerified
        case .pending:  return S.profileKycBadgePending
        case .rejected: return S.profileKycBadgeRejected
        case .notStarted: return S.profileKycBadgeNotStarted
        }
    }
}
