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
// Behaviour:
//   - Drag left → row offsets along with the finger, exposing a
//     destructive button (defaults to `trash.fill` + Voygo danger).
//   - Release past `actionWidth` → triggers `onClear` (with a
//     success haptic).
//   - Release inside the threshold → spring back to rest.
//   - Vertical pans bail out so the parent ScrollView still scrolls.
//
// `actionWidth` and the button label / system image are tweakable
// per call-site (Home's "Dismiss" reads differently from
// Notifications' "Clear"), but the swipe physics are shared.

extension View {
    /// Adds a leftward swipe gesture that reveals a destructive
    /// action button. Fires `onClear` when the gesture is released
    /// past the threshold.
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
    /// Locked once a horizontal pan is detected; bypassed for
    /// vertical pans so the parent ScrollView still scrolls.
    @State private var direction: Direction = .undecided
    /// Latches once the row has been cleared so the spring-back
    /// animation doesn't immediately re-fire the callback.
    @State private var hasCleared: Bool = false

    private enum Direction { case undecided, horizontal, vertical }

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            // Destructive action revealed behind the row. Tappable
            // independently of the drag — handy if the user reveals
            // the action and then prefers to tap it instead of
            // continuing the swipe.
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
            // poke out beyond rounded corners. The opacity ramp ties
            // visibility to drag progress.
            .opacity(min(1, abs(offset) / actionWidth))

            content
                .background(VPalette.surface)
                .offset(x: offset)
                // `highPriorityGesture` (not `.gesture` or
                // `.simultaneousGesture`) so child Buttons inside the
                // row don't claim the touch first. The previous
                // `.gesture` form lost every short drag to the inner
                // tap recognizer — the row scrolled less than the
                // action width and the rider got navigated to the
                // tap destination instead of seeing the destructive
                // action. We still respect minimumDistance: 12 so
                // genuine taps (under that threshold) fall through
                // to the child Button.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            // Lock direction on the first sample so
                            // we don't hijack vertical scrolls.
                            if direction == .undecided {
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    direction = .horizontal
                                } else {
                                    direction = .vertical
                                }
                            }
                            guard direction == .horizontal else { return }
                            // Clamp: only leftward swipes are
                            // meaningful, and we cap at 1.3× the
                            // action width so the row doesn't keep
                            // travelling indefinitely.
                            let raw = min(0, value.translation.width)
                            offset = max(raw, -actionWidth * 1.3)
                        }
                        .onEnded { value in
                            defer { direction = .undecided }
                            guard direction == .horizontal else { return }
                            if value.translation.width < -actionWidth * 0.55 {
                                triggerClear()
                            } else {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                    offset = 0
                                }
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
