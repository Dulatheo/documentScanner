import UIKit

/// Reads/writes page images as JPEG files in the app sandbox. SwiftData
/// models store only the filename returned here, never image bytes.
enum ImageStore {
    static var pagesDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Pages", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Writes `image` as JPEG and returns the filename to persist.
    @discardableResult
    static func save(_ image: UIImage, quality: CGFloat = 0.88) -> String {
        let filename = "\(UUID().uuidString).jpg"
        let url = pagesDirectory.appendingPathComponent(filename)
        if let data = image.jpegData(compressionQuality: quality) {
            try? data.write(to: url, options: .atomic)
        }
        return filename
    }

    static func load(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        let url = pagesDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        let url = pagesDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes arbitrary export output (PDF or JPG) to a temp directory for
    /// handoff to `UIActivityViewController`.
    static func writeExportFile(data: Data, filename: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let url = dir.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        return url
    }
}
