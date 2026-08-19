import AVFoundation
import SwiftUI
import UIKit

/// Hosts a full-screen `AVCaptureVideoPreviewLayer` for the live camera
/// feed. SwiftUI has no native preview-layer view, so this is a thin
/// `UIViewRepresentable` wrapper around a `UIView` whose backing layer is
/// the preview layer itself.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    /// Hands the caller the underlying `AVCaptureVideoPreviewLayer` — once
    /// it exists, and again on every subsequent layout pass, not just the
    /// first — so the live document-detection overlay can convert Vision's
    /// normalized frame coordinates into on-screen points via
    /// `layerRectConverted(fromMetadataOutputRect:)` (and the inverse, to
    /// compute Vision's `regionOfInterest`), both of which need
    /// `previewLayer.bounds` to already reflect the view's real, laid-out
    /// size. Firing only from `makeUIView` (as this used to) fires *before*
    /// layout has actually sized the view, so a bounds-dependent
    /// computation done only there would silently use a stale/zero size;
    /// `layoutSubviews()` is the point UIKit guarantees the bounds are
    /// correct, and re-fires this callback whenever they change.
    var onLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        view.onLayout = onLayerReady
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.onLayout = onLayerReady
    }

    final class PreviewContainerView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var onLayout: ((AVCaptureVideoPreviewLayer) -> Void)?

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Force-cast is safe: `layerClass` guarantees `layer` is always
            // an `AVCaptureVideoPreviewLayer` for this view subclass.
            layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Deferred to the next run-loop turn, same reasoning as the fix
            // this replaced: `layoutSubviews` can run synchronously inside
            // a SwiftUI update pass, and mutating a SwiftUI `@State` from
            // inside that same pass is the "modifying state during view
            // update" hazard that previously made this callback silently
            // no-op. Capturing `previewLayer`/`onLayout` now and hopping to
            // the next main-queue turn avoids that regardless of when
            // `layoutSubviews` happens to fire.
            let layer = previewLayer
            let callback = onLayout
            DispatchQueue.main.async {
                callback?(layer)
            }
        }
    }
}
