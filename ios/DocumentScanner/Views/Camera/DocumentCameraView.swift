import AVFoundation
import SwiftUI
import UIKit

/// Full-screen custom camera capture screen (DESIGN_SPEC §4.2). Replaces
/// the former `VNDocumentCameraViewController` wrapper: VisionKit's own
/// per-shot review UI is a sealed system screen that put **Retake** in the
/// prominent spot and the "keep this page" action in a small, easy-to-miss
/// back-chevron, with no public API to relabel/reposition/intercept it.
/// Hand-rolling capture with AVFoundation gives full control over that
/// screen (see `CameraReviewView`) at the cost of VisionKit's built-in
/// real-time edge detection — pages get manual perspective correction via
/// the Edit flow's Crop tool instead.
///
/// Public interface is unchanged from the VisionKit version, so
/// `RootView`'s `.fullScreenCover` call site needs no changes: `onFinish`
/// hands back every captured page as soon as the user taps "Done · N
/// pages"; `onCancel` fires when the user backs out via Cancel (discarding
/// anything captured so far, same as VisionKit's cancel behavior).
struct DocumentCameraView: View {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    @StateObject private var cameraSession = CameraSession()
    @Environment(\.theme) private var theme

    @State private var captures: [UIImage] = []
    @State private var isCapturing = false
    @State private var showPhotoImport = false
    /// On-demand review of `captures.last`, opened by tapping the capture
    /// stack — not a forced stop after every shutter tap.
    @State private var isReviewingLastCapture = false
    /// The `AVCaptureVideoPreviewLayer` backing `CameraPreviewView`, kept so
    /// the live document-quad overlay can convert Vision's normalized frame
    /// coordinates into on-screen points via
    /// `layerRectConverted(fromMetadataOutputRect:)`, which correctly
    /// accounts for the preview's `.resizeAspectFill` crop.
    @State private var previewLayer: AVCaptureVideoPreviewLayer?

    /// A just-captured thumbnail animating from the viewfinder to the
    /// capture-stack indicator (DESIGN_SPEC §4.2: "immediately animates...
    /// flying into the capture-stack indicator").
    @State private var flyingCapture: FlyingCapture?
    @State private var shutterFlashOpacity: Double = 0

    private struct FlyingCapture: Identifiable {
        let id = UUID()
        let image: UIImage
        var progress: CGFloat = 0
    }

    /// Fixed dark camera chrome (`#0B0B0C`) per the mock — independent of
    /// the app's light/dark theme, matching how camera UIs conventionally
    /// stay dark regardless of system appearance.
    private let chromeBackground = Color(red: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x0C / 255.0)

    var body: some View {
        ZStack {
            chromeBackground.ignoresSafeArea()

            switch cameraSession.authorizationState {
            case .authorized:
                liveCameraContent
            case .notDetermined:
                Color.clear
            case .denied:
                permissionDeniedContent
            }

            if isReviewingLastCapture, let lastCapture = captures.last {
                CameraReviewView(
                    image: lastCapture,
                    onRetake: {
                        if !captures.isEmpty {
                            captures.removeLast()
                        }
                        withAnimation(.easeOut(duration: 0.2)) {
                            isReviewingLastCapture = false
                        }
                    },
                    onDone: {
                        // The page was already added to `captures` at
                        // capture time, so Done makes no data change — it
                        // just closes the on-demand review.
                        withAnimation(.easeOut(duration: 0.2)) {
                            isReviewingLastCapture = false
                        }
                    }
                )
                .zIndex(2)
            }
        }
        .onAppear {
            cameraSession.checkAuthorization()
            switch cameraSession.authorizationState {
            case .authorized:
                cameraSession.start()
            case .notDetermined:
                cameraSession.requestAccess()
            case .denied:
                break
            }
        }
        .onDisappear {
            cameraSession.stop()
        }
        .sheet(isPresented: $showPhotoImport) {
            PhotoImportPicker(
                onFinish: { images in
                    showPhotoImport = false
                    captures.append(contentsOf: images)
                },
                onCancel: { showPhotoImport = false }
            )
            .ignoresSafeArea()
        }
        .statusBarHidden()
    }

    // MARK: - Live camera

    private var liveCameraContent: some View {
        ZStack {
            CameraPreviewView(session: cameraSession.session, onLayerReady: { layer in
                previewLayer = layer
            })
            .ignoresSafeArea()

            viewfinderGuide

            VStack {
                instructionPill
                    .padding(.top, 16)
                Spacer()
            }

            if !captures.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        captureStackIndicator
                        Spacer()
                    }
                    .padding(.leading, 24)
                    .padding(.bottom, 198)
                }
            }

            VStack(spacing: 14) {
                Spacer()
                if !captures.isEmpty {
                    doneButton
                }
                bottomControlBar
            }

            Color.white
                .opacity(shutterFlashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let flyingCapture {
                flyingCaptureOverlay(flyingCapture)
                    .allowsHitTesting(false)
                    .zIndex(1)
            }
        }
    }

    /// The captured-photo thumbnail flying from roughly the viewfinder's
    /// position to the capture-stack indicator's position, landing there as
    /// the animation completes (DESIGN_SPEC §4.2 / mock `flyToStack`).
    private func flyingCaptureOverlay(_ flying: FlyingCapture) -> some View {
        GeometryReader { proxy in
            let start = CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
            let end = CGPoint(x: 24 + 28, y: proxy.size.height - 198 - 37)
            let progress = flying.progress
            let current = CGPoint(
                x: start.x + (end.x - start.x) * progress,
                y: start.y + (end.y - start.y) * progress
            )
            let startWidth: CGFloat = 220
            let endWidth: CGFloat = 56
            let width = startWidth + (endWidth - startWidth) * progress
            let height = width * 1.333

            Image(uiImage: flying.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.85), lineWidth: 2))
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 6)
                .opacity(Double(1 - 0.15 * progress))
                .position(current)
        }
    }

    private var instructionPill: some View {
        Text("Position the document in the frame")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.72))
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    private var viewfinderGuide: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 72, 330)
            let height = width * 1.333

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: width, height: height)
                ViewfinderCorners()
                    .frame(width: width, height: height)
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)

            // Live-tracked quad (DESIGN_SPEC §4.2): overlaid on top of the
            // static corner brackets above, appearing/tracking/disappearing
            // as `CameraSession` detects a document in frame. Only a visual
            // guide — never used to crop the captured photo.
            if previewLayer != nil, let quad = cameraSession.detectedQuad {
                LiveDocumentQuadShape(
                    topLeft: screenPoint(for: quad.topLeft),
                    topRight: screenPoint(for: quad.topRight),
                    bottomRight: screenPoint(for: quad.bottomRight),
                    bottomLeft: screenPoint(for: quad.bottomLeft)
                )
                .stroke(theme.accent, lineWidth: 2.5)
                .shadow(color: theme.accent.opacity(0.6), radius: 4)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.15), value: cameraSession.detectedQuad)
            }
        }
        .allowsHitTesting(false)
    }

    /// Converts a normalized, top-left-origin point (`CameraSession`'s
    /// `DetectedQuad` space) into an on-screen point in the preview's own
    /// coordinate space, accounting for `.resizeAspectFill`'s crop via the
    /// preview layer itself — the correct way to do this conversion, since
    /// aspect-fill is not a simple linear scale. Falls back to a naive
    /// linear mapping for the brief window before the preview layer exists.
    private func screenPoint(for normalizedPoint: CGPoint) -> CGPoint {
        guard let previewLayer else { return .zero }
        let metadataRect = CGRect(origin: normalizedPoint, size: .zero)
        return previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect).origin
    }

    private var captureStackIndicator: some View {
        Button(action: { isReviewingLastCapture = true }) {
            ZStack(alignment: .topTrailing) {
                if let last = captures.last {
                    Image(uiImage: last)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.85), lineWidth: 2))
                        .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)
                }
                Text("\(captures.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Circle().fill(theme.accent))
                    .offset(x: 10, y: -10)
            }
        }
        .buttonStyle(.plain)
    }

    private var doneButton: some View {
        Button(action: finishSession) {
            Text("Done · \(captures.count) page\(captures.count == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 11)
                .background(Capsule().fill(theme.accent))
        }
    }

    private var bottomControlBar: some View {
        HStack(alignment: .top) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(width: 76, alignment: .leading)

            Spacer()

            Button(action: capturePhoto) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 72, height: 72)
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 4))
                    .opacity(isCapturing ? 0.5 : 1)
            }
            .disabled(isCapturing)

            Spacer()

            Button(action: { showPhotoImport = true }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 30)
        .padding(.top, 26)
        .frame(height: 174, alignment: .top)
        .background(Color(red: 12 / 255.0, green: 12 / 255.0, blue: 13 / 255.0).opacity(0.92))
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Permission denied

    private var permissionDeniedContent: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 38))
                .foregroundColor(.white.opacity(0.55))
            Text("Camera access is off")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            Text("Document Scanner needs camera access to scan pages. Enable it in Settings to continue.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            Button(action: openSettings) {
                Text("Open Settings")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(theme.accent))
            }
            .padding(.top, 8)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.top, 2)

            Spacer()
        }
    }

    // MARK: - Actions

    private func capturePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        cameraSession.capturePhoto { image in
            isCapturing = false
            guard let image else { return }
            handleCaptureSuccess(image)
        }
    }

    /// Appends the captured page immediately (DESIGN_SPEC §4.2: "no
    /// interruption") and plays the shutter-flash + fly-to-stack feedback.
    /// No full-screen review here — that's now purely on-demand via tapping
    /// `captureStackIndicator`.
    private func handleCaptureSuccess(_ image: UIImage) {
        captures.append(image)

        // Shutter flash: rise then fall across two separate dispatch turns
        // (~350ms total, matching the mock's `shutterFlash` timing) so the
        // brief "on" state is guaranteed to actually render before the fade
        // begins, rather than relying on SwiftUI to coalesce two
        // same-frame mutations into a visible intermediate state.
        withAnimation(.easeOut(duration: 0.08)) {
            shutterFlashOpacity = 0.85
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.27)) {
                shutterFlashOpacity = 0
            }
        }

        // Insert the flying thumbnail at progress 0 (unanimated — it should
        // simply appear where the viewfinder is) on this render pass, then
        // animate its progress to 1 on the *next* run-loop turn. Doing the
        // insert and the animated mutation in the same synchronous scope
        // would give SwiftUI no "from" frame to interpolate away from, so
        // the two are deliberately split across dispatch turns.
        let flying = FlyingCapture(image: image)
        flyingCapture = flying
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            guard flyingCapture?.id == flying.id else { return }
            withAnimation(.easeOut(duration: 0.62)) {
                flyingCapture?.progress = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01 + 0.62) {
            if flyingCapture?.id == flying.id {
                flyingCapture = nil
            }
        }
    }

    private func finishSession() {
        guard !captures.isEmpty else { return }
        onFinish(captures)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Draws the 4 independent corner brackets of the viewfinder guide
/// (DESIGN_SPEC §4.2 / mock `isCamera` block) — a purely static visual
/// frame, no live edge detection.
private struct ViewfinderCorners: View {
    var body: some View {
        GeometryReader { proxy in
            let bracketSize: CGFloat = 26
            let lineWidth: CGFloat = 2
            let inset: CGFloat = 12
            let halfBracket = bracketSize / 2

            ZStack {
                // Top-left: border-left + border-top.
                CornerBracket()
                    .stroke(Color.white, lineWidth: lineWidth)
                    .frame(width: bracketSize, height: bracketSize)
                    .position(x: inset + halfBracket, y: inset + halfBracket)

                // Top-right: border-right + border-top.
                CornerBracket()
                    .stroke(Color.white, lineWidth: lineWidth)
                    .frame(width: bracketSize, height: bracketSize)
                    .rotationEffect(.degrees(90))
                    .position(x: proxy.size.width - inset - halfBracket, y: inset + halfBracket)

                // Bottom-right: border-right + border-bottom.
                CornerBracket()
                    .stroke(Color.white, lineWidth: lineWidth)
                    .frame(width: bracketSize, height: bracketSize)
                    .rotationEffect(.degrees(180))
                    .position(
                        x: proxy.size.width - inset - halfBracket,
                        y: proxy.size.height - inset - halfBracket
                    )

                // Bottom-left: border-left + border-bottom.
                CornerBracket()
                    .stroke(Color.white, lineWidth: lineWidth)
                    .frame(width: bracketSize, height: bracketSize)
                    .rotationEffect(.degrees(270))
                    .position(x: inset + halfBracket, y: proxy.size.height - inset - halfBracket)
            }
        }
    }
}

/// One L-shaped bracket occupying the left + top edges of its frame; the 4
/// corners of `ViewfinderCorners` are this same shape rotated 0/90/180/270°.
private struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}

/// Traces the live-detected document quad from 4 already-screen-space
/// points (DESIGN_SPEC §4.2). The points are computed by `DocumentCameraView`
/// via `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)`
/// before being handed to this shape, so this type itself has no
/// coordinate-space math to do — it just connects 4 points into a closed
/// path, ignoring `rect` (unlike most `Shape`s, these points are already
/// absolute, not proportional to the shape's own frame).
private struct LiveDocumentQuadShape: Shape {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addLine(to: bottomRight)
        path.addLine(to: bottomLeft)
        path.closeSubpath()
        return path
    }
}
