import SwiftUI
import UIKit

/// Draws a signature's normalized [0,1] strokes into whatever frame it's
/// given.
struct SignatureStrokesView: View {
    let signature: Signature

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for stroke in signature.strokes {
                guard let first = stroke.points.first else { continue }
                path.move(to: CGPoint(x: CGFloat(first.x) * size.width, y: CGFloat(first.y) * size.height))
                for p in stroke.points.dropFirst() {
                    path.addLine(to: CGPoint(x: CGFloat(p.x) * size.width, y: CGFloat(p.y) * size.height))
                }
            }
            context.stroke(
                path,
                with: .color(signature.color.color),
                style: StrokeStyle(lineWidth: max(CGFloat(signature.thickness) * size.width, 0.75), lineCap: .round, lineJoin: .round)
            )
        }
    }
}
