import SwiftUI

/// The page image plus whichever tool overlay is currently active, per
/// DESIGN_SPEC §4.3. Lives inside the `paper` card drawn by `EditFlowView`.
struct PageEditorView: View {
    @ObservedObject var pageState: PageEditState
    let activeTool: EditTool?
    @Binding var placingSignature: Signature?
    /// The current crop + filter result with brightness/contrast still
    /// neutral (DESIGN_SPEC §4.3 "Adjust tool") — nil for every page except
    /// the one actually being edited, and nil there too until `EditFlowView`
    /// finishes computing it. See `displayImage`.
    var adjustPreviewImage: UIImage? = nil
    var liveBrightness: Double = 0
    var liveContrast: Double = 1

    @Environment(\.theme) private var theme

    /// `pendingQuad`/`committedQuad` are normalized to `originalImage` (see
    /// `PageEditState`), and `commitCropIfNeeded()` always perspective-corrects
    /// from `originalImage`. So while the Crop tool is active, the base image
    /// shown here must be `originalImage` too — otherwise, on a second-or-later
    /// crop of the same page, the on-screen drag coordinates (and the `size`
    /// used to scale/normalize them) would be measured against the previous
    /// crop's (differently-sized) result while the actual crop math runs
    /// against the pristine original, producing a wrong crop region.
    ///
    /// While the Adjust tool is active and its preview base is ready, that
    /// brightness/contrast-neutral base is shown instead of `pageState.image`
    /// (which already has the *previous* committed brightness/contrast baked
    /// in) — the live `.brightness()/.contrast()` modifiers below apply on
    /// top of it, so they represent the slider's absolute position rather
    /// than stacking on top of an already-adjusted image.
    private var displayImage: UIImage {
        if activeTool == .crop { return pageState.originalImage }
        if activeTool == .adjust, let adjustPreviewImage { return adjustPreviewImage }
        return pageState.image
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Image(uiImage: displayImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .brightness(activeTool == .adjust && adjustPreviewImage != nil ? liveBrightness : 0)
                    .contrast(activeTool == .adjust && adjustPreviewImage != nil ? liveContrast : 1)

                if activeTool != .highlight, activeTool != .crop, !pageState.highlightRegions.isEmpty {
                    committedHighlights(imageSize: pageState.image.size, size: size)
                }

                if activeTool == .highlight {
                    HighlightOverlayView(
                        lines: pageState.ocrLines,
                        highlightedIDs: pageState.highlightedLineIDs,
                        imageSize: pageState.image.size,
                        size: size
                    ) { line in
                        pageState.toggleHighlight(for: line)
                    }
                }

                if activeTool == .crop {
                    CropOverlayView(
                        quad: Binding(
                            get: { pageState.pendingQuad ?? pageState.committedQuad },
                            set: { pageState.pendingQuad = $0 }
                        ),
                        size: size
                    )
                }

                if activeTool != .crop {
                    if let placing = placingSignature {
                        // The getter reads `placingSignature` itself (falling
                        // back to `placing` only for the type checker, since
                        // this branch guarantees it's non-nil) rather than
                        // closing over `placing` as a fixed snapshot. Signature
                        // placement writes `.x` and `.y` as two separate
                        // statements in the same drag callback — with a
                        // snapshot-capturing getter, the second write reads
                        // that same stale snapshot instead of the first
                        // write's result and overwrites it, so `x` updates
                        // were silently discarded every time (whichever
                        // field is written last always "wins," which is
                        // exactly why signatures could only ever move
                        // vertically).
                        SignaturePlacementView(
                            signature: Binding(get: { placingSignature ?? placing }, set: { placingSignature = $0 }),
                            pageSize: size
                        )
                    } else if let committed = pageState.signature {
                        let width = CGFloat(committed.width) * size.width
                        let height = width * CGFloat(committed.aspectRatio)
                        SignatureStrokesView(signature: committed)
                            .frame(width: width, height: height)
                            .rotationEffect(.degrees(committed.rotation))
                            .position(x: CGFloat(committed.x) * size.width + width / 2, y: CGFloat(committed.y) * size.height + height / 2)
                    }
                }
            }
        }
        .aspectRatio(displayImage.size, contentMode: .fit)
    }

    private func committedHighlights(imageSize: CGSize, size: CGSize) -> some View {
        let scale = imageSize.width > 0 ? size.width / imageSize.width : 1
        return ForEach(pageState.highlightRegions) { region in
            let rect = PageRenderer.pixelRect(fromVisionNormalized: region.normalizedBox, imageSize: imageSize)
            Rectangle()
                .fill(theme.highlight)
                .frame(width: rect.width * scale, height: rect.height * scale)
                .position(x: rect.midX * scale, y: rect.midY * scale)
                .blendMode(.multiply)
        }
    }
}
