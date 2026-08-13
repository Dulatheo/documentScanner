import PhotosUI
import SwiftUI
import UIKit

/// Imports one or more existing photos as document pages. This is our
/// stand-in for the mock's in-camera "gallery" button (§4.2): since
/// `VNDocumentCameraViewController` owns its own full-screen UI and has no
/// slot for a custom gallery affordance, gallery import is offered as a
/// sibling entry point next to "Scan a document" instead. Uses `PHPicker`,
/// which needs no photo-library permission prompt for the picked assets
/// themselves; `NSPhotoLibraryUsageDescription` is included for the (rare)
/// fallback path some OS versions still surface.
struct PhotoImportPicker: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        let controller = PHPickerViewController(configuration: config)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                onCancel()
                return
            }
            let providers = results.map(\.itemProvider)
            var images = [UIImage?](repeating: nil, count: providers.count)
            let group = DispatchGroup()

            for (index, provider) in providers.enumerated() where provider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    images[index] = object as? UIImage
                    group.leave()
                }
            }

            group.notify(queue: .main) { [onFinish] in
                onFinish(images.compactMap { $0 })
            }
        }
    }
}
