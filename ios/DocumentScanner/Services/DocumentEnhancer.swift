import CoreImage
import UIKit

/// Turns a cropped page photo into something that reads as a processed
/// "scan" rather than a raw photo, per the selected `DocumentFilter`
/// (DESIGN_SPEC §4.2 "scan filters" / §4.3 Filter tool):
/// - `.auto` — Apple's own built-in auto-enhance (the same pipeline
///   Photos' "Auto Enhance" uses) plus a modest contrast boost, a touch of
///   desaturation, and light sharpening, tuned for text-on-paper rather
///   than general photography.
/// - `.original` — no processing, the crop as captured.
/// - `.grayscale` — desaturated, mild contrast boost.
/// - `.blackAndWhite` — desaturated with a strong contrast/brightness push,
///   for the classic high-contrast "black text, white paper" scanner look.
///   This is an approximation via global contrast, not true adaptive
///   thresholding/binarization.
enum DocumentEnhancer {
    private static let context = CIContext()
    private static let queue = DispatchQueue(label: "com.dulatheo.documentscanner.document-enhance", qos: .userInitiated)

    /// Runs the selected filter synchronously on the calling thread.
    static func apply(_ filter: DocumentFilter, to image: UIImage) -> UIImage {
        switch filter {
        case .auto: return applyAutoEnhance(image)
        case .original: return image
        case .grayscale: return applyColorControls(image, saturation: 0.05, contrast: 1.08, brightness: 0)
        case .blackAndWhite: return applyColorControls(image, saturation: 0.0, contrast: 1.55, brightness: 0.06)
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

    private static func applyColorControls(_ image: UIImage, saturation: Double, contrast: Double, brightness: Double) -> UIImage {
        guard let source = CIImage(image: image) else { return image }
        guard let colorFilter = CIFilter(name: "CIColorControls") else { return image }
        colorFilter.setValue(source, forKey: kCIInputImageKey)
        colorFilter.setValue(saturation, forKey: kCIInputSaturationKey)
        colorFilter.setValue(contrast, forKey: kCIInputContrastKey)
        colorFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
        guard let output = colorFilter.outputImage else { return image }
        return render(output, scale: image.scale) ?? image
    }

    private static func render(_ ciImage: CIImage, scale: CGFloat) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}
