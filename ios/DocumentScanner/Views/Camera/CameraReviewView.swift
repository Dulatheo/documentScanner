import SwiftUI
import UIKit

/// Per-shot review step shown immediately after each shutter tap
/// (DESIGN_SPEC §4.2). This is the actual fix the custom camera exists
/// for: VisionKit's own review screen put **Retake** in the prominent
/// position and buried "keep this page" in a small back-chevron. Here
/// **Retake** is secondary/outlined and bottom-left, **Done** is primary/
/// filled `accent` and bottom-right — reversed from the confusing
/// VisionKit layout, and the labels/positions are ours to control. Deliber-
/// ately minimal: just the captured photo plus these two actions, no crop/
/// adjust/filter tools (those live in the Edit flow's own Crop tool later).
struct CameraReviewView: View {
    let image: UIImage
    /// Owned by `DocumentCameraView`, which also owns the capture-stack
    /// thumbnail this screen zoom-transitions from — see the iOS
    /// zoom-transition implementation note in DESIGN_SPEC §4.2.
    var zoomNamespace: Namespace.ID
    var onRetake: () -> Void
    var onDone: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .ignoresSafeArea()

            VStack {
                Spacer()
                controlBar
            }
        }
        .matchedGeometryEffect(id: "captureReviewZoom", in: zoomNamespace)
        .statusBarHidden()
        .transition(.opacity)
    }

    private var controlBar: some View {
        HStack {
            Button(action: onRetake) {
                Text("Retake")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1)
                    )
            }

            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(theme.accent))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
    }
}
