import SwiftUI

/// Drives the transient confirmation pill described in DESIGN_SPEC §4.7
/// ("Saved to Documents", "Signature added", "Copied", …). One instance is
/// installed near the root and shared via the environment.
@MainActor
final class ToastCenter: ObservableObject {
    @Published var message: String?

    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, duration: TimeInterval = 1.6) {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            self.message = message
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    self?.message = nil
                }
            }
        }
    }
}
