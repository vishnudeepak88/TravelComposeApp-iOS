import SwiftUI

// MARK: - Favorites
//
// Riders comparison-shop a few routes before subscribing. The ⭐
// button on the search card adds a route here so they can come back
// to it later. Pulled on view-appear from /commute/routes/favorites/me.

struct FavoritesView: View {
    @Environment(AppStore.self) private var store
    var onBack: () -> Void
    var onOpenRoute: (String) -> Void

    @State private var hasLoaded: Bool = false

    private var favorites: [RecurringRoute] {
        store.routes.filter { store.favoriteRouteIds.contains($0.id) }
            .sorted { $0.driverName < $1.driverName }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Favourites", onBack: onBack)
                if favorites.isEmpty && hasLoaded {
                    EmptyStateView(
                        icon: "star",
                        title: "No favourites yet",
                        subtitle: "Tap the star on a route in Search to save it for later."
                    )
                    .frame(maxHeight: .infinity)
                } else if favorites.isEmpty {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(0..<3, id: \.self) { _ in
                                VStack(alignment: .leading, spacing: 10) {
                                    VSkeleton(height: 18)
                                    VSkeleton(height: 14)
                                }
                                .padding(14)
                                .background(VPalette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Array(favorites.enumerated()), id: \.element.id) { _, route in
                                Button { onOpenRoute(route.id) } label: {
                                    FavoriteRouteRow(route: route)
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        Task { await store.toggleFavorite(routeId: route.id) }
                                    } label: {
                                        Label("Unfavourite", systemImage: "star.slash")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 16)
                        .padding(.bottom, VTabBarLayout.clearance)
                    }
                    .refreshable { await store.refreshFavorites() }
                }
            }
        }
        .task {
            await store.refreshFavorites()
            hasLoaded = true
        }
    }
}

private struct FavoriteRouteRow: View {
    let route: RecurringRoute

    var body: some View {
        HStack(spacing: 12) {
            VAvatar(initial: String(route.driverName.prefix(1)), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(route.driverName)
                        .font(.subheadline.weight(.black))
                        .foregroundColor(VPalette.text)
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(VPalette.starGold)
                }
                Text("\(route.startLocation) → \(route.endLocation)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(VPalette.textSec)
                Text("\(route.departureTime) · \(route.daysOfWeek.shortLabel)")
                    .font(.caption2)
                    .foregroundColor(VPalette.textHint)
            }
            Spacer()
            Text(Formatters.ringgit(route.pricePerSeat))
                .font(.subheadline.weight(.heavy))
                .foregroundColor(VPalette.primary)
        }
        .padding(14)
        .background(VPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VPalette.border))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview("FavoritesView") {
    FavoritesView(onBack: {}, onOpenRoute: { _ in })
        .environment(AppStore())
}
