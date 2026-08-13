import SwiftUI
import UIKit

/// Thin `UIViewControllerRepresentable` wrapper around
/// `UIActivityViewController` — per DESIGN_SPEC §4.6 this hands exported
/// files to the OS's native share surface (Messages/Mail/Files/Print/Copy…)
/// instead of a custom share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
