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

    private let groups: [Group] = [
        Group(label: "Today", items: [
            Notif(icon: "car.fill",      color: VPalette.primary,   title: "Aiman is on the way",         subtitle: "ETA 7:42 AM at USJ 9 LRT · Tesla VEC 4123",  time: "2m",  unread: true),
            Notif(icon: "shield.fill",   color: VPalette.success,   title: "Ride completed",              subtitle: "Subang → KLCC · RM 11.50 charged",            time: "1h",  unread: true),
            Notif(icon: "bubble.left.fill", color: VPalette.accent, title: "New message from Priya S.",   subtitle: "Thanks for the smooth ride yesterday!",        time: "4h",  unread: false)
        ]),
        Group(label: "Yesterday", items: [
            Notif(icon: "clock.fill",    color: VPalette.warning,   title: "Pickup reminder",             subtitle: "Tomorrow 7:42 AM · USJ 9 LRT",                time: "10h", unread: false),
            Notif(icon: "shield.fill",   color: VPalette.success,   title: "DuitNow payout received",     subtitle: "RM 312 credited to Maybank ··4221",            time: "1d",  unread: false)
        ]),
        Group(label: "This week", items: [
            Notif(icon: "person.2.fill", color: VPalette.secondary, title: "Driver Aiman updated route",  subtitle: "New pickup added: Subang Mewah · 7:56",        time: "Tue", unread: false),
            Notif(icon: "heart.fill",    color: VPalette.accent,    title: "Marcus referred you to Voygo", subtitle: "You both earned RM 15 in credits",            time: "Mon", unread: false)
        ])
    ]

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: "Notifications", onBack: onBack) {
                    Text("Mark all read")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(VPalette.primary)
                }

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
