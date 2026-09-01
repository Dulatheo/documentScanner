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

    /// Manual Brightness/Contrast (DESIGN_SPEC §4.3 "Adjust tool"), applied
    /// on top of `filter`'s result. `brightness` is CoreImage's own scale
    /// (0 = no change); `contrast` is a multiplier (1 = no change).
    /// Independent of crop/filter, same as `filter` is independent of crop:
    /// re-cropping or switching filters re-derives from `originalImage` and
    /// re-applies whichever brightness/contrast is currently set, rather
    /// than resetting it.
    @Published var brightness: Double = 0
    @Published var contrast: Double = 1

    /// Existing page id, when this state is editing an already-saved page
    /// (nil for a page captured in this session that hasn't been saved yet).
    var existingPageID: UUID?

    init(
        order: Int,
        image: UIImage,
        originalImage: UIImage? = nil,
        committedQuad: Quad = .fullImage,
        filter: DocumentFilter = .auto,
        brightness: Double = 0,
        contrast: Double = 1,
        existingPageID: UUID? = nil
    ) {
        self.order = order
        self.image = image
        self.originalImage = originalImage ?? image
        self.committedQuad = committedQuad
        self.filter = filter
        self.brightness = brightness
        self.contrast = contrast
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
    /// Re-cropping preserves whichever filter and brightness/contrast are
    /// currently selected — they're not reset to their defaults.
    func commitCropIfNeeded() {
        guard let quad = pendingQuad, quad != committedQuad else {
            pendingQuad = nil
            return
        }
        committedQuad = quad
        pendingQuad = nil

        guard let corrected = PerspectiveCorrectionService.correct(image: originalImage, quad: quad) else { return }
        image = corrected
        reprocess(from: corrected, quad: quad)
    }

    /// Selects a new filter and re-derives `image` from `originalImage` +
    /// `committedQuad` with it applied. Crop is unaffected — this only
    /// re-processes the already-cropped image, it never re-runs perspective
    /// correction.
    func applyFilter(_ newFilter: DocumentFilter) {
        filter = newFilter
        reprocess(from: recroppedImage, quad: committedQuad)
    }

    /// Commits new Brightness/Contrast values (DESIGN_SPEC §4.3 "Adjust
    /// tool") and re-derives `image` with them applied on top of the
    /// current crop + filter. While the user is actively dragging a
    /// slider, the Adjust tool's overlay shows a live SwiftUI
    /// `.brightness()/.contrast()` preview instead of calling this on
    /// every frame — a full CoreImage pass per drag tick would be far too
    /// slow — and only calls this once, when the drag ends.
    func commitAdjustments(brightness: Double, contrast: Double) {
        self.brightness = brightness
        self.contrast = contrast
        reprocess(from: recroppedImage, quad: committedQuad)
    }

    /// `originalImage` perspective-corrected to `committedQuad`, or
    /// `originalImage` itself when there's nothing to crop — the base that
    /// `filter` and brightness/contrast both re-derive `image` from,
    /// shared by `applyFilter(_:)` and `commitAdjustments(brightness:contrast:)`.
    /// Also used by the Adjust tool's live-preview setup (`EditFlowView`)
    /// to compute a brightness/contrast-free base to preview against.
    var recroppedImage: UIImage {
        committedQuad == .fullImage
            ? originalImage
            : (PerspectiveCorrectionService.correct(image: originalImage, quad: committedQuad) ?? originalImage)
    }

    /// Shared "show the fast geometric result now, swap in the fully
    /// processed one shortly after" pattern used by `commitCropIfNeeded()`,
    /// `applyFilter(_:)`, and `commitAdjustments(brightness:contrast:)`.
    /// Guarded against `committedQuad`/`filter`/`brightness`/`contrast`
    /// having already moved on by the time this finishes, so a stale
    /// result can't clobber a newer crop, filter, or adjustment.
    private func reprocess(from base: UIImage, quad: Quad) {
        let filter = filter
        let brightness = brightness
        let contrast = contrast
        DocumentEnhancer.applyAsync(filter, to: base) { [weak self] filtered in
            guard let self, self.committedQuad == quad, self.filter == filter,
                  self.brightness == brightness, self.contrast == contrast else { return }
            DocumentEnhancer.applyAdjustmentsAsync(brightness: brightness, contrast: contrast, to: filtered) { [weak self] adjusted in
                guard let self, self.committedQuad == quad, self.filter == filter,
                      self.brightness == brightness, self.contrast == contrast else { return }
                self.image = adjusted
            }
        }
    }
}
