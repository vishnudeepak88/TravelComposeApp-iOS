import SwiftUI

// MARK: - Driver demand view
//
// Surface for drivers: which corridors do riders want that nobody is
// serving? Aggregated counts straight from /commute/route-requests/demand.
// Tapping a row jumps to the Create Route form with the corridor
// pre-filled — closing the cold-start liquidity loop end-to-end.

struct DriverDemandView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onCreateRoute: () -> Void

    @State private var hasLoaded: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Rider demand", kicker: "Corridors riders want", onBack: onBack)
                content
            }
        }
        .task {
            await store.refreshRouteRequestDemand()
            hasLoaded = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.routeRequestDemand.isEmpty && hasLoaded {
            EmptyStateView(
                icon: "person.2.slash",
                title: "No open requests",
                subtitle: "Riders haven't posted any corridors yet. Create routes on your usual paths — they'll come."
            )
            .frame(maxHeight: .infinity)
        } else if store.routeRequestDemand.isEmpty {
            // Skeleton during first load.
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            VSkeleton(height: 18)
                            VSkeleton(height: 12)
                        }
                        .padding(14)
                        .background(VPalette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Tap a corridor to start a route there. New routes auto-notify the waiting riders.")
                        .font(.caption)
                        .foregroundColor(VPalette.textSec)
                        .padding(.horizontal, 16)
                    ForEach(store.routeRequestDemand) { row in
                        Button(action: onCreateRoute) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(VPalette.primaryContainer)
                                        .frame(width: 44, height: 44)
                                    Text("\(row.riders)")
                                        .font(.callout.weight(.black))
                                        .foregroundColor(VPalette.primary)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(row.origin) → \(row.destination)")
                                        .font(.subheadline.weight(.heavy))
                                        .foregroundColor(VPalette.text)
                                        .lineLimit(1)
                                    Text(row.riders == 1
                                         ? "1 rider waiting"
                                         : "\(row.riders) riders waiting")
                                        .font(.caption)
                                        .foregroundColor(VPalette.textSec)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(VPalette.primary)
                            }
                            .padding(14)
                            .background(VPalette.surface)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 16)
                .padding(.bottom, VTabBarLayout.clearance)
            }
            .refreshable { await store.refreshRouteRequestDemand() }
        }
    }
}

#Preview("DriverDemandView") {
    DriverDemandView(onBack: {}, onCreateRoute: {})
        .environment(AppStore())
}
