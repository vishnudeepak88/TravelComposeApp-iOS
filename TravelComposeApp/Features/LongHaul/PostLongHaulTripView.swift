import SwiftUI

// MARK: - Post a long-haul trip
//
// Driver-side create form. Mirrors the backend's validation envelope
// (1..20 seats, RM 5..5000, future depart_at) with cheap inline
// guards so the user gets immediate feedback before the round-trip.

struct PostLongHaulTripView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onCreated: (String) -> Void = { _ in }

    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var departAt: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var seatsTotal: Int = 3
    @State private var pricePerSeatMyr: Int = 50
    @State private var notes: String = ""
    @State private var submitState: SubmitState = .idle

    enum SubmitState: Equatable {
        case idle, submitting
        case failure(String)
    }

    private var canSubmit: Bool {
        !origin.trimmingCharacters(in: .whitespaces).isEmpty &&
        !destination.trimmingCharacters(in: .whitespaces).isEmpty &&
        seatsTotal >= 1 && seatsTotal <= 20 &&
        pricePerSeatMyr >= 5 && pricePerSeatMyr <= 5000 &&
        departAt.timeIntervalSinceNow > 0 &&
        submitState != .submitting
    }

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Post a trip", kicker: "Long-haul · one-off", onBack: onBack)

                ScrollView {
                    VStack(spacing: 14) {
                        corridorCard
                        scheduleCard
                        capacityCard
                        notesCard
                        submitCTA
                        if case .failure(let msg) = submitState {
                            VErrorBanner(message: msg)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    private var corridorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardLabel("Where")
            field(icon: "circle.fill", placeholder: "Origin (e.g. Kuala Lumpur)", text: $origin)
            field(icon: "mappin.circle.fill", placeholder: "Destination (e.g. Penang)", text: $destination)
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardLabel("Departure")
            DatePicker("Departing at", selection: $departAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(VPalette.primary)
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private var capacityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardLabel("Capacity & price")
            HStack {
                Text("Seats")
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.text)
                Spacer()
                Stepper(value: $seatsTotal, in: 1...20) {
                    Text("\(seatsTotal)")
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(VPalette.text)
                }
            }
            HStack {
                Text("Price per seat")
                    .font(.footnote.weight(.heavy))
                    .foregroundColor(VPalette.text)
                Spacer()
                Stepper(value: $pricePerSeatMyr, in: 5...500, step: 5) {
                    Text(Formatters.ringgit(pricePerSeatMyr))
                        .font(.subheadline.weight(.heavy))
                        .foregroundColor(VPalette.primary)
                }
            }
            HStack {
                Text("Estimated revenue")
                    .font(.caption)
                    .foregroundColor(VPalette.textHint)
                Spacer()
                Text("\(Formatters.ringgit(seatsTotal * pricePerSeatMyr)) at full")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(VPalette.textSec)
            }
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardLabel("Notes (optional)")
            TextField("Pickup point, luggage limits, etc.", text: $notes, axis: .vertical)
                .lineLimit(2...5)
                .font(.footnote)
                .foregroundColor(VPalette.text)
                .tint(VPalette.primary)
                .padding(10)
                .background(VPalette.surfaceHigh)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private var submitCTA: some View {
        VPrimaryButton("Post trip",
                       icon: "paperplane.fill",
                       isLoading: submitState == .submitting,
                       isEnabled: canSubmit) {
            Task { await submit() }
        }
    }

    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .foregroundColor(VPalette.textHint)
    }

    private func field(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.heavy))
                .foregroundColor(VPalette.textHint)
            TextField(placeholder, text: text)
                .font(.footnote.weight(.semibold))
                .foregroundColor(VPalette.text)
                .tint(VPalette.primary)
                .textInputAutocapitalization(.words)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VPalette.surfaceHigh)
        .clipShape(Capsule())
    }

    private func submit() async {
        submitState = .submitting
        let result = await store.postLongHaul(
            origin: origin.trimmingCharacters(in: .whitespaces),
            destination: destination.trimmingCharacters(in: .whitespaces),
            departAt: departAt,
            seatsTotal: seatsTotal,
            pricePerSeatMyr: pricePerSeatMyr,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        switch result {
        case .success(let id):
            submitState = .idle
            onCreated(id)
        case .failure(let err):
            submitState = .failure(err.localizedDescription)
        }
    }
}

#Preview("PostLongHaulTripView") {
    PostLongHaulTripView(onBack: {})
        .environment(AppStore())
}
