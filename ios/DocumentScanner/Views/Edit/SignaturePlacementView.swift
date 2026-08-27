import Foundation
import SwiftUI

/// Placement mode after signing (DESIGN_SPEC §4.3): the signature can be
/// dragged, resized (corner handle), and rotated (corner handle) over the
/// page before Done commits it. `signature.x/y/width` are normalized to
/// `pageSize`; `signature.rotation` is degrees around its own center.
struct SignaturePlacementView: View {
    @Binding var signature: Signature
    let pageSize: CGSize

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragStartOrigin: CGPoint?
    @State private var resizeStartWidth: CGFloat?
    @State private var rotateLastAngle: Double?

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
            // `.highPriorityGesture` plus `minimumDistance: 0` (see
            // dragGesture below): this view lives inside EditFlowView's
            // per-page `TabView(.page style)` (added later, for swipeable
            // pages) nested inside a vertical ScrollView. The TabView's
            // paging is backed by a native UIScrollView, which SwiftUI's own
            // gesture-priority APIs can't fully out-arbitrate the way they
            // can another SwiftUI `Gesture` — but `DragGesture`'s *default*
            // 10pt `minimumDistance` was giving the page-swipe recognizer a
            // head start specifically on horizontal motion (it doesn't
            // contest vertical motion the same way, which is why the
            // reported symptom was always "moves in Y, never X," not a bug
            // in the x/y math below). Recognizing on the very first touch
            // point removes that head start.
            .highPriorityGesture(dragGesture(width: width, height: height))
            .overlay(alignment: .topLeading) {
                resizeHandle(width: width, height: height, originX: originX, originY: originY)
                rotateHandle(width: width, height: height, originX: originX, originY: originY)
            }
            .coordinateSpace(name: Self.spaceName)
    }

    private func dragGesture(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.spaceName))
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
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.spaceName))
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

    /// Rotate handle, top-right corner — a single-finger drag rather than a
    /// two-finger `RotationGesture` twist (the "standard iOS convention" this
    /// view originally used): a two-finger gesture nested inside a
    /// scroll/page-swipe stack is markedly less reliable to recognize than a
    /// one-finger drag competing for the same priority fight described on
    /// `dragGesture` above, and it isn't hinted anywhere in the UI, so it
    /// wasn't discoverable either. Tracks the touch's angle around the
    /// signature's own center and applies only the *change* in angle each
    /// frame, so grabbing the handle doesn't snap the signature to point at
    /// the finger.
    private func rotateHandle(width: CGFloat, height: CGFloat, originX: CGFloat, originY: CGFloat) -> some View {
        let center = CGPoint(x: originX + width / 2, y: originY + height / 2)
        return Circle()
            .fill(theme.accent)
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: "rotate.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            )
            .overlay(Circle().stroke(theme.paper, lineWidth: 2))
            .position(x: originX + width + 20, y: originY - 20)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.spaceName))
                    .onChanged { value in
                        let angle = atan2(Double(value.location.y - center.y), Double(value.location.x - center.x))
                        guard let last = rotateLastAngle else {
                            rotateLastAngle = angle
                            return
                        }
                        var deltaDegrees = (angle - last) * 180 / .pi
                        // Normalize a wraparound jump (crossing the ±180°
                        // seam) to the short way round, so the signature
                        // doesn't spin an extra near-full turn when the
                        // finger crosses it.
                        if deltaDegrees > 180 { deltaDegrees -= 360 }
                        if deltaDegrees < -180 { deltaDegrees += 360 }
                        signature.rotation += deltaDegrees
                        rotateLastAngle = angle
                    }
                    .onEnded { _ in rotateLastAngle = nil }
            )
    }
}
