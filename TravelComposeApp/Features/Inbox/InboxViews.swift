import SwiftUI

// MARK: - Inbox (mirrors InboxScreen.kt)

struct InboxView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// Drives the empty-state CTA. Posted via NotificationCenter rather
    /// than passed down because Inbox is a tab root and doesn't own a
    /// shared NavigationPath with the other tabs.
    static let openFindRoutesNotification = Notification.Name("voygo.inbox.findRoutes")
    /// Path-based stack so the chat thread can use the same custom
    /// VPolishedNavBar pattern as the rest of the app, instead of the
    /// system blue back arrow that came with the legacy NavigationLink.
    @State private var path: [InboxRoute] = []

    enum InboxRoute: Hashable {
        case thread(id: String, title: String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                VPalette.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    VPolishedNavBar(title: "Inbox", kicker: inboxKicker)

                    if store.threads.isEmpty {
                        EmptyStateView(
                            icon: "bubble.left.and.bubble.right",
                            title: "No messages",
                            subtitle: "Subscribe to a route or post a long-haul trip — chats appear here once you're matched with a driver or rider.",
                            ctaLabel: "Find a route",
                            ctaAction: {
                                // Pull-through to Carpool tab via the existing
                                // tab-reselect notification pattern. MainTabView
                                // listens and switches selectedTab to 1 (Search).
                                NotificationCenter.default.post(
                                    name: InboxView.openFindRoutesNotification,
                                    object: nil
                                )
                            }
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(spacing: 10) {
                                    Color.clear.frame(height: 0).id("top")
                                    ForEach(store.threads) { thread in
                                        Button {
                                            path.append(.thread(id: thread.id, title: thread.title))
                                        } label: {
                                            ThreadRow(thread: thread)
                                                .padding(.horizontal, 16)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 12)
                                .padding(.bottom, VTabBarLayout.clearance)
                            }
                            .refreshable {
                                await store.refreshAll()
                            }
                            // iOS convention: re-tap the active tab → top.
                            .onReceive(NotificationCenter.default.publisher(for: .voygoTabReselected)) { note in
                                if (note.userInfo?["index"] as? Int) == 3 {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        proxy.scrollTo("top", anchor: .top)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: InboxRoute.self) { route in
                switch route {
                case .thread(let id, let title):
                    ChatThreadView(
                        threadId: id,
                        title: title,
                        onBack: { if !path.isEmpty { path.removeLast() } }
                    )
                    .navigationBarHidden(true)
                }
            }
            .enableSwipeBack()
        }
        .task {
            // Initial fetch + periodic poll while the Inbox tab is on
            // screen. Without this loop, threads + unread counts only
            // update on pull-to-refresh / app open — a reply from the
            // driver wouldn't surface until the user happened to swipe
            // down. 8s is slow enough to be polite on battery and
            // fast enough that "where's my reply?" doesn't happen.
            await store.refreshAll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { break }
                await store.refreshThreads()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Foreground refresh — closing/reopening the app, or
            // returning from a push-notification tap, should not
            // require pulling to refresh to see new threads.
            if phase == .active {
                Task { await store.refreshThreads() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voygoOpenThread)) { note in
            guard let info = note.userInfo,
                  let threadId = info["threadId"] as? String else { return }
            let title = (info["title"] as? String) ?? "Conversation"
            // Avoid stacking duplicate destinations if the user re-taps.
            if path.last != .thread(id: threadId, title: title) {
                path.append(.thread(id: threadId, title: title))
            }
        }
    }

    /// Total unread count formatted as a kicker above the title — replaces
    /// the legacy red badge in the trailing slot. Empty when zero.
    private var inboxKicker: String? {
        let total = store.threads.map(\.unreadCount).reduce(0, +)
        return total > 0 ? "\(total) unread" : nil
    }
}

struct ThreadRow: View {
    let thread: ChatThread
    var body: some View {
        VoygoCard {
            HStack(spacing: 14) {
                AvatarView(initial: String(thread.title.prefix(1)), size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(thread.title).font(.subheadline.weight(.semibold)).foregroundColor(VoygoTheme.textPrimary)
                        Spacer()
                        if thread.unreadCount > 0 {
                            Text("\(thread.unreadCount)").font(.caption2.bold())
                                .frame(minWidth: 18, minHeight: 18)
                                .background(VoygoTheme.primary)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }
                    Text(thread.lastMessage).font(.caption).foregroundColor(VoygoTheme.textSecondary).lineLimit(1)
                }
            }
            .padding(14)
        }
    }
}

// MARK: - Chat Thread (mirrors ChatThreadScreen.kt)

struct ChatThreadView: View {
    let threadId: String
    let title: String
    /// Pop-up callback. Required because Inbox now drives the back via
    /// its own NavigationStack path, not the system back chevron.
    var onBack: () -> Void = {}
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var newMessage = ""
    @State private var scrollProxy: ScrollViewProxy? = nil

    var messages: [ChatMessage] { store.messages(for: threadId) }

    var body: some View {
        ZStack {
            VPalette.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                VPolishedNavBar(title: title, kicker: "Direct chat", onBack: onBack)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(messages) { msg in
                                ChatBubble(message: msg, onRetry: {
                                    Task { await store.retryFailedMessage(msg.id) }
                                })
                                .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onAppear { scrollProxy = proxy; scrollToBottom() }
                    .onChange(of: messages.count) { _, _ in scrollToBottom() }
                }

                // Input bar
                HStack(spacing: 10) {
                    TextField("Message...", text: $newMessage, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(VPalette.surfaceHigh)
                        .cornerRadius(22)
                        .foregroundColor(VPalette.text)
                        .tint(VPalette.primary)

                    Button(action: sendMessage) {
                        let isEmpty = newMessage.trimmingCharacters(in: .whitespaces).isEmpty
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(isEmpty ? VPalette.textHint : VPalette.primary)
                    }
                    .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(VPalette.surface)
            }
        }
        .task(id: threadId) {
            // Initial fetch + flip the read-state so the inbox kicker
            // and per-row badge clear. Then poll every 4s while the
            // view is on screen — chat is poll-only today; without
            // this the rider doesn't see replies until they leave
            // and re-enter the thread.
            await store.refreshMessages(threadId: threadId)
            await store.markThreadRead(threadId: threadId)
            scrollToBottom()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                await store.refreshMessages(threadId: threadId)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-mark-read on foreground so a notification-tap that
            // opens the app directly to this thread also clears the
            // badge that fired the push.
            if phase == .active {
                Task { await store.markThreadRead(threadId: threadId) }
            }
        }
    }

    private func sendMessage() {
        let text = newMessage
        newMessage = ""
        Task {
            await store.sendMessage(threadId: threadId, text: text)
        }
    }
    private func scrollToBottom() {
        if let last = messages.last { scrollProxy?.scrollTo(last.id, anchor: .bottom) }
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    /// Tap handler for the failed-state retry indicator. No-op when
    /// the message is sent / from another user.
    var onRetry: (() -> Void)? = nil

    var isMe: Bool { message.sender == .me }

    var body: some View {
        HStack {
            if isMe { Spacer() }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(isMe ? .white : VPalette.text)
                    // Long messages need to be selectable / copyable —
                    // critical for sharing addresses and phone numbers
                    // that appear in driver chat.
                    .textSelection(.enabled)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(
                        Group {
                            if isMe {
                                VPalette.primaryGradient
                                    .opacity(message.deliveryState == .failed ? 0.55 : 1.0)
                            } else {
                                VPalette.surfaceHigh
                            }
                        }
                    )
                    .cornerRadius(18, corners: isMe ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])

                // Delivery indicator on outgoing rows. Incoming bubbles
                // stay bare — the timestamp alone is enough.
                HStack(spacing: 4) {
                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(VoygoTheme.textHint)
                    if isMe {
                        switch message.deliveryState {
                        case .sending:
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(VPalette.textHint)
                                .accessibilityLabel("Sending")
                        case .failed:
                            Button(action: { onRetry?() }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                    Text("Tap to retry")
                                }
                                .font(.caption2.weight(.bold))
                                .foregroundColor(VPalette.danger)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Send failed. Tap to retry.")
                        case .sent:
                            EmptyView()
                        }
                    }
                }
            }
            if !isMe { Spacer() }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: date)
    }
}

// Corner radius helper for bubbles (rounds only the specified corners).
struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}
