import AVFoundation
import SwiftUI
import UIKit

/// Hosts a full-screen `AVCaptureVideoPreviewLayer` for the live camera
/// feed. SwiftUI has no native preview-layer view, so this is a thin
/// `UIViewRepresentable` wrapper around a `UIView` whose backing layer is
/// the preview layer itself.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
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
