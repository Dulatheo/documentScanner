import SwiftUI

/// The page image plus whichever tool overlay is currently active, per
/// DESIGN_SPEC §4.3. Lives inside the `paper` card drawn by `EditFlowView`.
struct PageEditorView: View {
    @ObservedObject var pageState: PageEditState
    let activeTool: EditTool?
    @Binding var placingSignature: Signature?

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Image(uiImage: pageState.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)

                if activeTool != .highlight, !pageState.highlightRegions.isEmpty {
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

                if let placing = placingSignature {
                    SignaturePlacementView(
                        signature: Binding(get: { placing }, set: { placingSignature = $0 }),
                        pageSize: size
                    )
                } else if let committed = pageState.signature {
                    let width = CGFloat(committed.width) * size.width
                    let height = width * CGFloat(committed.aspectRatio)
                    SignatureStrokesView(signature: committed, colorScheme: colorScheme)
                        .frame(width: width, height: height)
                        .position(x: CGFloat(committed.x) * size.width + width / 2, y: CGFloat(committed.y) * size.height + height / 2)
                }
            }
        }
        .aspectRatio(pageState.image.size, contentMode: .fit)
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
