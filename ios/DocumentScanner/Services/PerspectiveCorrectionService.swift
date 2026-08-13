import CoreImage
import UIKit

/// Applies perspective correction to a page image given a user-adjusted
/// quad, via CoreImage's `CIPerspectiveCorrection`.
enum PerspectiveCorrectionService {
    private static let context = CIContext()

    /// - Parameters:
    ///   - image: source page image.
    ///   - quad: corners normalized to `image`'s size, in UIKit coordinate
    ///     convention (origin top-left, y down).
    static func correct(image: UIImage, quad: Quad) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let extent = ciImage.extent
        let w = extent.width
        let h = extent.height

        // CoreImage's coordinate space has origin bottom-left, so flip y.
        func point(_ p: CodablePoint) -> CGPoint {
            CGPoint(x: CGFloat(p.x) * w, y: (1 - CGFloat(p.y)) * h)
        }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: point(quad.topLeft)), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: point(quad.topRight)), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: point(quad.bottomRight)), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: point(quad.bottomLeft)), forKey: "inputBottomLeft")

        guard let output = filter.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }
}
