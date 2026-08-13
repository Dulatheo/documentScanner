import SwiftUI

/// Renders `ToastCenter.message` as the dark pill from DESIGN_SPEC §4.7,
/// centered and low on screen. Add via `.toastOverlay()` near the root.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                Capsule().fill(Color(red: 20 / 255, green: 19 / 255, blue: 18 / 255).opacity(0.92))
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ToastOverlayModifier: ViewModifier {
    @ObservedObject var toastCenter: ToastCenter

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = toastCenter.message {
                ToastView(message: message)
                    .padding(.bottom, 170)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Pass the shared `ToastCenter` explicitly rather than resolving it via
    /// `@EnvironmentObject`, so the toast overlay doesn't depend on the
    /// environment propagating correctly across `.sheet`/`.fullScreenCover`
    /// presentation boundaries.
    func toastOverlay(_ toastCenter: ToastCenter) -> some View {
        modifier(ToastOverlayModifier(toastCenter: toastCenter))
    }
}
