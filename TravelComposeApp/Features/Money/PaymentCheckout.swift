import SwiftUI
import SafariServices

// MARK: - Hosted-checkout wrapper for Billplz.
//
// Billplz uses a redirect-based payment flow (FPX is server-mediated), so we
// open the URL in an SFSafariViewController. Once the rider completes payment
// the page redirects to `BILLPLZ_REDIRECT_URL` (a `voygo://payments/return?
// paid=…` deep link). The deep link bumps `AppStore.checkoutDismissalSignal`,
// and this view watches that signal to distinguish "rider returned via
// successful redirect" from "rider hit Done in Safari without paying".

struct BillplzCheckoutSheet: View {
    let url: URL
    /// Called when the rider completed payment and was redirected back via
    /// the `voygo://` deep link. Caller should advance the flow (e.g. push
    /// BookingConfirmed).
    var onPaid: () -> Void = {}
    /// Called when the rider closed the sheet without completing payment.
    /// Caller should NOT advance the flow — surface a "Retry payment" CTA
    /// or land them back on the previous screen.
    var onAbandoned: () -> Void = {}

    @Environment(AppStore.self) private var store
    @State private var initialDismissalSignal: Int = 0
    @State private var resolved = false

    var body: some View {
        SafariView(url: url)
            .ignoresSafeArea()
            .onAppear {
                // Snapshot the dismissal signal at present time. If it
                // increments while we're on this view, the deep link fired
                // and we know the user paid.
                //
                // The snapshot is deferred by one runloop tick so a
                // hot-cache redirect (the Billplz page returns the deep
                // link before the SafariViewController has fully appeared)
                // doesn't see the bumped signal as the "initial" value.
                resolved = false
                let pre = store.checkoutDismissalSignal
                DispatchQueue.main.async {
                    // If the signal already bumped between this enqueue and
                    // execution, take the old (pre-bump) value as initial
                    // so the .onChange below sees the bump.
                    initialDismissalSignal = pre
                }
            }
            .onChange(of: store.checkoutDismissalSignal) { _, newValue in
                if newValue > initialDismissalSignal && !resolved {
                    resolved = true
                    onPaid()
                }
            }
            .onDisappear {
                // SFSafariViewController dismissed. If the deep link
                // already resolved this checkout as paid, do nothing —
                // onPaid already fired. Otherwise treat as abandoned.
                if !resolved {
                    resolved = true
                    onAbandoned()
                }
            }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredBarTintColor = UIColor(VoygoTheme.surface)
        vc.preferredControlTintColor = UIColor(VoygoTheme.primary)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
