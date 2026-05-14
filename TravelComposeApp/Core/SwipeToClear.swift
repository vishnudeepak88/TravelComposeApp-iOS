import SwiftUI

// MARK: - Swipe-to-clear / dismiss
//
// Native `.swipeActions` only works inside a `List`. Voygo's
// Notifications + Home cards live inside `ScrollView` (because each
// screen mixes the rows with non-row chrome — kickers, hero cards,
// service tiles), so we ship our own gesture-based equivalent. The
// API mirrors the native modifier just enough to feel familiar:
//
//   row.swipeToClear { store.dismiss(notification.id) }
//
// Behaviour (iOS-Mail-style partial swipe, but no auto-commit):
//   - Drag left → row offsets along with the finger, exposing a
//     destructive button (defaults to `trash.fill` + Voygo danger).
//   - Release past the reveal threshold → row LATCHES open at the
//     action width (light haptic). Nothing committed yet.
//   - Tap the destructive button → fires the callback (success
//     haptic, row sweeps away).
//   - Drag right past the close threshold → springs closed.
//   - Vertical pans bail out so the parent ScrollView still scrolls.
//
// We intentionally don't auto-commit on release past the threshold —
// riders reported the auto-commit felt accidental, so every
// destructive action now requires the deliberate tap on the button.
//
// Architecture: ZStack with the action button at the trailing edge
// and content on top. Content's offset shifts it left to reveal the
// button. We deliberately don't use `.allowsHitTesting(false)` or a
// tap-to-close overlay — both interfere with the Clear button's tap
// recognizer. The trade-off: tapping content while revealed fires
// the content's tap action. Acceptable in practice because:
//   - The rider's eye is already on the visible Clear button.
//   - Underlying content taps are non-destructive navigation.
//   - The latch is easy to dismiss by swiping the row back right.

extension View {
    /// Adds a leftward swipe gesture that reveals a destructive
    /// action button. The action only fires when the rider taps the
    /// revealed button — releasing the swipe past the threshold
    /// latches the row open instead of auto-committing.
    func swipeToClear(
        label: String,
        systemImage: String = "trash.fill",
        actionWidth: CGFloat = 88,
        background: Color = VPalette.danger,
        onClear: @escaping () -> Void
    ) -> some View {
        self.modifier(
            SwipeToClearModifier(
                label: label,
                systemImage: systemImage,
                actionWidth: actionWidth,
                background: background,
                onClear: onClear
            )
        )
    }
}

private struct SwipeToClearModifier: ViewModifier {
    let label: String
    let systemImage: String
    let actionWidth: CGFloat
    let background: Color
    let onClear: () -> Void

    /// Negative = swiped left.
    @State private var offset: CGFloat = 0
    /// Snapshot of `offset` at the moment a new drag begins so a
    /// drag started from an already-latched row extends / closes
    /// the reveal smoothly instead of snapping to zero.
    @State private var dragStartOffset: CGFloat = 0
    /// Locked once a horizontal pan is detected; bypassed for
    /// vertical pans so the parent ScrollView still scrolls.
    @State private var direction: Direction = .undecided
    /// Latches once the row has been cleared so the spring-back
    /// animation doesn't re-fire the callback.
    @State private var hasCleared: Bool = false

    private enum Direction { case undecided, horizontal, vertical }

    private var latchThreshold: CGFloat { actionWidth * 0.55 }

    /// True when the row is far enough open for the action to be a
    /// meaningful target. Drives the Button's hit-testing so at rest
    /// the underlying content's tap action stays usable (we can't
    /// just put the Button on top with opacity=0 — invisible buttons
    /// still steal taps in SwiftUI unless hit-testing is disabled).
    private var isRevealed: Bool { offset < -2 }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            // Content first (back). Background fills the row so the
            // action button doesn't bleed through transparent areas
            // before the rider has actually swiped.
            content
                .background(VPalette.surface)
                .offset(x: offset)
                .highPriorityGesture(
                    // highPriorityGesture (not `.gesture`) so child
                    // Buttons inside the row don't claim the touch
                    // first. minimumDistance: 12 keeps taps under
                    // that threshold flowing through to child views.
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            if direction == .undecided {
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    direction = .horizontal
                                    dragStartOffset = offset
                                } else {
                                    direction = .vertical
                                }
                            }
                            guard direction == .horizontal else { return }
                            let candidate = dragStartOffset + value.translation.width
                            // Clamp leftward only; allow a small
                            // rubber-band overswipe.
                            offset = max(min(0, candidate), -actionWidth * 1.3)
                        }
                        .onEnded { _ in
                            defer { direction = .undecided }
                            guard direction == .horizontal else { return }
                            if offset < -latchThreshold {
                                latchOpen()
                            } else {
                                closeReveal()
                            }
                        }
                )

            // Action button ON TOP at the trailing edge — Swift's
            // hit-test goes front-to-back, so this is the first
            // thing checked at the trailing 88pt. allowsHitTesting
            // turns it off at rest so the underlying content's
            // tap (open route, etc.) still works through the
            // invisible button area. Opacity ramps in with the
            // swipe so it visually fades into view.
            Button(action: triggerClear) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.bold))
                    Text(label)
                        .font(.caption2.weight(.heavy))
                }
                .foregroundColor(.white)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(background)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(min(1, abs(offset) / actionWidth))
            .allowsHitTesting(isRevealed)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func latchOpen() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            offset = -actionWidth
        }
    }

    private func closeReveal() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            offset = 0
        }
    }

    private func triggerClear() {
        guard !hasCleared else { return }
        hasCleared = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // First leg: row sweeps off-screen to the left. Slightly
        // overshoots so the action button trails off cleanly instead
        // of clipping at the edge.
        withAnimation(.easeIn(duration: 0.2)) {
            offset = -actionWidth * 1.6
        }
        // Second leg: parent removes the row from its collection
        // inside a withAnimation so the ForEach diff-animates the
        // height collapse + neighbour shuffle. Pair with a
        // `.transition(.move(edge: .leading).combined(with: .opacity))`
        // on the row in the parent for the cleanest exit — without
        // an explicit transition, ForEach falls back to a fade,
        // which still reads fine.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeInOut(duration: 0.28)) {
                onClear()
            }
        }
    }
}
