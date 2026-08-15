import SwiftUI
import UIKit

/// Renders a page's base image with its committed highlight bands and
/// signature overlaid — used read-only by the Document Viewer and as the
/// backdrop layer under the interactive tool overlays in the Edit flow.
/// Sizes itself to the image's own aspect ratio so `GeometryReader`-derived
/// positions line up with `PageRenderer`'s pixel math without letterboxing.
struct PageCompositeView: View {
    let image: UIImage
    var highlightRegions: [HighlightRegion] = []
    var signature: Signature? = nil

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let scale = image.size.width > 0 ? size.width / image.size.width : 1
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)

                ForEach(highlightRegions) { region in
                    let rect = PageRenderer.pixelRect(fromVisionNormalized: region.normalizedBox, imageSize: image.size)
                    Rectangle()
                        .fill(theme.highlight)
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .position(x: rect.midX * scale, y: rect.midY * scale)
                        .blendMode(.multiply)
                }

                if let signature {
                    let sigWidth = CGFloat(signature.width) * size.width
                    let sigHeight = sigWidth * CGFloat(signature.aspectRatio)
                    SignatureStrokesView(signature: signature, colorScheme: colorScheme)
                        .frame(width: sigWidth, height: sigHeight)
                        .rotationEffect(.degrees(signature.rotation))
                        .position(x: CGFloat(signature.x) * size.width + sigWidth / 2, y: CGFloat(signature.y) * size.height + sigHeight / 2)
                }
            }
        }
        .aspectRatio(image.size, contentMode: .fit)
    }
}

/// Draws a signature's normalized [0,1] strokes into whatever frame it's
/// given.
struct SignatureStrokesView: View {
    let signature: Signature
    var colorScheme: ColorScheme = .light

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
            let hint: PageRenderer.SchemeHint = colorScheme == .dark ? .dark : .light
            context.stroke(
                path,
                with: .color(signature.color.uiColor(hint).suColor),
                style: StrokeStyle(lineWidth: max(CGFloat(signature.thickness) * size.width, 0.75), lineCap: .round, lineJoin: .round)
            )
        }
    }
}

private extension UIColor {
    var suColor: Color { Color(self) }
}
