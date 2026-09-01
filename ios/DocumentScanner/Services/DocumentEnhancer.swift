import CoreImage
import UIKit

/// Turns a cropped page photo into something that reads as a processed
/// "scan" rather than a raw photo, per the selected `DocumentFilter`
/// (DESIGN_SPEC §4.2 "scan filters" / §4.3 Filter tool):
/// - `.auto` — a detected paper-white balance correction, then shadow
///   lifting to even out the page's lighting, Apple's own built-in
///   auto-enhance, and a modest contrast boost/touch of desaturation/light
///   sharpening, tuned for text-on-paper rather than general photography.
/// - `.original` — no processing, the crop as captured.
/// - `.grayscale` — white-balanced and shadow-lifted first (see `.auto`),
///   then desaturated with a mild contrast boost.
/// - `.blackAndWhite` — white-balanced and more aggressively shadow-lifted,
///   then desaturated with a strong contrast/brightness push, for the
///   classic high-contrast "black text, white paper" scanner look. The
///   shadow-lift step is what makes this closer to real adaptive
///   thresholding than a single global contrast curve: without first
///   flattening an uneven light source (a hand's shadow, an angled desk
///   lamp), the same global threshold leaves the shadowed half of the page
///   gray or blotchy while the lit half blows out to solid white.
enum DocumentEnhancer {
    private static let context = CIContext()
    private static let queue = DispatchQueue(label: "com.dulatheo.documentscanner.document-enhance", qos: .userInitiated)

    /// Runs the selected filter synchronously on the calling thread.
    static func apply(_ filter: DocumentFilter, to image: UIImage) -> UIImage {
        switch filter {
        case .auto: return applyAutoEnhance(image)
        case .original: return image
        case .grayscale: return applyColorControls(image, saturation: 0.05, contrast: 1.08, brightness: 0, shadowAmount: 0.35)
        case .blackAndWhite: return applyColorControls(image, saturation: 0.0, contrast: 1.55, brightness: 0.06, shadowAmount: 0.6)
        }
    }

    /// Runs `apply(_:to:)` off the main thread and calls back on it.
    /// The CoreImage pipeline above can take a noticeable fraction of a
    /// second on a full-resolution photo, and the capture path specifically
    /// needs to stay instant (the shutter's fly-to-stack animation is
    /// deliberately "no interruption") — callers should show the
    /// pre-filter (e.g. just perspective-corrected) result immediately and
    /// swap in `completion`'s result once it arrives, rather than waiting
    /// on this before showing anything.
    static func applyAsync(_ filter: DocumentFilter, to image: UIImage, completion: @escaping (UIImage) -> Void) {
        queue.async {
            let result = apply(filter, to: image)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    // MARK: - Pipelines

    private static func applyAutoEnhance(_ image: UIImage) -> UIImage {
        guard var ciImage = CIImage(image: image) else { return image }

        ciImage = whiteBalanced(ciImage) ?? ciImage
        ciImage = flattenLighting(ciImage, shadowAmount: 0.45, highlightAmount: 0.9) ?? ciImage

        for filter in ciImage.autoAdjustmentFilters(options: [.enhance: true]) {
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                ciImage = output
            }
        }

        if let colorFilter = CIFilter(name: "CIColorControls") {
            colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
            colorFilter.setValue(1.12, forKey: kCIInputContrastKey)
            colorFilter.setValue(0.92, forKey: kCIInputSaturationKey)
            if let output = colorFilter.outputImage {
                ciImage = output
            }
        }

        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(ciImage, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.4, forKey: kCIInputSharpnessKey)
            if let output = sharpenFilter.outputImage {
                ciImage = output
            }
        }

        return render(ciImage, scale: image.scale) ?? image
    }

    private static func applyColorControls(_ image: UIImage, saturation: Double, contrast: Double, brightness: Double, shadowAmount: Double) -> UIImage {
        guard let source = CIImage(image: image) else { return image }
        var ciImage = whiteBalanced(source) ?? source
        ciImage = flattenLighting(ciImage, shadowAmount: shadowAmount, highlightAmount: 0.85) ?? ciImage

        guard let colorFilter = CIFilter(name: "CIColorControls") else { return image }
        colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
        colorFilter.setValue(saturation, forKey: kCIInputSaturationKey)
        colorFilter.setValue(contrast, forKey: kCIInputContrastKey)
        colorFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
        guard let output = colorFilter.outputImage else { return image }
        return render(output, scale: image.scale) ?? image
    }

    /// Lifts shadows and gently rolls off highlights so a page lit unevenly
    /// (a hand's shadow, an angled desk lamp) reads as flat, consistently
    /// lit paper — `CIHighlightShadowAdjust` does this with local, edge-aware
    /// tone mapping (the same building block behind Photos' Shadows/
    /// Highlights sliders), rather than a single global brightness curve
    /// that can only push the whole image lighter or darker at once.
    private static func flattenLighting(_ image: CIImage, shadowAmount: Double, highlightAmount: Double) -> CIImage? {
        guard let filter = CIFilter(name: "CIHighlightShadowAdjust") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(shadowAmount, forKey: "inputShadowAmount")
        filter.setValue(highlightAmount, forKey: "inputHighlightAmount")
        return filter.outputImage
    }

    /// Estimates the page's true paper color from the brightest pixels in
    /// the shot and neutralizes it to white, removing whatever color cast
    /// a warm lamp or a cool overcast window left on the photo — rather
    /// than trusting the camera's own white balance, which is tuned for
    /// general photography, not "this region of the frame is blank paper."
    private static func whiteBalanced(_ image: CIImage) -> CIImage? {
        guard let paperColor = brightestColor(in: image) else { return nil }
        // A dim or strongly tinted max means there's no reliable paper
        // white to find (a very dark or already off-color shot) — forcing
        // a white point against it would do more harm than good.
        guard paperColor.red > 0.55, paperColor.green > 0.55, paperColor.blue > 0.55 else { return nil }
        guard let filter = CIFilter(name: "CIWhitePointAdjust") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(paperColor, forKey: kCIInputColorKey)
        return filter.outputImage
    }

    /// The per-channel brightest pixel values in `image` (`CIAreaMaximum`,
    /// a single-pass reduction filter), read back via a 1x1 bitmap render —
    /// used as a stand-in for "the color of the blank paper," since paper
    /// is normally the brightest thing in a document photo.
    private static func brightestColor(in image: CIImage) -> CIColor? {
        guard let filter = CIFilter(name: "CIAreaMaximum") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: output.extent,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return CIColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255
        )
    }

    private static func render(_ ciImage: CIImage, scale: CGFloat) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
