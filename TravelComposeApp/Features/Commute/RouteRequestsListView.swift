import SwiftUI

// MARK: - Rider's own route demand posts
//
// Each row is a corridor the rider asked drivers to add. OPEN status
// means waiting; FULFILLED means a matching route was created (the
// rider got a notification when that happened). Riders can withdraw
// stale OPEN requests via a swipe action.

struct RouteRequestsListView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void

    @State private var hasLoaded: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "My requests", kicker: "Corridors I'm waiting on", onBack: onBack)
                content
            }
        }
        .task {
            await store.refreshRouteRequests()
            hasLoaded = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.routeRequests.isEmpty && hasLoaded {
            EmptyStateView(
                icon: "hand.raised",
                title: "No outstanding requests",
                subtitle: "Search for a route — if nothing matches, post a request from the empty state."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.routeRequests) { req in
                        requestRow(req)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
                .padding(.bottom, VTabBarLayout.clearance)
            }
            .refreshable { await store.refreshRouteRequests() }
        }
    }

    private func requestRow(_ req: RouteRequest) -> some View {
        let isOpen = req.status == "OPEN"
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(req.origin) → \(req.destination)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(VPalette.text)
                        .lineLimit(1)
                    statusPill(req.status)
                }
                if let time = req.preferredTime, !time.isEmpty {
                    Text("Preferred \(time)")
                        .font(.caption2)
                        .foregroundColor(VPalette.textHint)
                }
                if !req.notes.isEmpty {
                    Text(req.notes)
                        .font(.caption2)
                        .foregroundColor(VPalette.textSec)
                        .lineLimit(2)
                }
            }
            Spacer()
            if isOpen {
                Button {
                    Task { await store.withdrawRouteRequest(req.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(VPalette.textHint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Withdraw request")
            }
        }
        .padding(14)
        .background(VPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusPill(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "OPEN":      return ("Open", VPalette.warning)
            case "FULFILLED": return ("Fulfilled", VPalette.success)
            default:          return (status.capitalized, VPalette.textHint)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color)
            .clipShape(Capsule())
    }
}

#Preview("RouteRequestsListView") {
    RouteRequestsListView(onBack: {})
        .environment(AppStore())
}
