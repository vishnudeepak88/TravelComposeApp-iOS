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
// Behaviour mirrors iOS Mail's partial swipe:
//   - Drag left → row offsets along with the finger, exposing a
//     destructive button (defaults to `trash.fill` + Voygo danger).
//   - Release past the reveal threshold → row LATCHES at the action
//     width; the destructive button is now revealed. Nothing is
//     committed yet — the rider must tap the button to confirm.
//   - Release inside the threshold → spring back to rest.
//   - Tap the content area while revealed → spring back to rest.
//   - Vertical pans bail out so the parent ScrollView still scrolls.
//
// This intentionally departs from the iOS Mail "full-swipe-to-commit"
// shortcut: riders told us the auto-commit felt accidental ("I just
// peeked at the button and it deleted the row"). The latch-and-tap
// flow keeps every destructive action explicit.

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

    @State private var offset: CGFloat = 0
    /// True once the row has latched open. Drives both visual state
    /// and gesture routing — a tap on the content area while open
    /// snaps back instead of forwarding to the underlying view.
    @State private var isRevealed: Bool = false
    /// Locked once a horizontal pan is detected; bypassed for
    /// vertical pans so the parent ScrollView still scrolls.
    @State private var direction: Direction = .undecided
    /// Latches once the row has been cleared so the spring-back
    /// animation doesn't immediately re-fire the callback.
    @State private var hasCleared: Bool = false

    private enum Direction { case undecided, horizontal, vertical }

    /// Distance the row must travel before the latch engages. Tied
    /// to actionWidth so taller actions need a proportionally bigger
    /// commit gesture.
    private var latchThreshold: CGFloat { actionWidth * 0.55 }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            // Destructive action revealed behind the row. Tapping
            // this is the ONLY way to commit the clear — releasing a
            // swipe past the threshold latches the row open here
            // and waits for the deliberate tap.
            Button(action: triggerClear) {
                HStack {
                    Spacer(minLength: 0)
                    VStack(spacing: 4) {
                        Image(systemName: systemImage)
                            .font(.subheadline.weight(.bold))
                        Text(label)
                            .font(.caption2.weight(.heavy))
                    }
                    .foregroundColor(.white)
                    Spacer(minLength: 0)
                }
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            // Hide the button when the row is at rest so it doesn't
            // poke out beyond rounded corners. Opacity ramp ties
            // visibility to drag progress.
            .opacity(min(1, abs(offset) / actionWidth))

            content
                .background(VPalette.surface)
                .offset(x: offset)
                // Tap-to-close when latched open. Suppress hits to
                // the underlying view's gestures while revealed so a
                // stray tap doesn't navigate the rider away from the
                // destructive choice they're about to commit.
                .allowsHitTesting(!isRevealed)
                .overlay(
                    Group {
                        if isRevealed {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { closeReveal() }
                        }
                    }
                )
                .highPriorityGesture(
                    // highPriorityGesture (not `.gesture`) so child
                    // Buttons inside the row don't claim the touch
                    // first. minimumDistance: 12 lets genuine taps
                    // (under that threshold) fall through to the
                    // child Button when the row is at rest.
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            if direction == .undecided {
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    direction = .horizontal
                                } else {
                                    direction = .vertical
                                }
                            }
                            guard direction == .horizontal else { return }
                            // Base offset depends on whether the row
                            // is already latched open — a swipe while
                            // revealed should be able to extend or
                            // close the reveal smoothly.
                            let base: CGFloat = isRevealed ? -actionWidth : 0
                            let candidate = base + value.translation.width
                            // Clamp to leftward only, capping at
                            // 1.3× the action width so the row
                            // doesn't keep travelling.
                            offset = max(min(0, candidate), -actionWidth * 1.3)
                        }
                        .onEnded { value in
                            defer { direction = .undecided }
                            guard direction == .horizontal else { return }
                            // Latch open / snap closed based on the
                            // final offset, NOT the velocity. We do
                            // NOT auto-fire `triggerClear` here —
                            // the destructive action always requires
                            // an explicit tap on the revealed button.
                            if offset < -latchThreshold {
                                latchOpen()
                            } else {
                                closeReveal()
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func latchOpen() {
        // Light haptic to confirm the row latched open. The
        // destructive haptic fires later when the rider taps Clear.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            offset = -actionWidth
            isRevealed = true
        }
    }

    private func closeReveal() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            offset = 0
            isRevealed = false
        }
    }

    private func triggerClear() {
        guard !hasCleared else { return }
        hasCleared = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.22)) {
            offset = -actionWidth * 1.4
        }
        // Slight delay so the row's exit animation reads as
        // "swept away" before the parent removes it from its
        // collection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onClear()
        }
    }
}
