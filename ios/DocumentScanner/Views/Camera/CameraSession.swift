import AVFoundation
import UIKit
import Vision

/// Owns the `AVCaptureSession` powering the custom camera screen
/// (DESIGN_SPEC §4.2). Replaces `VNDocumentCameraViewController` so the
/// per-shot review step can be a hand-built screen (`CameraReviewView`)
/// instead of VisionKit's sealed, non-relabelable UI. Handles camera
/// permission state, session lifecycle, and single-photo capture; all
/// `AVCaptureSession` mutation happens on a dedicated background queue per
/// Apple's guidance, with `@Published` state updated back on the main
/// queue for SwiftUI.
///
/// Also runs live document-boundary detection against the video feed
/// (`VNDetectDocumentSegmentationRequest`, the same Vision building block
/// VisionKit's own scanner is built on) so the viewfinder can show a
/// live-tracked quad the way VisionKit did — without pulling in VisionKit's
/// sealed capture UI. That live feed's detections are a visual aid only
/// (`detectedQuad`, used purely for the on-screen guide); the quad actually
/// used to crop a captured photo comes from a separate one-shot detection
/// (`detectDocumentQuad(in:minConfidence:)`) run directly against the final
/// still image at capture time — see that method's doc comment for why.
final class CameraSession: NSObject, ObservableObject {
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
    }

    /// A document quad detected in the live feed, in normalized
    /// **top-left-origin** coordinates (0...1 in each axis) — SwiftUI's
    /// convention. Vision itself reports normalized coordinates with the
    /// origin at the bottom-left; that flip is applied once here so the
    /// view layer never has to think about Vision's coordinate space.
    struct DetectedQuad: Equatable {
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomRight: CGPoint
        var bottomLeft: CGPoint

        /// Whether every corner of `self` sits within `tolerance`
        /// (normalized units) of the matching corner in `other`. Used by
        /// `DocumentCameraView`'s auto-capture logic to tell "the document
        /// has stopped moving" apart from ordinary frame-to-frame jitter —
        /// exact `Equatable` equality would essentially never hold between
        /// two live frames.
        func isClose(to other: DetectedQuad, tolerance: CGFloat) -> Bool {
            func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
                abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
            }
            return near(topLeft, other.topLeft)
                && near(topRight, other.topRight)
                && near(bottomRight, other.bottomRight)
                && near(bottomLeft, other.bottomLeft)
        }
    }

    @Published private(set) var authorizationState: AuthorizationState = .notDetermined

    /// The most recently detected document quad in the live feed, or `nil`
    /// when nothing is currently detected. Updated on the main queue.
    @Published private(set) var detectedQuad: DetectedQuad?

    /// The live capture session. `CameraPreviewView` attaches this directly
    /// to its `AVCaptureVideoPreviewLayer`.
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.dulatheo.documentscanner.camera-session")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false
    private var captureCompletion: ((UIImage?, Quad?) -> Void)?

    // MARK: - Live document detection

    private let videoAnalysisQueue = DispatchQueue(label: "com.dulatheo.documentscanner.camera-video-analysis")
    /// Throttles Vision analysis to ~8 frames/sec — running the segmentation
    /// request on every delivered frame is wasteful and can stall the
    /// analysis queue, since `VNImageRequestHandler.perform` is synchronous.
    /// (Raised from an initial 5fps once live detection was confirmed
    /// working on-device: more frequent samples feed smoother interpolation
    /// in the view layer's `LiveDocumentQuadShape.animatableData`.)
    private let minAnalysisInterval: TimeInterval = 1.0 / 8.0
    private var lastAnalysisTime = Date.distantPast
    /// Below this confidence, treat the frame as "nothing detected" rather
    /// than showing a shaky/unreliable quad.
    ///
    /// Deliberately lower than a naive first guess (0.5): unlike VisionKit's
    /// own scanner, which effectively runs segmentation against a
    /// deliberately-composed still, this request runs against live,
    /// hand-held, frequently motion-blurred preview frames — a strictly
    /// harder input than a careful single shot. This threshold only governs
    /// the live *guide* (`detectedQuad`); the separate one-shot detection
    /// used to actually crop a captured photo (`detectDocumentQuad`) uses
    /// its own, independently-passed confidence check, so loosening this
    /// one only risks a shakier on-screen guide, never a bad crop. Tune
    /// using the `#if DEBUG` logging below, which prints every
    /// observation's actual confidence on a real device.
    private let minDetectionConfidence: VNConfidence = 0.3

    // MARK: - Permission

    /// Syncs `authorizationState` with the current system permission
    /// without prompting. Call on appear.
    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationState = .authorized
        case .notDetermined:
            authorizationState = .notDetermined
        case .denied, .restricted:
            authorizationState = .denied
        @unknown default:
            authorizationState = .denied
        }
    }

    /// Prompts the system permission dialog. Only meaningful when
    /// `authorizationState == .notDetermined`.
    func requestAccess() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorizationState = granted ? .authorized : .denied
                if granted {
                    self.start()
                }
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)

        if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // Discard late frames rather than queuing them — this is a live
        // analysis feed, not a recording, so the freshest frame is always
        // preferable to catching up on a backlog.
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        session.commitConfiguration()

        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        // Deliberately *not* setting `videoOrientation` on this connection
        // (unlike the photo connection above) — this buffer feeds Vision,
        // and the resulting `VNRectangleObservation` corners are converted
        // to screen points via `AVCaptureVideoPreviewLayer
        // .layerRectConverted(fromMetadataOutputRect:)`. Apple's docs for
        // that API (and for the closely related `AVCaptureMetadataOutput
        // .rectOfInterest`) are explicit that the input rect's (0,0)-(1,1)
        // normalized space is defined "on an unrotated image" / "relative
        // to the coordinate space of the device providing the metadata" —
        // i.e. the sensor's native orientation, *regardless* of whatever
        // videoOrientation some connection happens to be rotating its own
        // delivered buffer to. If this connection rotated the buffer to
        // portrait, Vision's observation coordinates would land in that
        // rotated (portrait) space — a 90°, aspect-ratio-swapped mismatch
        // against what `layerRectConverted` expects — which would scramble
        // the live quad's on-screen position (very plausibly *the* cause
        // of "no visible live detection", not just a placement error,
        // since scrambled coordinates can easily fall off-screen or
        // collapse to a degenerate rect). Leaving this connection at its
        // native orientation, and telling `VNImageRequestHandler` the
        // buffer is `.up` (i.e. "analyze exactly as delivered, don't
        // reinterpret it"), keeps Vision's reported coordinates in that
        // same native space, matching `layerRectConverted`'s contract
        // exactly. It also sidesteps the real performance cost Apple's
        // Technical Q&A QA1744 documents for physically rotating
        // `AVCaptureVideoDataOutput` buffers ("only request rotation if
        // it's necessary") — we no longer need to.
        //
        // Trade-off: the document segmentation model itself now analyzes
        // a sensor-native (landscape-laid-out) buffer rather than a
        // virtually-upright one, which *could* reduce detection
        // confidence versus telling Vision the true `.right` orientation.
        // Rectangle/quad detection is a largely geometric task and should
        // be reasonably rotation-tolerant, but this is exactly what the
        // `#if DEBUG` logging below is for: if on-device confidence values
        // look suspiciously low, that's the next thing to revisit — by
        // passing the correct orientation to Vision *and* rotating its
        // results back into native space before this point, rather than
        // by touching this connection again.
        videoDataOutput.setSampleBufferDelegate(self, queue: videoAnalysisQueue)

        isConfigured = true
    }

    // MARK: - Capture

    /// Captures a single still photo, along with the document quad detected
    /// in *that* photo (or `nil` if nothing confident was found) so the
    /// caller can crop it to exactly what the live viewfinder showed.
    /// `completion` is always called on the main queue.
    func capturePhoto(completion: @escaping (UIImage?, Quad?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil, nil) }
                return
            }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            self.captureCompletion = completion
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    /// Runs a one-shot `VNDetectDocumentSegmentationRequest` against an
    /// already-`.up`-oriented still image — as opposed to the throttled
    /// live-feed path above, which runs against the video-data-output's
    /// *native sensor* orientation and has to convert results into the
    /// preview layer's coordinate space via `layerRectConverted`. Running
    /// this directly against the final captured photo's own pixel space
    /// needs none of that cross-buffer mapping: the returned `Quad` is
    /// already normalized to `image`'s own size and orientation, exactly
    /// the convention `PerspectiveCorrectionService` and the manual Crop
    /// tool's `PageEditState.committedQuad` both expect.
    private static func detectDocumentQuad(in image: UIImage, minConfidence: VNConfidence) -> Quad? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, observation.confidence >= minConfidence else {
                return nil
            }
            func flipped(_ point: CGPoint) -> CodablePoint {
                CodablePoint(x: Double(point.x), y: Double(1 - point.y))
            }
            return Quad(
                topLeft: flipped(observation.topLeft),
                topRight: flipped(observation.topRight),
                bottomRight: flipped(observation.bottomRight),
                bottomLeft: flipped(observation.bottomLeft)
            )
        } catch {
            return nil
        }
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let completion = captureCompletion
        captureCompletion = nil

        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            DispatchQueue.main.async { completion?(nil, nil) }
            return
        }

        let normalized = image.normalizedToUpOrientation()
        // `AVCapturePhotoCaptureDelegate` callbacks land on an internal
        // AVFoundation queue, not necessarily main — safe to do this
        // synchronous, single-image Vision request here directly rather
        // than hopping queues first.
        let quad = Self.detectDocumentQuad(in: normalized, minConfidence: minDetectionConfidence)
        DispatchQueue.main.async {
            completion?(normalized, quad)
        }
    }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisTime) >= minAnalysisInterval else { return }
        lastAnalysisTime = now

        // `perform` is synchronous; running it here (on `videoAnalysisQueue`,
        // never the main queue or the session queue) keeps it off the UI
        // thread while the queue's own seriality naturally paces analysis —
        // no frame is picked up mid-analysis.
        //
        // `orientation: .up` here means "analyze this buffer exactly as
        // delivered, don't reinterpret/rotate it" — which is correct
        // *because* `configureSession()` deliberately leaves this
        // connection at the sensor's native orientation (see the comment
        // there). That keeps `request.results`' normalized coordinates in
        // the same native coordinate space `screenPoint(for:)` needs for
        // `layerRectConverted(fromMetadataOutputRect:)` to place the quad
        // correctly. This is *not* the sensor's true visual up direction —
        // don't change this to `.up` for some other reason without also
        // reconciling `configureSession()` and `screenPoint(for:)`.
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            let observation = request.results?.first
            #if DEBUG
            Self.logAnalysis(observation: observation, minConfidence: minDetectionConfidence)
            #endif
            publish(quad: Self.quad(from: observation, minConfidence: minDetectionConfidence))
        } catch {
            #if DEBUG
            print("[CameraSession] VNImageRequestHandler.perform failed: \(error)")
            #endif
            publish(quad: nil)
        }
    }

    #if DEBUG
    /// Debug-only diagnostic so a future on-device test can tell apart
    /// "frames never arrive" (no log lines at all), "frames arrive but
    /// nothing is ever detected" (consistent "no observation"), and
    /// "detects fine but below threshold" (an observation with confidence
    /// under `minConfidence`) from "detects fine, still doesn't render"
    /// (log shows confident detections; the bug is then in the view layer,
    /// not this pipeline). Throttled to the same ~5fps as analysis itself,
    /// so this cannot spam a release build (it's compiled out entirely) or
    /// meaningfully affect a debug build's frame rate.
    private static func logAnalysis(observation: VNRectangleObservation?, minConfidence: VNConfidence) {
        guard let observation else {
            print("[CameraSession] frame analyzed — no document observation")
            return
        }
        let passed = observation.confidence >= minConfidence ? "PUBLISHED" : "below threshold"
        print("[CameraSession] frame analyzed — confidence \(observation.confidence) (\(passed), min \(minConfidence))")
    }
    #endif

    private func publish(quad: DetectedQuad?) {
        DispatchQueue.main.async { [weak self] in
            self?.detectedQuad = quad
        }
    }

    /// Converts a `VNRectangleObservation`'s corners (normalized,
    /// bottom-left origin) into `DetectedQuad` (normalized, top-left
    /// origin), or `nil` when there's no confident observation.
    private static func quad(
        from observation: VNRectangleObservation?,
        minConfidence: VNConfidence
    ) -> DetectedQuad? {
        guard let observation, observation.confidence >= minConfidence else { return nil }
        func flipped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: 1 - point.y)
        }
        return DetectedQuad(
            topLeft: flipped(observation.topLeft),
            topRight: flipped(observation.topRight),
            bottomRight: flipped(observation.bottomRight),
            bottomLeft: flipped(observation.bottomLeft)
        )
    }
}

private extension UIImage {
    /// Redraws the image with `imageOrientation == .up` so downstream code
    /// (perspective correction, OCR, PDF/JPG export) never has to reason
    /// about EXIF orientation metadata from the capture pipeline.
    func normalizedToUpOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
