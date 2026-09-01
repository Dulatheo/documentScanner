import Foundation
import SwiftData

/// One page of a document. `imagePath`/`originalImagePath` are filenames
/// relative to `ImageStore.pagesDirectory`, not blobs — the pixels live on
/// disk, only the reference is persisted.
@Model
final class PageModel {
    @Attribute(.unique) var id: UUID
    var order: Int

    /// Perspective-corrected (cropped) page image, no highlight/signature
    /// baked in — those are composited at render time from the fields below.
    var imagePath: String
    /// Pre-crop capture, kept so the Crop tool can be re-applied from
    /// scratch later.
    var originalImagePath: String?

    var ocrText: String?
    private var ocrLinesData: Data?
    private var highlightRegionsData: Data?
    private var signatureData: Data?
    private var filterRawValue: String = DocumentFilter.auto.rawValue
    var brightness: Double = 0
    var contrast: Double = 1

    var document: DocumentModel?

    init(
        id: UUID = UUID(),
        order: Int,
        imagePath: String,
        originalImagePath: String? = nil
    ) {
        self.id = id
        self.order = order
        self.imagePath = imagePath
        self.originalImagePath = originalImagePath
    }

    // MARK: - Codable-backed convenience accessors

    var ocrLines: [OCRLine] {
        get { Self.decode([OCRLine].self, from: ocrLinesData) ?? [] }
        set { ocrLinesData = Self.encode(newValue) }
    }

    var highlightRegions: [HighlightRegion] {
        get { Self.decode([HighlightRegion].self, from: highlightRegionsData) ?? [] }
        set { highlightRegionsData = Self.encode(newValue) }
    }

    var signature: Signature? {
        get { Self.decode(Signature.self, from: signatureData) }
        set { signatureData = newValue.flatMap { Self.encode($0) } }
    }

    var filter: DocumentFilter {
        get { DocumentFilter(rawValue: filterRawValue) ?? .auto }
        set { filterRawValue = newValue.rawValue }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
