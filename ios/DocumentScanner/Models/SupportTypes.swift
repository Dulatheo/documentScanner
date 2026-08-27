import CoreGraphics
import Foundation

/// Codable mirror of `CGPoint` so stroke data can round-trip through JSON
/// stored in SwiftData `Data` attributes.
struct CodablePoint: Codable, Hashable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = Double(point.x)
        y = Double(point.y)
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// Four corner points of a perspective quad, normalized to the source
/// image's [0,1] coordinate space, in clockwise order starting top-left.
struct Quad: Codable, Hashable {
    var topLeft: CodablePoint
    var topRight: CodablePoint
    var bottomRight: CodablePoint
    var bottomLeft: CodablePoint

    static let fullImage = Quad(
        topLeft: CodablePoint(x: 0, y: 0),
        topRight: CodablePoint(x: 1, y: 0),
        bottomRight: CodablePoint(x: 1, y: 1),
        bottomLeft: CodablePoint(x: 0, y: 1)
    )
}

/// One recognized line of text from `VNRecognizeTextRequest`, with its
/// bounding box normalized to the page image (Vision's coordinate space:
/// origin bottom-left, unit square).
struct OCRLine: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var text: String
    /// Normalized rect, Vision convention (origin bottom-left).
    var normalizedBox: CGRectCodable
}

/// Codable `CGRect` mirror.
struct CGRectCodable: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// A highlighted OCR line, referenced by the line's stable id plus a copy of
/// its box (so highlights still render even if OCR is re-run later).
struct HighlightRegion: Codable, Hashable, Identifiable {
    var id: UUID
    var lineID: UUID
    var normalizedBox: CGRectCodable
}

/// One free-hand stroke, as an ordered list of points normalized to the
/// signature's own bounding box ([0,1] in both axes).
struct SignatureStroke: Codable, Hashable {
    var points: [CodablePoint]
}

/// A signature: its ink strokes plus placement on the page. `x`, `y`,
/// `width` are normalized to the page image size; height is derived from
/// the aspect ratio of the drawing canvas.
struct Signature: Codable, Hashable {
    var strokes: [SignatureStroke]
    var color: Theme.SignatureColor
    /// Normalized as a fraction of the signature's own rendered width, so
    /// strokes stay proportional at any placement size.
    var thickness: Double
    var x: Double
    var y: Double
    var width: Double
    /// Aspect ratio (height / width) of the canvas the strokes were drawn in,
    /// so placement scaling keeps strokes proportional.
    var aspectRatio: Double
    /// Rotation around the signature's own center, in degrees (SwiftUI's
    /// `.rotationEffect` convention: positive = clockwise).
    var rotation: Double = 0

    init(
        strokes: [SignatureStroke],
        color: Theme.SignatureColor,
        thickness: Double,
        x: Double,
        y: Double,
        width: Double,
        aspectRatio: Double,
        rotation: Double = 0
    ) {
        self.strokes = strokes
        self.color = color
        self.thickness = thickness
        self.x = x
        self.y = y
        self.width = width
        self.aspectRatio = aspectRatio
        self.rotation = rotation
    }

    private enum CodingKeys: String, CodingKey {
        case strokes, color, thickness, x, y, width, aspectRatio, rotation
    }

    /// Custom decoding so documents saved before `rotation` existed (real
    /// on-device test data from earlier in this app's development) still
    /// decode instead of crashing on a missing key — the synthesized
    /// `Decodable` conformance a plain stored-property default doesn't get
    /// you would require every key to be present.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        strokes = try container.decode([SignatureStroke].self, forKey: .strokes)
        color = try container.decode(Theme.SignatureColor.self, forKey: .color)
        thickness = try container.decode(Double.self, forKey: .thickness)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        aspectRatio = try container.decode(Double.self, forKey: .aspectRatio)
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
    }
}

enum EditTool: String, CaseIterable, Identifiable, Hashable {
    case crop, highlight, ocr, sign
    var id: String { rawValue }

    var label: String {
        switch self {
        case .crop: return "Crop"
        case .highlight: return "Highlight"
        case .ocr: return "Text"
        case .sign: return "Sign"
        }
    }

    var systemImage: String {
        switch self {
        case .crop: return "crop"
        case .highlight: return "highlighter"
        case .ocr: return "text.viewfinder"
        case .sign: return "signature"
        }
    }

    var hint: String {
        switch self {
        case .crop: return "Drag the corners to fit the page"
        case .highlight: return "Tap a line of text to highlight it"
        case .ocr: return "Text recognition"
        case .sign: return "Draw your signature"
        }
    }
}

/// The scan-processing look applied to a page's cropped image
/// (DESIGN_SPEC §4.2 "scan filters" / §4.3 Filter tool). Selectable per
/// page, persisted alongside the rest of the page's edits.
enum DocumentFilter: String, CaseIterable, Identifiable, Codable, Hashable {
    case auto, original, grayscale, blackAndWhite
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .original: return "Original"
        case .grayscale: return "Grayscale"
        case .blackAndWhite: return "B&W"
        }
    }
}
