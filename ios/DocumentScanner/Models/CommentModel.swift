import Foundation
import SwiftData

@Model
final class CommentModel {
    @Attribute(.unique) var id: UUID
    var text: String
    var authorLabel: String
    var createdAt: Date
    var pageIndex: Int?

    var document: DocumentModel?

    init(
        id: UUID = UUID(),
        text: String,
        authorLabel: String = "You",
        createdAt: Date = Date(),
        pageIndex: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.authorLabel = authorLabel
        self.createdAt = createdAt
        self.pageIndex = pageIndex
    }

    /// e.g. "You · 2h ago · page 1"
    func metaLabel() -> String {
        let relative = Self.relativeFormatter.localizedString(for: createdAt, relativeTo: Date())
        if let pageIndex {
            return "\(authorLabel) · \(relative) · page \(pageIndex + 1)"
        }
        return "\(authorLabel) · \(relative)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
