import SwiftUI
import PhotosUI
import UIKit

// MARK: - Photo picker (PHPickerViewController wrapper)
//
// Used by KYC document upload. Returns a single image as raw `Data`
// to the caller, who is responsible for uploading it (or — for now —
// for using the data length as a proxy that something was selected
// while the backend's S3 presigned-upload endpoint isn't wired).
//
// We deliberately don't ship Camera capture in this iteration — KYC
// photos benefit from the user reviewing/zooming/cropping in the
// system picker before submitting. Once the backend is ready for
// upload progress + retry, we can layer Camera on top.

struct PhotoPicker: UIViewControllerRepresentable {
    /// Called once with the bytes of the picked image, or with nil if
    /// the user cancelled the picker. Marked `@Sendable` so the
    /// background-queue completion in PHPicker can hand the bytes
    /// back to MainActor without tripping Swift 6 strict-concurrency.
    var onPicked: @Sendable (Data?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: @Sendable (Data?) -> Void
        init(onPicked: @escaping @Sendable (Data?) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                onPicked(nil)
                return
            }
            // `loadObject` invokes its completion on a background
            // queue. Capture the @Sendable callback locally so we
            // satisfy Swift 6 strict-concurrency, then bounce the
            // result onto MainActor for the SwiftUI side.
            let cb = onPicked
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let data = (object as? UIImage).flatMap { $0.jpegData(compressionQuality: 0.85) }
                Task { @MainActor in cb(data) }
            }
        }
    }
}
