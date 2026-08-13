import SwiftUI

/// Draggable-corner quad refinement for the Crop tool (DESIGN_SPEC §4.3).
/// VisionKit already auto-crops on capture; this lets the user nudge the
/// four corners before perspective correction is re-applied.
struct CropOverlayView: View {
    @Binding var quad: Quad
    let size: CGSize

    @Environment(\.theme) private var theme

    private var points: [CGPoint] {
        [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft].map {
            CGPoint(x: CGFloat($0.x) * size.width, y: CGFloat($0.y) * size.height)
        }
    }

    var body: some View {
        ZStack {
            Path { path in
                let pts = points
                guard let first = pts.first else { return }
                path.move(to: first)
                for p in pts.dropFirst() { path.addLine(to: p) }
                path.closeSubpath()
            }
            .stroke(theme.accent, lineWidth: 1.5)

            Path { path in
                let pts = points
                guard let first = pts.first else { return }
                path.move(to: first)
                for p in pts.dropFirst() { path.addLine(to: p) }
                path.closeSubpath()
            }
            .fill(theme.accent.opacity(0.06))

            handle(for: \.topLeft)
            handle(for: \.topRight)
            handle(for: \.bottomRight)
            handle(for: \.bottomLeft)
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: Self.spaceName)
    }

    private static let spaceName = "cropOverlay"

    private func handle(for keyPath: WritableKeyPath<Quad, CodablePoint>) -> some View {
        let point = quad[keyPath: keyPath]
        let position = CGPoint(x: CGFloat(point.x) * size.width, y: CGFloat(point.y) * size.height)
        return Circle()
            .fill(theme.accent)
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(theme.paper, lineWidth: 2))
            .position(position)
            .gesture(
                DragGesture(coordinateSpace: .named(Self.spaceName))
                    .onChanged { value in
                        var updated = quad
                        let clampedX = min(max(value.location.x / size.width, 0), 1)
                        let clampedY = min(max(value.location.y / size.height, 0), 1)
                        updated[keyPath: keyPath] = CodablePoint(x: Double(clampedX), y: Double(clampedY))
                        quad = updated
                    }
            )
    }
}
