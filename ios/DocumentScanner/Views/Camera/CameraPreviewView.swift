import AVFoundation
import SwiftUI
import UIKit

/// Hosts a full-screen `AVCaptureVideoPreviewLayer` for the live camera
/// feed. SwiftUI has no native preview-layer view, so this is a thin
/// `UIViewRepresentable` wrapper around a `UIView` whose backing layer is
/// the preview layer itself.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    /// Hands the caller the underlying `AVCaptureVideoPreviewLayer` once
    /// it's created, so the live document-detection overlay can convert
    /// Vision's normalized frame coordinates into on-screen points via
    /// `layerRectConverted(fromMetadataOutputRect:)` — the correct way to
    /// account for `.resizeAspectFill`'s crop, rather than hand-rolling
    /// aspect-fill math.
    var onLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        // Deferred to the next run-loop turn: `makeUIView` runs synchronously
        // as part of the parent's (`DocumentCameraView`) own body evaluation,
        // so calling `onLayerReady` here directly mutates that parent's
        // `@State private var previewLayer` *during* the same view-update
        // cycle that produced it — SwiftUI's well-known "modifying state
        // during view update" hazard. In practice this silently drops the
        // assignment: `makeUIView` only ever runs once, so if the mutation
        // doesn't stick that first time, `previewLayer` stays `nil` forever
        // and nothing ever gates on it again, which is exactly why the live
        // document-detection overlay never appeared even though detection
        // itself (confirmed via on-device logging) was working correctly.
        // Dispatching to the main queue moves the mutation to its own,
        // later update cycle, where it's safe.
        DispatchQueue.main.async {
            onLayerReady?(view.previewLayer)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {}

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Force-cast is safe: `layerClass` guarantees `layer` is always
            // an `AVCaptureVideoPreviewLayer` for this view subclass.
            layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast
        }
    }
}
