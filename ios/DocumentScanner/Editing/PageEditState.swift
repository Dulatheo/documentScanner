import SwiftUI
import UIKit

/// In-memory editing state for one page, used while the Edit flow is open.
/// Nothing here touches SwiftData until `EditFlowView` commits on Save.
@MainActor
final class PageEditState: ObservableObject, Identifiable {
    let id = UUID()
    var order: Int

    /// Current perspective-corrected image shown on the paper card.
    @Published var image: UIImage
    /// Pre-crop capture (the raw camera/gallery photo), retained so
    /// Crop can be re-applied from scratch.
    @Published var originalImage: UIImage

    /// Live-editing quad while the Crop tool is active, normalized to
    /// `originalImage`. Nil means "not currently mid-crop".
    @Published var pendingQuad: Quad?
    /// Last-committed crop quad (normalized to `originalImage`), used to
    /// seed the overlay next time Crop is opened.
    @Published var committedQuad: Quad = .fullImage

    @Published var ocrText: String?
    @Published var ocrLines: [OCRLine] = []
    @Published var isRecognizingText = false
    @Published var highlightedLineIDs: Set<UUID> = []

    @Published var signature: Signature?

    /// The currently selected scan filter (DESIGN_SPEC §4.2/§4.3), applied
    /// to the committed crop. Independent of crop: changing it re-processes
    /// the already-cropped image rather than re-running perspective
    /// correction, and re-cropping preserves whichever filter is selected.
    @Published var filter: DocumentFilter

    /// Existing page id, when this state is editing an already-saved page
    /// (nil for a page captured in this session that hasn't been saved yet).
    var existingPageID: UUID?

    init(
        order: Int,
        image: UIImage,
        originalImage: UIImage? = nil,
        committedQuad: Quad = .fullImage,
        filter: DocumentFilter = .auto,
        existingPageID: UUID? = nil
    ) {
        self.order = order
        self.image = image
        self.originalImage = originalImage ?? image
        self.committedQuad = committedQuad
        self.filter = filter
        self.existingPageID = existingPageID
    }

    var highlightRegions: [HighlightRegion] {
        ocrLines
            .filter { highlightedLineIDs.contains($0.id) }
            .map { HighlightRegion(id: UUID(), lineID: $0.id, normalizedBox: $0.normalizedBox) }
    }

    func toggleHighlight(for line: OCRLine) {
        if highlightedLineIDs.contains(line.id) {
            highlightedLineIDs.remove(line.id)
        } else {
            highlightedLineIDs.insert(line.id)
        }
    }

    /// Applies perspective correction using `pendingQuad` (if the user moved
    /// it) and clears crop-mode state. Safe to call even if nothing changed.
    /// Re-cropping preserves whichever filter is currently selected — it's
    /// not reset to `.auto`.
    func commitCropIfNeeded() {
        guard let quad = pendingQuad, quad != committedQuad else {
            pendingQuad = nil
            return
        }
        committedQuad = quad
        pendingQuad = nil

        guard let corrected = PerspectiveCorrectionService.correct(image: originalImage, quad: quad) else { return }
        image = corrected
        applyFilterAsync(to: corrected, quad: quad, filter: filter)
    }

    /// Selects a new filter and re-derives `image` from `originalImage` +
    /// `committedQuad` with it applied. Crop is unaffected — this only
    /// re-processes the already-cropped image, it never re-runs perspective
    /// correction.
    func applyFilter(_ newFilter: DocumentFilter) {
        filter = newFilter
        let base = committedQuad == .fullImage
            ? originalImage
            : (PerspectiveCorrectionService.correct(image: originalImage, quad: committedQuad) ?? originalImage)
        applyFilterAsync(to: base, quad: committedQuad, filter: newFilter)
    }

    /// Shared "show the fast geometric result now, swap in the filtered
    /// one shortly after" pattern used by both `commitCropIfNeeded()` and
    /// `applyFilter(_:)`. Guarded against `committedQuad`/`filter` having
    /// already moved on by the time this finishes, so a stale result can't
    /// clobber a newer crop or filter selection.
    private func applyFilterAsync(to base: UIImage, quad: Quad, filter: DocumentFilter) {
        DocumentEnhancer.applyAsync(filter, to: base) { [weak self] filtered in
            guard let self, self.committedQuad == quad, self.filter == filter else { return }
            self.image = filtered
        }
    }
}
