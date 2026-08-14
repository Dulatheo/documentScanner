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
    @State private var reviewImage: UIImage?
    @State private var isCapturing = false
    @State private var showPhotoImport = false

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

            if let reviewImage {
                CameraReviewView(
                    image: reviewImage,
                    onRetake: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.reviewImage = nil
                        }
                    },
                    onDone: {
                        captures.append(reviewImage)
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.reviewImage = nil
                        }
                    }
                )
                .zIndex(1)
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
            CameraPreviewView(session: cameraSession.session)
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
        }
        .allowsHitTesting(false)
    }

    private var captureStackIndicator: some View {
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
            withAnimation(.easeOut(duration: 0.2)) {
                reviewImage = image
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
