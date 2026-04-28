import SwiftUI

// MARK: - Inbox (mirrors InboxScreen.kt)

struct InboxView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedThreadId: String? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VoygoTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    VoygoNavBar(
                        title: "Inbox",
                        trailingContent: AnyView(
                            Group {
                                if store.threads.contains(where: { $0.unreadCount > 0 }) {
                                    Text("\(store.threads.map(\.unreadCount).reduce(0, +))")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(VoygoTheme.danger)
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                }
                            }
                        )
                    )

                    if store.threads.isEmpty {
                        EmptyStateView(icon: "bubble.left.and.bubble.right",
                                       title: "No messages", subtitle: "Your commute chats will appear here").frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(store.threads) { thread in
                                    NavigationLink(destination: ChatThreadView(threadId: thread.id, title: thread.title)) {
                                        ThreadRow(thread: thread)
                                            .padding(.horizontal, 16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.bottom, 96)
                        }
                        .refreshable {
                            await store.refreshAll()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            await store.refreshAll()
        }
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
    @EnvironmentObject var store: AppStore
    @State private var newMessage = ""
    @State private var scrollProxy: ScrollViewProxy? = nil

    var messages: [ChatMessage] { store.messages(for: threadId) }

    var body: some View {
        ZStack {
            VoygoTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(messages) { msg in
                                ChatBubble(message: msg)
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
                    TextField("Message...", text: $newMessage)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(VoygoTheme.surfaceHigh)
                        .cornerRadius(22)
                        .foregroundColor(VoygoTheme.textPrimary)
                        .tint(VoygoTheme.primary)

                    Button(action: sendMessage) {
                        let isEmpty = newMessage.trimmingCharacters(in: .whitespaces).isEmpty
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(isEmpty ? VoygoTheme.textHint : VoygoTheme.primary)
                    }
                    .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(VoygoTheme.surface)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(VoygoTheme.background, for: .navigationBar)
        .task(id: threadId) {
            await store.refreshMessages(threadId: threadId)
            scrollToBottom()
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
    var isMe: Bool { message.sender == .me }

    var body: some View {
        HStack {
            if isMe { Spacer() }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(isMe ? .white : VoygoTheme.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Group { if isMe { VoygoTheme.primaryGradient } else { LinearGradient(colors: [VoygoTheme.surfaceHigh], startPoint: .leading, endPoint: .trailing) } })
                    .cornerRadius(18, corners: isMe ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])
                Text(formatTime(message.timestamp)).font(.caption2).foregroundColor(VoygoTheme.textHint)
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
