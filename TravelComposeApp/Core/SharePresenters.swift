import SwiftUI
import UIKit
import MessageUI

// MARK: - Share & message-compose UIKit wrappers
//
// SwiftUI doesn't have first-class wrappers for either of these in
// iOS 26 yet — the share sheet is doable via `ShareLink` but only
// when you have a single Transferable; for "text + URL" the legacy
// UIActivityViewController is still the cleanest path. The SMS
// composer is UIKit-only.

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Wraps `MFMessageComposeViewController` so SwiftUI can present it
/// as a sheet. Caller must check `canSendText` before showing —
/// presenting on a device that can't send SMS yields an empty
/// modal that confuses users.
struct MessageComposerView: UIViewControllerRepresentable {
    let body: String
    var recipients: [String]? = nil

    static var canSendText: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.body = body
        if let recipients { vc.recipients = recipients }
        vc.messageComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
        }
    }
}
