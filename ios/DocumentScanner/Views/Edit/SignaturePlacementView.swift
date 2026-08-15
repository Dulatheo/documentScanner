import SwiftUI

/// Placement mode after signing (DESIGN_SPEC §4.3): the signature can be
/// dragged, resized (corner handle), and rotated (two-finger twist) over
/// the page before Done commits it. `signature.x/y/width` are normalized
/// to `pageSize`; `signature.rotation` is degrees around its own center.
struct SignaturePlacementView: View {
    @Binding var signature: Signature
    let pageSize: CGSize

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragStartOrigin: CGPoint?
    @State private var resizeStartWidth: CGFloat?
    @State private var rotationStartDegrees: Double?

    private static let spaceName = "signaturePlacement"

    var body: some View {
        let width = CGFloat(signature.width) * pageSize.width
        let height = width * CGFloat(signature.aspectRatio)
        let originX = CGFloat(signature.x) * pageSize.width
        let originY = CGFloat(signature.y) * pageSize.height

        SignatureStrokesView(signature: signature, colorScheme: colorScheme)
            .frame(width: width, height: height)
            .padding(10)
            .background(theme.accentSoft)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .rotationEffect(.degrees(signature.rotation))
            .position(x: originX + width / 2 + 10, y: originY + height / 2 + 10)
            // `.highPriorityGesture` rather than `.gesture`: this view lives
            // inside EditFlowView's vertical ScrollView, whose own pan
            // recognizer can otherwise win arbitration for part of a plain
            // `.gesture`'s touch sequence — the reported symptom (drag only
            // ever moving the signature vertically, horizontal movement
            // never registering) is exactly that class of gesture-priority
            // conflict, not a bug in the x/y math below (which was already
            // computing both axes correctly). Forcing this gesture to win
            // over the ancestor ScrollView fixes it regardless of the exact
            // arbitration mechanism.
            .highPriorityGesture(SimultaneousGesture(dragGesture(width: width, height: height), rotationGesture()))
            .overlay(alignment: .topLeading) {
                resizeHandle(width: width, height: height, originX: originX, originY: originY)
            }
            .coordinateSpace(name: Self.spaceName)
    }

    private func dragGesture(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.spaceName))
            .onChanged { value in
                if dragStartOrigin == nil {
                    dragStartOrigin = CGPoint(x: CGFloat(signature.x) * pageSize.width, y: CGFloat(signature.y) * pageSize.height)
                }
                guard let start = dragStartOrigin else { return }
                let newX = start.x + value.translation.width
                let newY = start.y + value.translation.height
                let maxX = max(pageSize.width - width, 0)
                let maxY = max(pageSize.height - height, 0)
                signature.x = Double(min(max(newX, 0), maxX)) / Double(pageSize.width)
                signature.y = Double(min(max(newY, 0), maxY)) / Double(pageSize.height)
            }
            .onEnded { _ in dragStartOrigin = nil }
    }

    /// Two-finger twist, simultaneous with the one-finger move drag above —
    /// the standard iOS pattern for combining move + rotate on one object
    /// (Markup, Photos, etc.), rather than overloading the single-finger
    /// resize-handle drag with a second, less discoverable meaning.
    private func rotationGesture() -> some Gesture {
        RotationGesture()
            .onChanged { angle in
                if rotationStartDegrees == nil {
                    rotationStartDegrees = signature.rotation
                }
                signature.rotation = (rotationStartDegrees ?? 0) + angle.degrees
            }
            .onEnded { _ in rotationStartDegrees = nil }
    }

    private func resizeHandle(width: CGFloat, height: CGFloat, originX: CGFloat, originY: CGFloat) -> some View {
        Circle()
            .fill(theme.accent)
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            )
            .overlay(Circle().stroke(theme.paper, lineWidth: 2))
            .position(x: originX + width + 20, y: originY + height + 20)
            .highPriorityGesture(
                DragGesture(coordinateSpace: .named(Self.spaceName))
                    .onChanged { value in
                        if resizeStartWidth == nil {
                            resizeStartWidth = CGFloat(signature.width) * pageSize.width
                        }
                        guard let startWidth = resizeStartWidth else { return }
                        let newWidth = min(max(startWidth + value.translation.width, 40), pageSize.width - originX)
                        signature.width = Double(newWidth) / Double(pageSize.width)
                    }
                    .onEnded { _ in resizeStartWidth = nil }
            )
    }
}
