import AVFoundation
import SwiftUI
import UIKit

/// One captured page, handed from `DocumentCameraView` to `RootView` via
/// `onFinish`.
struct CameraCapture: Identifiable {
    let id = UUID()
    /// The raw, uncropped capture — kept so the Edit flow's Crop tool can
    /// re-crop from scratch (`PageEditState.originalImage`).
    let original: UIImage
    /// The image shown everywhere in this app — the capture stack
    /// thumbnail, the on-demand review screen, and what `PageEditState`
    /// starts from — perspective-corrected to the quad the live detector
    /// saw at the moment of capture, so what the user sees afterward
    /// matches what was inside the live frame. Falls back to `original`
    /// when no confident quad was detected for this particular shot.
    /// `var`, not `let`: `handleCaptureSuccess` shows this immediately
    /// (perspective-corrected only, so shutter feedback stays instant),
    /// then swaps in `DocumentEnhancer`'s result once that finishes
    /// asynchronously a moment later.
    var cropped: UIImage
    /// The quad `cropped` was corrected from (normalized to `original`'s
    /// size), or `.fullImage` when nothing was detected. Seeded into
    /// `PageEditState.committedQuad` so re-opening the Crop tool starts
    /// from this same quad instead of resetting to the full image.
    let quad: Quad
}

/// Full-screen custom camera capture screen (DESIGN_SPEC §4.2). Replaces
/// the former `VNDocumentCameraViewController` wrapper: VisionKit's own
/// per-shot review UI is a sealed system screen that put **Retake** in the
/// prominent spot and the "keep this page" action in a small, easy-to-miss
/// back-chevron, with no public API to relabel/reposition/intercept it.
/// Hand-rolling capture with AVFoundation gives full control over that
/// screen (see `CameraReviewView`), and — now that live document detection
/// is proven working on-device — auto-crops each capture to the live-quad
/// the user actually saw, with the Edit flow's Crop tool still available to
/// refine it (or re-crop from `CameraCapture.original` entirely) afterward.
///
/// `onFinish` hands back every captured page — each with the raw photo
/// *and* the version cropped to whatever quad the live detector saw at
/// capture time — as soon as the user taps "Done · N pages"; `onCancel`
/// fires when the user backs out via Cancel (discarding anything captured
/// so far, same as VisionKit's cancel behavior).
struct DocumentCameraView: View {
    var onFinish: ([CameraCapture]) -> Void
    var onCancel: () -> Void
    /// Injected by `RootView` so this screen's own root can
    /// `matchedGeometryEffect`-animate open/closed from Home's scan
    /// button — see the iOS zoom-transition implementation note in
    /// DESIGN_SPEC §4.2. Not to be confused with `reviewZoomNamespace`
    /// below, which is this view's *own* namespace for its internal
    /// capture-stack-thumbnail → review transition.
    var zoomNamespace: Namespace.ID

    @StateObject private var cameraSession = CameraSession()
    @Environment(\.theme) private var theme

    /// Owns both the capture-stack thumbnail (the source) and the per-shot
    /// review overlay (the destination) below, so — unlike the other two
    /// zoom transitions — this one needs no state lifted to a parent view.
    @Namespace private var reviewZoomNamespace

    @State private var captures: [CameraCapture] = []
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

    // MARK: - Auto-capture

    /// Consecutive live-detection frames the quad has stayed within
    /// `autoCaptureStabilityTolerance` of its predecessor. Reset to 0
    /// whenever nothing's detected or the quad jumps too far between
    /// frames. Reaching `autoCaptureStableFrameThreshold` (while not in
    /// cooldown) triggers an automatic shutter — matching VisionKit's own
    /// "captures once the page holds steady" behavior.
    @State private var stableFrameCount = 0
    @State private var lastStableQuad: CameraSession.DetectedQuad?
    /// Auto-capture is suppressed until this time, so a page that stays
    /// steadily framed after an auto-capture isn't immediately captured
    /// again before the user moves on to the next page.
    @State private var autoCaptureCooldownUntil = Date.distantPast

    /// ~8 consecutive on-target frames at the session's ~8fps analysis
    /// rate is roughly 1 second of steady framing before auto-capturing.
    private let autoCaptureStableFrameThreshold = 8
    /// How far (normalized 0...1 units, per corner) the quad may drift
    /// between frames and still count as "steady" rather than "moving."
    private let autoCaptureStabilityTolerance: CGFloat = 0.015
    private let autoCaptureCooldownInterval: TimeInterval = 2.0

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
                    image: lastCapture.cropped,
                    zoomNamespace: reviewZoomNamespace,
                    onRetake: {
                        if !captures.isEmpty {
                            captures.removeLast()
                        }
                        withAnimation(.zoomTransition) {
                            isReviewingLastCapture = false
                        }
                    },
                    onDone: {
                        // The page was already added to `captures` at
                        // capture time, so Done makes no data change — it
                        // just closes the on-demand review.
                        withAnimation(.zoomTransition) {
                            isReviewingLastCapture = false
                        }
                    }
                )
                .zIndex(2)
            }
        }
        .matchedGeometryEffect(id: "cameraZoom", in: zoomNamespace)
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
        .onChange(of: cameraSession.detectedQuad) { _, newQuad in
            evaluateAutoCapture(newQuad)
        }
        .sheet(isPresented: $showPhotoImport) {
            PhotoImportPicker(
                onFinish: { images in
                    showPhotoImport = false
                    // No live detection applies to gallery imports — kept
                    // as full, uncropped pages (`quad: .fullImage`), same
                    // as manual Crop always could produce anyway.
                    let imported = images.map { CameraCapture(original: $0, cropped: $0, quad: .fullImage) }
                    captures.append(contentsOf: imported)
                    // Same "show it now, enhance in place shortly after"
                    // pattern as the shutter path — see DocumentEnhancer.
                    for capture in imported {
                        DocumentEnhancer.enhanceAsync(capture.original) { enhanced in
                            guard let idx = captures.firstIndex(where: { $0.id == capture.id }) else { return }
                            captures[idx].cropped = enhanced
                        }
                    }
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
                cameraSession.updateRegionOfInterest(regionOfInterest(for: layer))
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
        GeometryReader { _ in
            // Live-tracked quad (DESIGN_SPEC §4.2) is now the *only* framing
            // guide — the earlier static corner-bracket frame was dropped
            // once live detection was confirmed working on-device, so
            // there's no redundant static chrome competing with it.
            // `LiveDocumentQuadShape.animatableData` lets SwiftUI interpolate
            // smoothly between successive detected positions instead of
            // jumping frame-to-frame; `.transition(.opacity)` covers the
            // appear/disappear case when detection starts/stops entirely.
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
                .animation(.linear(duration: 0.1), value: cameraSession.detectedQuad)
            }
        }
        .ignoresSafeArea()
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

    /// The portion of the sensor's frame actually visible through
    /// `.resizeAspectFill`'s crop, converted into `CameraSession`'s
    /// `regionOfInterest` (Vision's normalized, bottom-left-origin
    /// convention) so live detection only ever considers what the user can
    /// actually see — `metadataOutputRectConverted(fromLayerRect:)` is the
    /// exact inverse of `layerRectConverted(fromMetadataOutputRect:)` used
    /// in `screenPoint(for:)` above, so both directions of this conversion
    /// stay consistent with each other (and with `CameraSession`'s own
    /// bottom-left-origin flip for the same reason).
    private func regionOfInterest(for layer: AVCaptureVideoPreviewLayer) -> CGRect {
        guard layer.bounds.width > 0, layer.bounds.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let visible = layer.metadataOutputRectConverted(fromLayerRect: layer.bounds)
        return CGRect(x: visible.minX, y: 1 - visible.maxY, width: visible.width, height: visible.height)
    }

    private var captureStackIndicator: some View {
        Button(action: {
            withAnimation(.zoomTransition) {
                isReviewingLastCapture = true
            }
        }) {
            ZStack(alignment: .topTrailing) {
                if let last = captures.last {
                    Image(uiImage: last.cropped)
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
        // Zoom-transition source (DESIGN_SPEC §4.2): the per-shot review
        // overlay above is tagged with this same id in `reviewZoomNamespace`,
        // so it animates open from this thumbnail's own frame instead of a
        // plain fade-in.
        .matchedGeometryEffect(id: "captureReviewZoom", in: reviewZoomNamespace)
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
        cameraSession.capturePhoto { image, quad in
            isCapturing = false
            guard let image else { return }
            handleCaptureSuccess(image, quad: quad)
        }
    }

    /// Appends the captured page immediately (DESIGN_SPEC §4.2: "no
    /// interruption") and plays the shutter-flash + fly-to-stack feedback.
    /// No full-screen review here — that's now purely on-demand via tapping
    /// `captureStackIndicator`.
    ///
    /// `quad` is whatever `CameraSession` detected in *this specific photo*
    /// (a fresh one-shot detection against the final image itself, not a
    /// reprojection of the live-preview quad — see
    /// `CameraSession.detectDocumentQuad`) — cropping to it here is what
    /// makes the saved/reviewed page match what the user actually saw
    /// inside the live frame, rather than the full uncropped photo.
    private func handleCaptureSuccess(_ image: UIImage, quad: Quad?) {
        let cropped = quad.flatMap { PerspectiveCorrectionService.correct(image: image, quad: $0) } ?? image
        let capture = CameraCapture(original: image, cropped: cropped, quad: quad ?? .fullImage)
        captures.append(capture)

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
        let flying = FlyingCapture(image: cropped)
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

        // The stack/review/Edit flow should show an enhanced "scanned
        // document" look, not a raw cropped photo — but the CoreImage
        // pipeline is too slow to run in the critical path above without
        // making the shutter feel laggy, so it runs off-thread and swaps
        // into place (stack thumbnail, on-demand review) once ready.
        DocumentEnhancer.enhanceAsync(cropped) { enhanced in
            guard let idx = captures.firstIndex(where: { $0.id == capture.id }) else { return }
            captures[idx].cropped = enhanced
        }
    }

    private func finishSession() {
        guard !captures.isEmpty else { return }
        onFinish(captures)
    }

    /// Feeds one new live-detection result into the stability tracker and
    /// fires the shutter automatically once a document has held steady for
    /// `autoCaptureStableFrameThreshold` consecutive frames (DESIGN_SPEC
    /// §4.2), the same "just hold it still" behavior VisionKit's own
    /// scanner has. The manual shutter button keeps working the whole time
    /// — this only ever *adds* a capture, never blocks one.
    private func evaluateAutoCapture(_ quad: CameraSession.DetectedQuad?) {
        guard let quad else {
            stableFrameCount = 0
            lastStableQuad = nil
            return
        }
        if let last = lastStableQuad, quad.isClose(to: last, tolerance: autoCaptureStabilityTolerance) {
            stableFrameCount += 1
        } else {
            stableFrameCount = 1
        }
        lastStableQuad = quad

        guard stableFrameCount >= autoCaptureStableFrameThreshold else { return }
        stableFrameCount = 0

        guard !isCapturing, Date() >= autoCaptureCooldownUntil else { return }
        autoCaptureCooldownUntil = Date().addingTimeInterval(autoCaptureCooldownInterval)
        capturePhoto()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Traces the live-detected document quad from 4 already-screen-space
/// points (DESIGN_SPEC §4.2) — the only viewfinder guide now (the earlier
/// static corner-bracket frame was removed once live detection was
/// confirmed working on-device, so there's no redundant static chrome
/// alongside it). The points are computed by `DocumentCameraView` via
/// `AVCaptureVideoPreviewLayer.layerRectConverted(fromMetadataOutputRect:)`
/// before being handed to this shape, so this type itself has no
/// coordinate-space math to do — it just connects 4 points into a closed
/// path, ignoring `rect` (unlike most `Shape`s, these points are already
/// absolute, not proportional to the shape's own frame).
///
/// Conforms `animatableData` (4 points × 2 `CGFloat`s each, nested in
/// `AnimatablePair`s per SwiftUI's standard pattern for multi-value
/// `Shape`s) so SwiftUI can smoothly interpolate the quad's position
/// between successive detections instead of the corners jumping instantly
/// every ~125ms (the ~8fps analysis interval) — that per-frame jump was
/// the actual cause of "not smooth," since a plain `.animation(value:)`
/// modifier alone only animates a `Shape`'s *appearance/disappearance*,
/// not changes to a custom shape's own geometry, unless it implements
/// `animatableData` itself.
private struct LiveDocumentQuadShape: Shape {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    var animatableData: AnimatablePair<
        AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>,
        AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>
    > {
        get {
            AnimatablePair(
                AnimatablePair(topLeft.animatableData, topRight.animatableData),
                AnimatablePair(bottomRight.animatableData, bottomLeft.animatableData)
            )
        }
        set {
            topLeft.animatableData = newValue.first.first
            topRight.animatableData = newValue.first.second
            bottomRight.animatableData = newValue.second.first
            bottomLeft.animatableData = newValue.second.second
        }
    }

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
