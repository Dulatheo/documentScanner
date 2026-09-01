import UIKit
import Vision

/// On-device text recognition via `VNRecognizeTextRequest`.
enum OCRService {
    struct Result {
        var fullText: String
        var lines: [OCRLine]
    }

    /// Runs recognition on a background queue and returns full text plus
    /// per-line bounding boxes (normalized, Vision convention).
    static func recognize(_ image: UIImage) async -> Result {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: Result(fullText: "", lines: []))
                return
            }
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: Result(fullText: "", lines: []))
                    return
                }
                var lines: [OCRLine] = []
                var fullTextLines: [String] = []
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    fullTextLines.append(candidate.string)
                    lines.append(
                        OCRLine(
                            text: candidate.string,
                            normalizedBox: CGRectCodable(observation.boundingBox),
                            words: extractWords(from: candidate)
                        )
                    )
                }
                continuation.resume(
                    returning: Result(fullText: fullTextLines.joined(separator: "\n"), lines: lines)
                )
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: cgOrientation(from: image.imageOrientation),
                options: [:]
            )
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: Result(fullText: "", lines: []))
                }
            }
        }
    }

    /// Returns `page.ocrLines`, running OCR live and caching the result on
    /// `page` first if it hasn't been recognized yet. Normal editing only
    /// runs OCR when the Text/Highlight tool is opened, so a page that was
    /// scanned but never had either tool touched otherwise has nothing —
    /// DOCX/XLSX export (DESIGN_SPEC §5/§9) has no page image to fall back
    /// on the way PDF/JPG do, so it needs this to avoid exporting a blank
    /// document/sheet for a page nobody happened to run OCR on yet.
    static func ensureLines(for page: PageModel) async -> [OCRLine] {
        if !page.ocrLines.isEmpty { return page.ocrLines }
        guard let image = ImageStore.load(page.imagePath) else { return [] }
        let result = await recognize(image)
        page.ocrText = result.fullText
        page.ocrLines = result.lines
        return result.lines
    }

    /// Per-word bounding boxes within one recognized line, used only for
    /// DOCX table detection (DESIGN_SPEC §5/§9) — Vision's line-level API
    /// doesn't expose per-word boxes directly, but `boundingBox(for:)` can
    /// compute one for any substring range of the recognized string, so
    /// this slices the line on word boundaries and queries it per word.
    private static func extractWords(from candidate: VNRecognizedText) -> [OCRWord] {
        let string = candidate.string
        guard !string.isEmpty else { return [] }
        var words: [OCRWord] = []
        string.enumerateSubstrings(in: string.startIndex..<string.endIndex, options: .byWords) { substring, range, _, _ in
            guard let substring, let observation = try? candidate.boundingBox(for: range) else { return }
            words.append(OCRWord(text: substring, normalizedBox: CGRectCodable(observation.boundingBox)))
        }
        return words
    }

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
