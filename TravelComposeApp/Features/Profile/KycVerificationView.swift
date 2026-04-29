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
    @EnvironmentObject var store: AppStore
    var onBack: () -> Void

    @State private var role: KycSubmission.Role = .rider
    @State private var inFlightKind: KycDocumentKind? = nil
    @State private var error: String? = nil
    @State private var info: String? = nil

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
                VPolishedNavBar(title: "Identity Verification", kicker: "Trust & safety", onBack: onBack)

                ScrollView {
                    VStack(spacing: 16) {
                        statusCard
                        roleSwitcher
                        progressBar
                        if let error { banner(error, color: VPalette.danger) }
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
    }

    // MARK: - Sections

    private var statusCard: some View {
        HStack(spacing: 14) {
            VIconBubble(systemName: statusIcon, color: statusColor, size: 48, iconSize: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(VPalette.text)
                Text(statusSubtitle)
                    .font(.system(size: 12))
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
            VKicker(text: "Who's verifying").padding(.leading, 4)
            HStack(spacing: 6) {
                roleChip(label: "Rider", value: .rider, subtitle: "3 documents")
                roleChip(label: "Driver", value: .driver, subtitle: "7 documents")
            }
        }
    }

    private func roleChip(label: String, value: KycSubmission.Role, subtitle: String) -> some View {
        let on = role == value
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { role = value }
        } label: {
            VStack(spacing: 2) {
                Text(label).font(.system(size: 14, weight: .heavy))
                Text(subtitle).font(.system(size: 11)).opacity(0.85)
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
        let pct = pair.required == 0 ? 1.0 : Double(pair.uploaded) / Double(pair.required)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VKicker(text: "Documents uploaded")
                Spacer()
                Text("\(pair.uploaded) / \(pair.required)")
                    .font(.system(size: 12, weight: .heavy)).foregroundColor(VPalette.text)
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

        return HStack(spacing: 12) {
            VIconBubble(systemName: state.icon, color: state.color, size: 32, iconSize: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.label).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                Text(state.subtitle).font(.system(size: 11)).foregroundColor(VPalette.textSec)
            }
            Spacer()
            Button {
                Task { await upload(kind) }
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView().tint(VPalette.primary)
                    } else {
                        Text(doc == nil ? "Upload" : "Replace")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(VPalette.primary)
                    }
                }
                .frame(width: 78, height: 32)
                .background(VPalette.primaryContainer)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text("We use your documents to verify identity, run a quick safety check, and meet Bank Negara KYC rules. Photos are stored encrypted and only seen by trust & safety reviewers.")
                .font(.system(size: 11))
                .foregroundColor(VPalette.textHint)
                .multilineTextAlignment(.center)

            if !store.kycDocuments.isEmpty {
                Button {
                    Task { await store.submitKyc(status: .pending) }
                } label: {
                    Text("Mark verification submitted")
                        .font(.system(size: 13, weight: .heavy))
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
            return DocState(icon: "tray.fill", color: VPalette.textHint, subtitle: "Not uploaded")
        }
        if doc.verifiedAt != nil {
            return DocState(icon: "checkmark.seal.fill", color: VPalette.success, subtitle: "Verified")
        }
        if let reason = doc.rejectionReason, !reason.isEmpty {
            return DocState(icon: "xmark.seal.fill", color: VPalette.danger, subtitle: "Rejected — \(reason)")
        }
        return DocState(icon: "clock.fill", color: VPalette.warning, subtitle: "Under review")
    }

    private func banner(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundColor(color)
            Text(text).font(.system(size: 12, weight: .semibold)).foregroundColor(VPalette.text)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func upload(_ kind: KycDocumentKind) async {
        inFlightKind = kind
        defer { inFlightKind = nil }
        // No real photo picker yet — pass nil so the backend creates a record
        // without a storage URL. A real implementation would put up a
        // PHPickerViewController, upload to S3, then call this with the URL.
        let result = await store.submitKycDocument(kind: kind, storageUrl: nil)
        switch result {
        case .success:
            error = nil
            info = "\(kind.label) uploaded — review pending"
        case .failure(let err):
            info = nil
            error = err.localizedDescription
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
        case .approved: return "You're fully verified"
        case .pending:  return "Verification under review"
        case .rejected: return "Verification rejected"
        default:        return "Verify to start riding"
        }
    }

    private var statusSubtitle: String {
        switch store.kycStatus {
        case .approved: return "MyKad on file · trusted account"
        case .pending:  return "We typically respond within 24 hours"
        case .rejected: return "Resubmit the rejected docs below to retry"
        default:        return "MyKad + selfie covers riders. Drivers add license + vehicle."
        }
    }
}

private extension KycStatus {
    var label: String {
        switch self {
        case .approved: return "Verified"
        case .pending:  return "Pending"
        case .rejected: return "Rejected"
        case .notStarted: return "Not Started"
        }
    }
}
