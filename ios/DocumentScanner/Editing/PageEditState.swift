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

    /// Existing page id, when this state is editing an already-saved page
    /// (nil for a page captured in this session that hasn't been saved yet).
    var existingPageID: UUID?

    init(order: Int, image: UIImage, originalImage: UIImage? = nil, existingPageID: UUID? = nil) {
        self.order = order
        self.image = image
        self.originalImage = originalImage ?? image
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
    func commitCropIfNeeded() {
        guard let quad = pendingQuad, quad != committedQuad else {
            pendingQuad = nil
            return
        }
        if let corrected = PerspectiveCorrectionService.correct(image: originalImage, quad: quad) {
            image = corrected
        }
        committedQuad = quad
        pendingQuad = nil
    }
}
