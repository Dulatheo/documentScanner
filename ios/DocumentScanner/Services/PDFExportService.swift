import CoreText
import UIKit

/// Builds a multi-page PDF from a document's pages, embedding recognized
/// text as an invisible (rendering-mode 3) text layer over each OCR'd line
/// so the page image stays visually unchanged but the PDF becomes
/// searchable/selectable — the same trick "OCR a PDF" tools use.
enum PDFExportService {
    static func makePDF(for document: DocumentModel) -> URL {
        let pages = document.orderedPages
        let renderer = UIGraphicsPDFRenderer(bounds: .zero)

        let data = renderer.pdfData { context in
            for page in pages {
                guard let base = ImageStore.load(page.imagePath) else { continue }
                let flattened = PageRenderer.flatten(
                    base: base,
                    highlightRegions: page.highlightRegions,
                    signature: page.signature
                )
                let pageRect = CGRect(origin: .zero, size: flattened.size)
                context.beginPage(withBounds: pageRect, pageInfo: [:])
                flattened.draw(in: pageRect)
                drawInvisibleTextLayer(lines: page.ocrLines, in: context.cgContext, pageSize: flattened.size)
            }
        }

        let filename = sanitizedFilename(document.name) + ".pdf"
        return ImageStore.writeExportFile(data: data, filename: filename)
    }

    /// Draws each recognized line's text at its bounding box using Core
    /// Text with an invisible text-rendering mode: it contributes to the
    /// PDF's text/selection layer without changing what's visible.
    private static func drawInvisibleTextLayer(lines: [OCRLine], in cgContext: CGContext, pageSize: CGSize) {
        guard !lines.isEmpty else { return }
        cgContext.saveGState()
        cgContext.setTextDrawingMode(.invisible)

        // UIGraphicsPDFRenderer's context is flipped to UIKit convention
        // (origin top-left, y down) so `UIImage.draw(in:)` above lands
        // correctly. Core Text expects standard PDF convention (origin
        // bottom-left, y up), so undo the flip just for text drawing —
        // then Vision's bottom-left-normalized boxes map directly.
        cgContext.translateBy(x: 0, y: pageSize.height)
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.textMatrix = .identity

        for line in lines {
            let box = line.normalizedBox.cgRect
            let rectHeight = box.size.height * pageSize.height
            let fontSize = max(rectHeight * 0.82, 4)
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black.cgColor,
            ]
            let attributed = NSAttributedString(string: line.text, attributes: attributes)
            let ctLine = CTLineCreateWithAttributedString(attributed)

            let originX = box.origin.x * pageSize.width
            let originY = box.origin.y * pageSize.height

            cgContext.textPosition = CGPoint(x: originX, y: originY)
            CTLineDraw(ctLine, cgContext)
        }
        cgContext.restoreGState()
    }

    static func sanitizedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalid).joined(separator: "-")
    }
}
