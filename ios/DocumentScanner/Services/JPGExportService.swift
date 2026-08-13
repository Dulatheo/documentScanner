import UIKit

/// Exports one JPG file per page (flattened with highlights/signature).
enum JPGExportService {
    static func makeJPGs(for document: DocumentModel) -> [URL] {
        let pages = document.orderedPages
        let base = PDFExportService.sanitizedFilename(document.name)
        var urls: [URL] = []
        for (index, page) in pages.enumerated() {
            guard let baseImage = ImageStore.load(page.imagePath) else { continue }
            let flattened = PageRenderer.flatten(
                base: baseImage,
                highlightRegions: page.highlightRegions,
                signature: page.signature
            )
            guard let data = flattened.jpegData(compressionQuality: 0.9) else { continue }
            let filename = pages.count > 1 ? "\(base)-\(index + 1).jpg" : "\(base).jpg"
            urls.append(ImageStore.writeExportFile(data: data, filename: filename))
        }
        return urls
    }
}
