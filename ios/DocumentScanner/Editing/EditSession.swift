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
}
