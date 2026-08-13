import Foundation
import SwiftData

/// A saved, scanned document: an ordered set of pages plus comments.
/// Page images live as files in the sandbox (see `ImageStore`); only their
/// paths are persisted here.
@Model
final class DocumentModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PageModel.document)
    var pages: [PageModel] = []

    @Relationship(deleteRule: .cascade, inverse: \CommentModel.document)
    var comments: [CommentModel] = []

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    var orderedPages: [PageModel] {
        pages.sorted { $0.order < $1.order }
    }

    var pageCountLabel: String {
        let n = pages.count
        return n == 1 ? "1 pg" : "\(n) pgs"
    }

    var sortedComments: [CommentModel] {
        comments.sorted { $0.createdAt < $1.createdAt }
    }
}
