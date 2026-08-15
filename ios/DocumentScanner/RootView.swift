import SwiftData
import SwiftUI
import UIKit

/// Actions Home/DocumentViewer trigger; RootView owns the presentation
/// state so the whole `home → camera → edit → (export → share) → home`
/// state machine (DESIGN_SPEC §4) lives in one place.
struct AppActions {
    var startCamera: () -> Void = {}
    var startPhotoImport: () -> Void = {}
    var openExport: (DocumentModel, Bool) -> Void = { _, _ in }
}

private struct AppActionsKey: EnvironmentKey {
    static let defaultValue = AppActions()
}

extension EnvironmentValues {
    var appActions: AppActions {
        get { self[AppActionsKey.self] }
        set { self[AppActionsKey.self] = newValue }
    }
}

struct ExportTarget: Identifiable {
    let id = UUID()
    let document: DocumentModel
    let pendingSave: Bool
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DocumentModel.createdAt, order: .reverse) private var documents: [DocumentModel]

    @StateObject private var toastCenter = ToastCenter()

    @State private var showCamera = false
    @State private var showPhotoImport = false
    @State private var editSession: EditSession?
    @State private var exportTarget: ExportTarget?
    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            HomeView(documents: documents)
                .navigationDestination(for: DocumentModel.self) { document in
                    DocumentViewerView(document: document)
                }
        }
        .environment(\.appActions, AppActions(
            startCamera: { showCamera = true },
            startPhotoImport: { showPhotoImport = true },
            openExport: { document, pendingSave in
                exportTarget = ExportTarget(document: document, pendingSave: pendingSave)
            }
        ))
        .toastOverlay(toastCenter)
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView(
                onFinish: { captures in
                    showCamera = false
                    beginEditSession(with: captures)
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoImport) {
            PhotoImportPicker(
                onFinish: { images in
                    showPhotoImport = false
                    if !images.isEmpty {
                        toastCenter.show("Added from gallery")
                        beginEditSession(with: images)
                    }
                },
                onCancel: { showPhotoImport = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $editSession) { session in
            EditFlowView(
                session: session,
                toastCenter: toastCenter,
                onCancel: { editSession = nil },
                onSaved: { document in
                    editSession = nil
                    toastCenter.show("Saved to Documents")
                    exportTarget = ExportTarget(document: document, pendingSave: true)
                }
            )
        }
        .sheet(item: $exportTarget) { target in
            ExportSheetView(document: target.document, pendingSave: target.pendingSave) {
                exportTarget = nil
            }
        }
    }

    /// Used by the top-level gallery-import path (`AppActions.startPhotoImport`),
    /// which has no live-detected quad to seed — pages start full/uncropped,
    /// same as always.
    private func beginEditSession(with images: [UIImage]) {
        guard !images.isEmpty else { return }
        let pages = images.enumerated().map { index, image in
            PageEditState(order: index, image: image, originalImage: image)
        }
        let name = "Scan \(documents.count + 1)"
        editSession = EditSession(pages: pages, existingDocument: nil, documentName: name)
    }

    /// Used by `DocumentCameraView`'s `onFinish` — each page already carries
    /// the quad the live detector saw at capture time, so `PageEditState`
    /// starts pre-cropped to it (with `committedQuad` seeded to match, so
    /// re-opening the Crop tool doesn't reset to the full image).
    private func beginEditSession(with captures: [CameraCapture]) {
        guard !captures.isEmpty else { return }
        let pages = captures.enumerated().map { index, capture in
            PageEditState(
                order: index,
                image: capture.cropped,
                originalImage: capture.original,
                committedQuad: capture.quad
            )
        }
        let name = "Scan \(documents.count + 1)"
        editSession = EditSession(pages: pages, existingDocument: nil, documentName: name)
    }
}
