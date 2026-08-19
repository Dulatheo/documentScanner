import CoreImage
import UIKit

/// Turns a cropped page photo into something that reads as a "scanned
/// document" rather than a raw photo — normalized exposure/color (Apple's
/// own built-in auto-enhance, the same pipeline Photos' "Auto Enhance"
/// uses) plus a modest contrast boost, a touch of desaturation, and light
/// sharpening, tuned for text-on-paper rather than general photography.
/// Applied automatically to every captured/imported page; there's no
/// user-facing filter picker (yet) — a reasonable, reconsiderable default
/// rather than the final word on this.
enum DocumentEnhancer {
    private static let context = CIContext()
    private static let queue = DispatchQueue(label: "com.dulatheo.documentscanner.document-enhance", qos: .userInitiated)

    /// Runs the enhancement pipeline synchronously on the calling thread.
    static func enhance(_ image: UIImage) -> UIImage {
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

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    /// Runs `enhance(_:)` off the main thread and calls back on it.
    /// The CoreImage pipeline above can take a noticeable fraction of a
    /// second on a full-resolution photo, and the capture path specifically
    /// needs to stay instant (the shutter's fly-to-stack animation is
    /// deliberately "no interruption") — callers should show the
    /// pre-enhancement (e.g. just perspective-corrected) result
    /// immediately and swap in `completion`'s result once it arrives,
    /// rather than waiting on this before showing anything.
    static func enhanceAsync(_ image: UIImage, completion: @escaping (UIImage) -> Void) {
        queue.async {
            let result = enhance(image)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
