import SwiftUI

/// Everything the Edit flow needs for one run: the pages being edited and,
/// if this is a re-edit, the document they belong to.
@MainActor
final class EditSession: ObservableObject, Identifiable {
    let id = UUID()
    @Published var pages: [PageEditState]
    @Published var currentIndex: Int = 0

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

    var pageLabel: String { "Page \(currentIndex + 1) of \(pageCount)" }

    func goToNext() {
        guard currentIndex < pages.count - 1 else { return }
        current.commitCropIfNeeded()
        currentIndex += 1
    }

    func goToPrevious() {
        guard currentIndex > 0 else { return }
        current.commitCropIfNeeded()
        currentIndex -= 1
    }
}
