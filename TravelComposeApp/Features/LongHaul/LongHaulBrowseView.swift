import SwiftUI

// MARK: - Long-haul browse
//
// Entry point from the Home service grid's "Long-haul" tile. Riders
// type origin/destination + pick a from-date; the server returns up
// to 100 OPEN trips. Bookings live one drilldown deeper in
// `LongHaulTripDetailView` so this surface stays scannable.

struct LongHaulBrowseView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onOpenTrip: (String) -> Void
    var onPostTrip: () -> Void

    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var fromDate: Date = Date()
    @State private var isSearching: Bool = false
    @State private var hasLoaded: Bool = false
    @State private var error: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Long-haul", kicker: "One-off inter-city trips", onBack: onBack) {
                    Button(action: onPostTrip) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(VPalette.primary)
                            .frame(width: 40, height: 40)
                            .background(VPalette.primaryContainer)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Post a trip")
                }

                searchPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if let err = error {
                    VErrorBanner(message: err, onRetry: { Task { await search() } })
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                resultsList
            }
        }
        .task {
            if !hasLoaded {
                await search()
                hasLoaded = true
            }
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                fieldChip(icon: "circle.fill", placeholder: "From", text: $origin)
                fieldChip(icon: "mappin.circle.fill", placeholder: "To", text: $destination)
            }
            HStack(spacing: 10) {
                DatePicker("Departing on", selection: $fromDate, in: Date()..., displayedComponents: [.date])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(VPalette.primary)
                Spacer(minLength: 0)
                Button {
                    Task { await search() }
                } label: {
                    HStack(spacing: 6) {
                        if isSearching { ProgressView().tint(.white).controlSize(.small) }
                        else { Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .heavy)) }
                        Text("Search")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(VPalette.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSearching)
            }
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private func fieldChip(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(VPalette.textHint)
            TextField(placeholder, text: text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(VPalette.text)
                .tint(VPalette.primary)
                .textInputAutocapitalization(.words)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VPalette.surfaceHigh)
        .clipShape(Capsule())
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if isSearching && store.longHaulSearchResults.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 10) {
                            VSkeleton(height: 18)
                            VSkeleton(height: 14)
                            VSkeleton(height: 12)
                        }
                        .padding(14)
                        .background(VPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                } else if store.longHaulSearchResults.isEmpty {
                    EmptyStateView(icon: "location.north",
                                   title: "No trips yet",
                                   subtitle: "Try a different corridor or date — or post your own.",
                                   ctaLabel: "Post a trip",
                                   ctaAction: onPostTrip)
                } else {
                    ForEach(store.longHaulSearchResults) { trip in
                        Button {
                            onOpenTrip(trip.id)
                        } label: {
                            LongHaulTripRow(trip: trip)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.bottom, VTabBarLayout.clearance)
        }
        .refreshable { await search() }
    }

    private func search() async {
        isSearching = true
        error = nil
        let result = await store.searchLongHaul(origin: origin, destination: destination, fromDate: fromDate)
        if case .failure(let err) = result {
            error = err.localizedDescription
        }
        isSearching = false
    }
}

struct LongHaulTripRow: View {
    let trip: LongHaulTrip

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(trip.origin)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(VPalette.text)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.heavy))
                        .foregroundColor(VPalette.textHint)
                    Text(trip.destination)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(VPalette.text)
                        .lineLimit(1)
                }
                Text(formatDeparture(trip.departAt))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(VPalette.textSec)
                HStack(spacing: 8) {
                    Label("\(trip.seatsAvailable) of \(trip.seatsTotal) seats", systemImage: "person.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(VPalette.textSec)
                    if let rating = trip.driverRating, rating > 0 {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(VPalette.warning)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text("RM \(trip.pricePerSeatMyr)")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(VPalette.primary)
                Text("per seat")
                    .font(.caption2)
                    .foregroundColor(VPalette.textHint)
            }
        }
        .padding(14)
        .background(VPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
    }

    private func formatDeparture(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM · h:mm a"
        return f.string(from: date)
    }
}

#Preview("LongHaulBrowseView") {
    LongHaulBrowseView(onBack: {}, onOpenTrip: { _ in }, onPostTrip: {})
        .environment(AppStore())
}
