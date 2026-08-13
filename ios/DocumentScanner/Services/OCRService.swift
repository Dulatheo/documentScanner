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
                            normalizedBox: CGRectCodable(observation.boundingBox)
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
