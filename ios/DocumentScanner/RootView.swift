import SwiftData
import SwiftUI
import UIKit

/// Actions Home triggers; RootView owns the presentation state so the
/// whole `home → camera → edit → (export → share) → home` state machine
/// (DESIGN_SPEC §4) lives in one place. Viewing/editing an already-saved
/// document reuses that same Edit flow (`EditSession.load(from:)`) rather
/// than a separate read-only screen, so there's no dedicated "open
/// export" action here — Export lives in Edit's own top bar for that case.
struct AppActions {
    var startCamera: () -> Void = {}
    var startPhotoImport: () -> Void = {}
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

/// `matchedGeometryEffect` id for a document card (DESIGN_SPEC §4.1).
/// Tapping a card now opens `EditFlowView` via `.fullScreenCover`, a
/// separate presentation `matchedGeometryEffect` can't reach into (same
/// limitation noted on `DocumentCameraView`'s zoom transition below), so
/// this id currently has no matching destination to animate into — kept
/// as a harmless no-op rather than restructured, in case a future zoom
/// transition into the Edit flow is worth adding back.
func documentZoomID(for document: DocumentModel) -> String {
    "documentZoom-\(document.id)"
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DocumentModel.createdAt, order: .reverse) private var documents: [DocumentModel]

    @StateObject private var toastCenter = ToastCenter()
    @StateObject private var premiumManager = PremiumManager()

    @State private var showCamera = false
    @State private var showPhotoImport = false
    @State private var editSession: EditSession?
    @State private var exportTarget: ExportTarget?

    /// Shared with `HomeView` for the scan button's zoom transition into
    /// Camera (DESIGN_SPEC §4.2) — Camera is presented as a plain
    /// conditional overlay in the `ZStack` below, not `.fullScreenCover`,
    /// so `matchedGeometryEffect` can reach across.
    @Namespace private var zoomNamespace

    var body: some View {
        ZStack {
            HomeView(
                documents: documents,
                zoomNamespace: zoomNamespace,
                onSelectDocument: { document in
                    editSession = EditSession.load(from: document)
                },
                onDeleteDocument: deleteDocument,
                onRenameDocument: renameDocument,
                premiumManager: premiumManager,
                toastCenter: toastCenter
            )

            if showCamera {
                DocumentCameraView(
                    onFinish: { captures in
                        withAnimation(.zoomTransition) { showCamera = false }
                        beginEditSession(with: captures)
                    },
                    onCancel: {
                        withAnimation(.zoomTransition) { showCamera = false }
                    }
                )
                .matchedGeometryEffect(id: "cameraZoom", in: zoomNamespace)
                .ignoresSafeArea()
                .zIndex(2)
            }
        }
        .environment(\.appActions, AppActions(
            startCamera: {
                withAnimation(.zoomTransition) { showCamera = true }
            },
            startPhotoImport: {
                showPhotoImport = true
            }
        ))
        .toastOverlay(toastCenter)
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
                premiumManager: premiumManager,
                documentCount: documents.count,
                onCancel: { editSession = nil },
                onSaved: { document in
                    // `session` here is still the one this EditFlowView was
                    // built from — captured before `editSession` is nilled
                    // below — so its `existingDocument` reflects whether
                    // this was a fresh capture or a re-edit (DESIGN_SPEC
                    // §4.4), which decides the toast/export-sheet copy.
                    let wasExistingDocument = session.existingDocument != nil
                    editSession = nil
                    toastCenter.show(wasExistingDocument ? "Changes saved" : "Saved to Documents")
                    exportTarget = ExportTarget(document: document, pendingSave: !wasExistingDocument)
                }
            )
        }
        .sheet(item: $exportTarget) { target in
            ExportSheetView(document: target.document, pendingSave: target.pendingSave, premiumManager: premiumManager) {
                exportTarget = nil
            }
            // Single, fixed-height detent (not `.medium`/`.large`, and not
            // left as the default free-form sheet) — this sheet's content
            // is a short, fixed set of rows, so it should present at
            // exactly that height and never be draggable to a different
            // size. 560 comfortably fits the title/subtitle, all five
            // export rows (PDF/JPG/DOCX/XLSX/PPTX), and the dismiss button,
            // including the home-indicator safe area sheets add
            // automatically — the rows themselves also scroll as a safety
            // net on shorter screens.
            .presentationDetents([.height(560)])
            .presentationDragIndicator(.visible)
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

    /// Deletes a saved document from the library (DESIGN_SPEC §4.1 "delete
    /// a saved document"). `PageModel`/`CommentModel` are cascade-deleted
    /// by `DocumentModel`'s relationship rules, but SwiftData has no idea
    /// the pages' `imagePath`/`originalImagePath` point at files on disk —
    /// those have to be cleaned up explicitly, and before the document
    /// itself goes away, since nothing else can reach them afterward.
    private func deleteDocument(_ document: DocumentModel) {
        for page in document.pages {
            ImageStore.delete(page.imagePath)
            ImageStore.delete(page.originalImagePath)
        }
        modelContext.delete(document)
        try? modelContext.save()
    }

    /// Renames a saved document in place (DESIGN_SPEC §4.1 "rename a saved
    /// document").
    private func renameDocument(_ document: DocumentModel, to newName: String) {
        document.name = newName
        try? modelContext.save()
    }
}
