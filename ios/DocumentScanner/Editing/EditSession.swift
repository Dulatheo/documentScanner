import SwiftUI

/// An in-progress comment (DESIGN_SPEC §4.3 "Comment tool"), buffered in
/// `EditSession.comments` until Save/Export writes it to a real
/// `CommentModel` — mirrors how `PageEditState`'s edits stay in memory
/// until then too. Works the same whether this session is a fresh capture
/// or a re-edit of an existing document; `existingCommentID` just tracks
/// which draft already has a persisted counterpart, in case editing an
/// existing comment is ever added later.
struct DraftComment: Identifiable {
    let id = UUID()
    var text: String
    var pageIndex: Int?
    var createdAt: Date = Date()
    var existingCommentID: UUID?
}

/// Everything the Edit flow needs for one run: the pages being edited and,
/// if this is a re-edit, the document they belong to.
@MainActor
final class EditSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var pages: [PageEditState]
    @Published var currentIndex: Int = 0
    @Published var comments: [DraftComment] = []

    /// Nil when this session originates from a fresh capture (new document);
    /// set when re-editing an already-saved document.
    let existingDocument: DocumentModel?
    let documentName: String

    init(pages: [PageEditState], existingDocument: DocumentModel?, documentName: String) {
        self.pages = pages
        self.existingDocument = existingDocument
        self.documentName = documentName
    }

    var current: PageEditState { pages[currentIndex] }
    var pageCount: Int { pages.count }

    // `String(localized:)`, not a plain interpolated literal — `pageLabel`
    // is displayed via `Text(session.pageLabel)`, a `Text(String)` call
    // (verbatim, unlocalized) since `pageLabel`'s type is `String`; the
    // catalog lookup has to happen here, when the value is produced.
    var pageLabel: String { String(localized: "Page \(currentIndex + 1) of \(pageCount)") }

    func goToNext() { goTo(currentIndex + 1) }
    func goToPrevious() { goTo(currentIndex - 1) }

    /// Switches to `index`, first committing any in-progress crop
    /// adjustment on the page being left — the same thing `goToNext`/
    /// `goToPrevious` always did, factored out so the swipeable page
    /// TabView's selection binding (which can land on any index directly,
    /// not just an adjacent one via repeated taps) goes through the same
    /// safe path instead of assigning `currentIndex` directly and skipping
    /// the commit.
    func goTo(_ index: Int) {
        guard index >= 0, index < pages.count, index != currentIndex else { return }
        current.commitCropIfNeeded()
        currentIndex = index
    }

    /// Removes the page at `index` (DESIGN_SPEC §4.3 "delete a scanned
    /// page") — used when reviewing a multi-page capture and one page
    /// didn't come out well. Clamps `currentIndex` to stay valid, favoring
    /// the new last page over resetting to 0 so deleting a page near the
    /// end doesn't jump the user back to the start.
    func deletePage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        pages.remove(at: index)
        guard !pages.isEmpty else { return }
        currentIndex = min(currentIndex, pages.count - 1)
    }
}

extension EditSession {
    /// Reconstructs an editable session from an already-saved document
    /// (DESIGN_SPEC §4.4) — tapping a document on Home reopens the exact
    /// same Edit flow a fresh capture uses, just seeded from disk instead
    /// of the camera, so every tool (Crop/Adjust/Comment/Text/Sign) and
    /// Save/Export work identically either way. `committedQuad` starts at
    /// `.fullImage` since crop quads were never persisted in the first
    /// place — same as how re-opening Crop on a fresh capture's page
    /// starts from a fresh inset rectangle rather than remembering exactly
    /// where the corners last were.
    static func load(from document: DocumentModel) -> EditSession {
        let pages = document.orderedPages.map { pageModel -> PageEditState in
            let image = ImageStore.load(pageModel.imagePath) ?? UIImage()
            let original = ImageStore.load(pageModel.originalImagePath) ?? image
            let state = PageEditState(
                order: pageModel.order,
                image: image,
                originalImage: original,
                committedQuad: .fullImage,
                filter: pageModel.filter,
                brightness: pageModel.brightness,
                contrast: pageModel.contrast,
                existingPageID: pageModel.id
            )
            state.ocrText = pageModel.ocrText
            state.ocrLines = pageModel.ocrLines
            state.highlightedLineIDs = Set(pageModel.highlightRegions.map(\.lineID))
            state.signature = pageModel.signature
            return state
        }
        let session = EditSession(pages: pages, existingDocument: document, documentName: document.name)
        session.comments = document.sortedComments.map { comment in
            DraftComment(
                text: comment.text,
                pageIndex: comment.pageIndex,
                createdAt: comment.createdAt,
                existingCommentID: comment.id
            )
        }
        return session
    }
}
