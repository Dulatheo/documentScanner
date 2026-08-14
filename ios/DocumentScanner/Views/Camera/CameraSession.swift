import AVFoundation
import UIKit

/// Owns the `AVCaptureSession` powering the custom camera screen
/// (DESIGN_SPEC §4.2). Replaces `VNDocumentCameraViewController` so the
/// per-shot review step can be a hand-built screen (`CameraReviewView`)
/// instead of VisionKit's sealed, non-relabelable UI. Handles camera
/// permission state, session lifecycle, and single-photo capture; all
/// `AVCaptureSession` mutation happens on a dedicated background queue per
/// Apple's guidance, with `@Published` state updated back on the main
/// queue for SwiftUI.
final class CameraSession: NSObject, ObservableObject {
    enum AuthorizationState {
        case notDetermined
        case authorized
        case denied
    }

    @Published private(set) var authorizationState: AuthorizationState = .notDetermined

    /// The live capture session. `CameraPreviewView` attaches this directly
    /// to its `AVCaptureVideoPreviewLayer`.
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.dulatheo.documentscanner.camera-session")
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var captureCompletion: ((UIImage?) -> Void)?

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

        session.commitConfiguration()

        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

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
