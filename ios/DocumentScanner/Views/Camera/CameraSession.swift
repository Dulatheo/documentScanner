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
/// sealed capture UI. This is purely a visual aid: the detected quad is
/// never used to crop the captured photo.
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
    private var captureCompletion: ((UIImage?) -> Void)?

    // MARK: - Live document detection

    private let videoAnalysisQueue = DispatchQueue(label: "com.dulatheo.documentscanner.camera-video-analysis")
    /// Throttles Vision analysis to ~5 frames/sec — running the segmentation
    /// request on every delivered frame is wasteful and can stall the
    /// analysis queue, since `VNImageRequestHandler.perform` is synchronous.
    private let minAnalysisInterval: TimeInterval = 1.0 / 5.0
    private var lastAnalysisTime = Date.distantPast
    /// Below this confidence, treat the frame as "nothing detected" rather
    /// than showing a shaky/unreliable quad.
    private let minDetectionConfidence: VNConfidence = 0.5

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

        // Rotate delivered buffers to portrait up-front (matching the photo
        // output above) so Vision can be told the frame is already `.up`,
        // rather than reasoning about the sensor's native landscape
        // orientation on every frame.
        if let connection = videoDataOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        videoDataOutput.setSampleBufferDelegate(self, queue: videoAnalysisQueue)

        isConfigured = true
    }

    // MARK: - Capture

    /// Captures a single still photo. `completion` is always called on the
    /// main queue with `nil` on failure.
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            self.captureCompletion = completion
            self.photoOutput.capturePhoto(with: settings, delegate: self)
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
            DispatchQueue.main.async { completion?(nil) }
            return
        }

        let normalized = image.normalizedToUpOrientation()
        DispatchQueue.main.async {
            completion?(normalized)
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
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            publish(quad: Self.quad(from: request.results?.first, minConfidence: minDetectionConfidence))
        } catch {
            publish(quad: nil)
        }
    }

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
