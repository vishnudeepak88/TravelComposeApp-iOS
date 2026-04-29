import SwiftUI
import SafariServices

// MARK: - Hosted-checkout wrapper for Billplz.
//
// Billplz uses a redirect-based payment flow (FPX is server-mediated), so we
// open the URL in an SFSafariViewController. Once the rider completes payment
// the page redirects to `BILLPLZ_REDIRECT_URL` (a `voygo://` deep link in
// production); for now we just dismiss when the user closes the sheet.

struct BillplzCheckoutSheet: View {
    let url: URL
    var onDismiss: () -> Void

    var body: some View {
        SafariView(url: url)
            .ignoresSafeArea()
            .onDisappear { onDismiss() }
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
