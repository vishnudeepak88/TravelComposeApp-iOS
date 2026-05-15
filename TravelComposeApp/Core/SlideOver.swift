import SwiftUI

// MARK: - Slide-from-right overlay
//
// Reusable modifier that presents a full-screen overlay sliding in
// from the trailing edge — the iOS-native push direction for
// forward navigation. Use this in place of `.sheet(isPresented:)`
// when the destination feels like a "page" (drilling deeper into
// the app) rather than a transient modal task.
//
// Why not just `.sheet` everywhere?
//   - `.sheet` is bottom-to-top (good for modal forms, share
//     sheets, action sheets).
//   - `.fullScreenCover` is also bottom-to-top and can't be
//     customised.
//   - NavigationStack push gives you right-to-left, but requires
//     restructuring around a path-based navigation context.
//
// For a "drill into a sub-page" feel that survives outside
// NavigationStack, this overlay matches the language picker
// pattern: a ZStack overlay with `.transition(.move(edge: .trailing))`
// and a spring animation keyed to the presentation Bool.
//
// Usage:
//
//   .slideOver(isPresented: $showEditName) {
//       EditNameSheet(onDone: { showEditName = false })
//   }
//
// The presented content is responsible for its own background
// (e.g. `VPalette.bg.ignoresSafeArea()`) and its own dismiss
// button — same contract as the existing language picker.

extension View {
    /// Presents `content` as a right-to-left slide overlay anchored
    /// on top of the modified view. The overlay covers the full
    /// frame; the underlying view stays mounted but isn't tappable
    /// while the overlay is presented (the overlay's own
    /// `.background` blocks taps).
    func slideOver<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self.modifier(SlideOverModifier(isPresented: isPresented, sheetContent: content))
    }

    /// `item:` variant that mirrors `.sheet(item:)`. The overlay is
    /// presented while the binding holds a non-nil value; the
    /// content closure receives the unwrapped item.
    func slideOver<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        let isPresented = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { newValue in
                if !newValue { item.wrappedValue = nil }
            }
        )
        return self.modifier(
            SlideOverModifier(isPresented: isPresented) {
                Group {
                    if let unwrapped = item.wrappedValue {
                        content(unwrapped)
                    }
                }
            }
        )
    }
}

private struct SlideOverModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                sheetContent()
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        // Spring (response 0.38, damping 0.86) gives the slide a
        // tactile feel — matches the language picker so the whole
        // app feels cohesive. Wrapped through `voygoAnimation` so
        // Settings → Accessibility → Reduce Motion suppresses the
        // slide (the overlay still appears/disappears, just without
        // the lateral motion).
        .voygoAnimation(.spring(response: 0.38, dampingFraction: 0.86), value: isPresented)
    }
}
