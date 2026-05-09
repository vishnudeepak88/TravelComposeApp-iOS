import SwiftUI

// MARK: - Home Tab (super-app hero)
//
// New top-level landing screen ported from the design handoff bundle
// (`car-pool/project/screens-c.jsx`). Replaces "Routes" as the default
// tab so the first thing the rider sees is a vibrant green gradient,
// a tappable search card, and the "Heading your way" feed — not a list.
//
// Drilling into the search card pushes onto the same FindCommute flow
// the Routes tab already owns. The service grid is a marketing surface
// for now: Carpool routes the user to Find, the others surface a
// "Coming soon" sheet via the same `showComingSoonFor` pattern Wallet
// uses, so the tile is honest about what's wired up vs. on the roadmap.

struct HomeTab: View {
    @State private var path: [AppRoute] = []
    /// Filter state pinned at the tab level — Home doesn't host
    /// SearchFilters today, but the shared destination map needs the
    /// bindings so a future "filter pill" on the hero card can flow
    /// straight into the same SearchFiltersView the Routes tab owns.
    @State private var filtersQuery: String = ""
    @State private var filtersEarliest: String = "06:30"
    @State private var filtersLatest: String = "09:00"
    @State private var filtersDays: DaysOfWeekFlags = .weekdays

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onSearchTapped:       { path.append(.findRides) },
                onCarpoolTapped:      { path.append(.findRides) },
                onOpenRoute:          { id in path.append(.routeDetails(routeId: id)) },
                onOpenNotifications:  { path.append(.notifications) }
            )
            .appRouteDestinations(
                path: $path,
                filtersQuery: $filtersQuery,
                filtersEarliest: $filtersEarliest,
                filtersLatest: $filtersLatest,
                filtersDays: $filtersDays
            )
            .navigationBarHidden(true)
            .enableSwipeBack()
        }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    var onSearchTapped: () -> Void = {}
    var onCarpoolTapped: () -> Void = {}
    /// Callback when a "Heading your way" card is tapped. Closures the
    /// route id rather than the row so HomeTab can drill straight into
    /// the shared `AppRoute.routeDetails(...)` without HomeView needing
    /// to know what comes next.
    var onOpenRoute: (String) -> Void = { _ in }
    /// Bell button → push notifications. Wired now that NotificationsView
    /// lives in `AppRoute`; previously this fell through to the
    /// "Coming soon" alert because there was no path to push.
    var onOpenNotifications: () -> Void = {}

    @State private var showComingSoonFor: String? = nil

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Hi there"
        }
    }

    private var firstName: String {
        let full = store.currentUser.name
        guard !full.isEmpty else { return "there" }
        return full.split(separator: " ").first.map(String.init) ?? full
    }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        hero
                    // No overlap: the search card sits flush below
                    // the hero. Two earlier fixes (overlay+offset,
                    // then negative padding+zIndex) chased a "lifted
                    // card" visual but kept dropping taps in real
                    // builds — SwiftUI's hit-test kept picking the
                    // hero's gradient over the search card in the
                    // overlap region. Reliable taps > pretty overlap.
                    searchCard
                        .padding(.top, 16)
                    serviceGrid
                        .padding(.top, 16)
                    promoBanner
                    suggestedRides
                    Spacer().frame(height: VTabBarLayout.clearance)
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                // iOS convention: tap the active tab again to scroll
                // to top. Wave 4 wired the notification but no root
                // subscribed; Home is now the first opt-in.
                .onReceive(NotificationCenter.default.publisher(for: .voygoTabReselected)) { note in
                    if (note.userInfo?["index"] as? Int) == 0 {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            }
        }
        .alert(
            "Coming soon",
            isPresented: Binding(
                get: { showComingSoonFor != nil },
                set: { if !$0 { showComingSoonFor = nil } }
            ),
            presenting: showComingSoonFor
        ) { _ in
            Button("OK", role: .cancel) { showComingSoonFor = nil }
        } message: { feature in
            Text("\(feature) is on the roadmap. We'll let you know when it lands.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            VPalette.primaryGradient
                .ignoresSafeArea(edges: .top)

            // Decorative blobs — soft white + amber
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 200, height: 200)
                .offset(x: 200, y: -20)
            Circle()
                .fill(VPalette.accentAmber.opacity(0.18))
                .frame(width: 120, height: 120)
                .offset(x: 240, y: 80)

            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    HueAvatar(name: firstName, hue: 140, size: 40)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.5), lineWidth: 2)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greeting)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        HStack(spacing: 4) {
                            Text(firstName).font(.system(size: 17, weight: .heavy))
                            Text("👋")
                        }
                        .foregroundColor(.white)
                    }
                    Spacer(minLength: 0)
                    Button(action: onOpenNotifications) {
                        Image(systemName: "bell")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text(S.homeWhereTo)
                    .font(.system(size: 26, weight: .black))
                    .tracking(-0.5)
                    .foregroundColor(.white)
                    .lineSpacing(1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 24)
        }
    }

    // MARK: Lifted search card

    private var searchCard: some View {
        Button(action: onSearchTapped) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(VPalette.primaryContainer)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(VPalette.primary)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text("To")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(VPalette.textHint)
                    Text("Where are you heading?")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(VPalette.text)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // Localized via `Strings.swift` → `Localizable.strings`.
                // English "Book a ride" / Malay "Tempah perjalanan".
                Text(S.homeBookARide)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(VPalette.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(14)
            .background(VPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: VPalette.text.opacity(0.12), radius: 20, x: 0, y: 12)
            // Force the entire rendered shape (including padding) to
            // be the hit area; without this, SwiftUI sometimes keeps
            // the implicit shape limited to non-transparent pixels
            // and parts of the card stop responding to taps.
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.findRide")
    }

    // MARK: Service grid

    private var serviceGrid: some View {
        let tiles: [ServiceTile] = [
            .init(icon: "car.fill",            label: "Carpool",   fg: VPalette.primary,      bg: VPalette.primaryContainer,      isPrimary: true,  badge: "NEW"),
            .init(icon: "person.fill",         label: "Ride solo", fg: VPalette.accentCoral,  bg: VPalette.accentCoralContainer),
            .init(icon: "calendar",            label: "Schedule",  fg: VPalette.accentPurple, bg: VPalette.accentPurpleContainer),
            .init(icon: "location.north.fill", label: "Long-haul", fg: VPalette.accentAmber,  bg: VPalette.accentAmberContainer)
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
            ForEach(tiles) { tile in
                Button {
                    if tile.isPrimary { onCarpoolTapped() }
                    else { showComingSoonFor = tile.label }
                } label: {
                    serviceTileBody(tile)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func serviceTileBody(_ tile: ServiceTile) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                tile.bg
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(
                        color: tile.isPrimary ? VPalette.primary.opacity(0.25) : .clear,
                        radius: 16, x: 0, y: 6
                    )
                Image(systemName: tile.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(tile.fg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let badge = tile.badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.4)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(VPalette.accentCoral)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(6)
                }
            }
            Text(tile.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(VPalette.text)
        }
    }

    // MARK: Promo banner

    private var promoBanner: some View {
        ZStack {
            LinearGradient(
                colors: [VPalette.accentAmber, Color(hex: 0xFF8A2A)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 100, height: 100)
                .offset(x: 130, y: 40)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(S.homePromoKicker)
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(0.4)
                        .foregroundColor(.white.opacity(0.92))
                    Text(S.homePromoTitle)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundColor(.white)
                }
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.95))
                    Image(systemName: "car.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Color(hex: 0xFF8A2A))
                }
                .frame(width: 52, height: 52)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 20)
    }

    // MARK: Suggested rides

    private var suggestedRides: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(S.homeHeadingYourWay)
                    .font(.system(size: 16, weight: .black))
                    .tracking(-0.2)
                    .foregroundColor(VPalette.text)
                Spacer()
                Button(action: onSearchTapped) {
                    Text(S.homeSeeAll)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(VPalette.primary)
                }
                .buttonStyle(.plain)
            }
            ForEach(suggestedRideRows) { row in
                suggestedRideCard(row)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    private func suggestedRideCard(_ row: SuggestedRide) -> some View {
        // Tap the row → route details if we have a backing routeId,
        // otherwise fall through to the find-rides search (the demo
        // rows don't carry a real id).
        Button {
            if let id = row.routeId {
                onOpenRoute(id)
            } else {
                onSearchTapped()
            }
        } label: {
            HStack(spacing: 12) {
                HueAvatar(name: row.name, hue: row.hue, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(VPalette.text)
                        VVerifiedTick(size: 11)
                        Text("★ \(row.rating, specifier: "%.1f")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(VPalette.textHint)
                    }
                    Text(row.route)
                        .font(.system(size: 12))
                        .foregroundColor(VPalette.textSec)
                    Text("Departs \(row.time)")
                        .font(.system(size: 11))
                        .foregroundColor(VPalette.textHint)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("RM \(row.priceMyr)")
                        .font(.system(size: 18, weight: .black, design: .default))
                        .foregroundColor(VPalette.primary)
                    Text("per seat")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(VPalette.textHint)
                }
            }
            .padding(14)
            .background(VPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: VPalette.text.opacity(0.04), radius: 14, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    /// Shows real driver routes from the store when available; falls back
    /// to a polished demo so the screen never reads as empty on a fresh
    /// install.
    private var suggestedRideRows: [SuggestedRide] {
        let live = store.routes.prefix(2).enumerated().map { idx, r in
            SuggestedRide(
                name:     r.driverName.isEmpty ? "Driver" : r.driverName,
                hue:      [280, 30, 140, 200][idx % 4],
                time:     r.departureTime,
                route:    "\(shortLabel(r.startLocation)) → \(shortLabel(r.endLocation))",
                priceMyr: r.pricePerSeat,
                rating:   r.reliability.averageRating > 0 ? r.reliability.averageRating : 4.9,
                routeId:  r.id
            )
        }
        if !live.isEmpty { return Array(live) }
        return [
            .init(name: "Maya R.",   hue: 280, time: "8:25 AM", route: "Mont Kiara → KLCC",     priceMyr: 14, rating: 4.9),
            .init(name: "David K.",  hue: 30,  time: "8:40 AM", route: "Subang Jaya → Bangsar", priceMyr: 12, rating: 4.8)
        ]
    }

    private func shortLabel(_ raw: String) -> String {
        let trimmed = raw.split(separator: ",").first.map(String.init) ?? raw
        return trimmed.trimmingCharacters(in: .whitespaces)
    }
}

private struct ServiceTile: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let fg: Color
    let bg: Color
    var isPrimary: Bool = false
    var badge: String? = nil
}

private struct SuggestedRide: Identifiable {
    let id = UUID()
    let name: String
    let hue: Double
    let time: String
    let route: String
    let priceMyr: Int
    let rating: Double
    /// Backing route id when the row originated from `store.routes`.
    /// `nil` for the polished demo fallback rows so taps fall through
    /// to the find-rides search instead of pushing a 404 detail screen.
    var routeId: String? = nil
}

// MARK: - Atoms (Home-local; promote to Polished.swift if they earn reuse)

/// Pastel avatar circle keyed by hue, mirroring the `Avatar` component
/// from `tokens.jsx`. Distinct from the existing gradient-style
/// `VAvatar` — that one is a brand-loud hero avatar; this one is a
/// quiet list-row avatar that lets multiple drivers feel visually
/// distinct without each one shouting in the brand color.
struct HueAvatar: View {
    let name: String
    var hue: Double = 210
    var size: CGFloat = 36

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(Color(hue: hue/360, saturation: 0.32, brightness: 0.86))
            Text(initial)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(Color(hue: hue/360, saturation: 0.55, brightness: 0.32))
        }
        .frame(width: size, height: size)
    }
}

/// Small green pill with a white check. Sits next to verified driver
/// names in suggested rides + profile cards.
struct VVerifiedTick: View {
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            Circle().fill(VPalette.success)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.65, weight: .black))
                .foregroundColor(.white)
        }
        .frame(width: size + 4, height: size + 4)
    }
}

#Preview("Home") {
    HomeView()
        .environment(AppStore())
}
