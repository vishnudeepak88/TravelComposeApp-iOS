import SwiftUI

// MARK: - Notifications (mirrors NotificationsScreen.jsx)

struct NotificationsView: View {
    var onBack: () -> Void

    private struct Notif: Identifiable {
        let id = UUID()
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let time: String
        let unread: Bool
    }

    private struct Group: Identifiable {
        let id = UUID()
        let label: String
        let items: [Notif]
    }

    /// Empty until the backend exposes `/users/me/notifications`.
    /// The hardcoded reel ("Aiman is on the way", "Marcus referred
    /// you to Voygo") looked real on a fresh install — including
    /// fake driver names and amounts. Better to render an honest
    /// empty state than show the wrong driver to a real user.
    private let groups: [Group] = []
    @State private var allRead: Bool = false

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Notifications", onBack: onBack) {
                    // Real Button (was a plain Text). No-ops while the
                    // groups list is empty; flips local `allRead` state
                    // and would call `/notifications/read-all` once the
                    // backend lands.
                    Button {
                        allRead = true
                    } label: {
                        Text("Mark all read")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(groups.isEmpty ? VPalette.textHint : VPalette.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(groups.isEmpty)
                    .accessibilityLabel("Mark all notifications as read")
                }

                if groups.isEmpty {
                    EmptyStateView(
                        icon: "bell.slash",
                        title: "No notifications yet",
                        subtitle: "Ride updates, pickup reminders, and chat alerts will appear here."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(groups) { g in
                                VStack(alignment: .leading, spacing: 8) {
                                    VKicker(text: g.label).padding(.horizontal, 4)
                                    VStack(spacing: 0) {
                                        ForEach(Array(g.items.enumerated()), id: \.element.id) { idx, n in
                                            notifRow(n)
                                            if idx < g.items.count - 1 {
                                                Rectangle().fill(VPalette.border).frame(height: 1)
                                            }
                                        }
                                    }
                                    .background(VPalette.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VPalette.border, lineWidth: 1))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func notifRow(_ n: Notif) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if n.unread {
                Circle().fill(VPalette.primary).frame(width: 6, height: 6).padding(.top, 14)
            } else {
                Color.clear.frame(width: 6, height: 6)
            }
            VIconBubble(systemName: n.icon, color: n.color, size: 38, iconSize: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(n.title).font(.system(size: 13, weight: .heavy)).foregroundColor(VPalette.text)
                    Spacer()
                    Text(n.time).font(.system(size: 10, weight: .bold)).foregroundColor(VPalette.textHint)
                }
                Text(n.subtitle).font(.system(size: 12)).foregroundColor(VPalette.textSec)
                    .lineLimit(2).multilineTextAlignment(.leading)
            }
        }
        .padding(14)
        .background(n.unread ? VPalette.primaryContainer.opacity(0.35) : VPalette.surface)
    }
}

#Preview("NotificationsView") {
    NotificationsView(onBack: {})
        .environment(AppStore())
}
