import SwiftUI
import UIKit
import VisionKit

/// One captured page, handed from `DocumentCameraView` to `RootView` via
/// `onFinish`.
struct CameraCapture: Identifiable {
    let id = UUID()
    /// VisionKit hands back each page already cropped/perspective-corrected
    /// to the document it detected — there's no separate "raw, uncropped"
    /// capture available, so `original` and `cropped` both start from that
    /// same image. `PageEditState`'s Crop tool can still re-crop further
    /// from `original` if the user wants to adjust it.
    let original: UIImage
    /// The enhanced version of `original` (DESIGN_SPEC §4.2 "scan
    /// filters"), produced by `DocumentEnhancer` with the default `.auto`
    /// filter — what's actually shown in the capture stack thumbnail and
    /// what `PageEditState` starts from.
    let cropped: UIImage
    /// Always `.fullImage`: VisionKit has already cropped `original` to the
    /// document's edges, so there's no further quad to seed the Crop tool
    /// with.
    let quad: Quad = .fullImage
}

/// Wraps `VNDocumentCameraViewController` — the platform's built-in
/// document-scanning capture UI (edge detection, multi-page, per-shot
/// review) per DESIGN_SPEC §4.2. An earlier version of this screen replaced
/// VisionKit with a hand-rolled AVFoundation camera (live detection,
/// auto-capture, a custom review screen) to get full control over the
/// per-shot review UI's button layout; after repeated rounds of on-device
/// bugs in that custom implementation couldn't be reliably resolved, the app
/// reverted to VisionKit — Apple's own maintained, known-working
/// implementation — rather than continuing to chase them. Its own
/// Cancel/shutter/multi-page/review chrome replaces this app's camera
/// screen entirely; there's no view of our own to attach a zoom-transition
/// to internally, so `RootView` applies `.matchedGeometryEffect` at its
/// call site instead.
struct DocumentCameraView: UIViewControllerRepresentable {
    var onFinish: ([CameraCapture]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([CameraCapture]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([CameraCapture]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            DispatchQueue.global(qos: .userInitiated).async { [onFinish] in
                let captures = pages.map { page in
                    CameraCapture(original: page, cropped: DocumentEnhancer.apply(.auto, to: page))
                }
                DispatchQueue.main.async {
                    onFinish(captures)
                }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onCancel()
        }
    }
}
