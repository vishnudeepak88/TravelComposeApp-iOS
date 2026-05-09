import SwiftUI
import UIKit

// MARK: - Swipe-back gesture restoration
//
// Custom-nav screens set `.navigationBarHidden(true)` to hide the
// system bar in favor of `VPolishedNavBar`. Side effect: UIKit
// disables `interactivePopGestureRecognizer` because there's no
// system back button it can rely on. Users still expect the iOS
// swipe-from-left-edge to pop, especially on bigger devices.
//
// `EnableSwipeBack` walks the responder chain to the closest
// `UINavigationController` and force-enables the recognizer.
// Apply once on each NavigationStack root (or the modifier-wrap
// `.enableSwipeBack()` per screen).

struct EnableSwipeBack: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SwipeBackHostController {
        SwipeBackHostController()
    }
    func updateUIViewController(_ uiViewController: SwipeBackHostController, context: Context) {}
}

final class SwipeBackHostController: UIViewController, UIGestureRecognizerDelegate {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        // `parent` is the SwiftUI hosting controller; walk up to find
        // the wrapping UINavigationController that the NavigationStack
        // ultimately presents through.
        if let nav = findNavController(from: parent) {
            nav.interactivePopGestureRecognizer?.delegate = self
            nav.interactivePopGestureRecognizer?.isEnabled = true
        }
    }

    private func findNavController(from vc: UIViewController?) -> UINavigationController? {
        var cursor: UIViewController? = vc
        while let c = cursor {
            if let nav = c as? UINavigationController { return nav }
            cursor = c.parent
        }
        return nil
    }

    // Only allow the gesture to begin when there's actually something
    // to pop. Starting it at the root navigation level would do
    // nothing visible and feel broken.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = findNavController(from: parent) else { return false }
        return nav.viewControllers.count > 1
    }
}

extension View {
    /// Re-enables the iOS edge-swipe-back gesture on a screen whose
    /// system nav bar is hidden. Paired with custom `VPolishedNavBar`
    /// chevrons so users have both affordances.
    func enableSwipeBack() -> some View {
        background(EnableSwipeBack().frame(width: 0, height: 0))
    }
}
