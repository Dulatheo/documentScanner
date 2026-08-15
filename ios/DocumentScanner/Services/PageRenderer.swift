import UIKit

/// Composites highlight bands and a placed signature on top of a page's
/// base (cropped) image. Used by the live editor/viewer to draw the
/// overlay in SwiftUI *and* by export to bake a single flattened raster —
/// this is the one place that owns the highlight/signature coordinate math
/// so the two stay pixel-identical.
enum PageRenderer {
    static let highlightColor = UIColor(red: 226 / 255, green: 178 / 255, blue: 62 / 255, alpha: 0.55)

    /// Converts a Vision-convention normalized rect (origin bottom-left) to
    /// UIKit-convention pixel rect (origin top-left) for `imageSize`.
    static func pixelRect(fromVisionNormalized box: CGRectCodable, imageSize: CGSize) -> CGRect {
        let rect = box.cgRect
        let x = rect.origin.x * imageSize.width
        let width = rect.size.width * imageSize.width
        let height = rect.size.height * imageSize.height
        let y = (1 - rect.origin.y - rect.size.height) * imageSize.height
        // Pad the tight OCR box slightly so the highlight reads as a band
        // under/around the text rather than a hairline.
        let padY = height * 0.35
        return CGRect(x: x, y: y - padY, width: width, height: height + padY * 2)
    }

    /// Draws a signature's strokes into a `size`-sized image using the
    /// signature's own normalized [0,1] stroke coordinates.
    static func renderSignatureImage(_ signature: Signature, size: CGSize, scheme: SchemeHint) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.setStrokeColor(signature.color.uiColor(scheme).cgColor)
            // `thickness` is stored normalized (fraction of the signature's
            // own drawing-canvas width) so strokes stay proportional whether
            // rendered tiny on a page thumbnail or full-size when placing.
            cg.setLineWidth(max(CGFloat(signature.thickness) * size.width, 0.75))
            for stroke in signature.strokes {
                guard let first = stroke.points.first else { continue }
                cg.beginPath()
                cg.move(to: CGPoint(x: CGFloat(first.x) * size.width, y: CGFloat(first.y) * size.height))
                for p in stroke.points.dropFirst() {
                    cg.addLine(to: CGPoint(x: CGFloat(p.x) * size.width, y: CGFloat(p.y) * size.height))
                }
                cg.strokePath()
            }
        }
    }

    /// Bakes highlight bands + the placed signature onto `base`, returning a
    /// single flattened image suitable for the document viewer, thumbnails,
    /// and JPG/PDF export.
    static func flatten(
        base: UIImage,
        highlightRegions: [HighlightRegion],
        signature: Signature?,
        scheme: SchemeHint = .light
    ) -> UIImage {
        let size = base.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            base.draw(in: CGRect(origin: .zero, size: size))

            let cg = ctx.cgContext
            cg.setBlendMode(.multiply)
            cg.setFillColor(highlightColor.cgColor)
            for region in highlightRegions {
                let rect = pixelRect(fromVisionNormalized: region.normalizedBox, imageSize: size)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: 2)
                path.fill()
            }
            cg.setBlendMode(.normal)

            if let signature {
                let sigWidth = CGFloat(signature.width) * size.width
                let sigHeight = sigWidth * CGFloat(signature.aspectRatio)
                let sigImage = renderSignatureImage(
                    signature,
                    size: CGSize(width: sigWidth, height: sigHeight),
                    scheme: scheme
                )
                let originX = CGFloat(signature.x) * size.width
                let originY = CGFloat(signature.y) * size.height
                let sigRect = CGRect(x: originX, y: originY, width: sigWidth, height: sigHeight)

                if signature.rotation == 0 {
                    sigImage.draw(in: sigRect)
                } else {
                    // Rotate around the signature's own center to match
                    // SwiftUI's `.rotationEffect(anchor: .center)` used
                    // everywhere else this signature is drawn (placement,
                    // the Edit/DocumentViewer composite views). This
                    // context is already in UIKit's flipped (origin
                    // top-left, y-down) space like every other
                    // `UIGraphicsImageRenderer` context, so a positive
                    // angle here is clockwise on screen, same as
                    // `.rotationEffect`'s convention.
                    cg.saveGState()
                    let center = CGPoint(x: sigRect.midX, y: sigRect.midY)
                    cg.translateBy(x: center.x, y: center.y)
                    cg.rotate(by: CGFloat(signature.rotation) * .pi / 180)
                    cg.translateBy(x: -center.x, y: -center.y)
                    sigImage.draw(in: sigRect)
                    cg.restoreGState()
                }
            }
        }
    }

    enum SchemeHint {
        case light, dark
    }
}

extension Theme.SignatureColor {
    func uiColor(_ scheme: PageRenderer.SchemeHint) -> UIColor {
        switch self {
        case .ink:
            return scheme == .dark ? UIColor(hex: 0xF2F0EC) : UIColor(hex: 0x171614)
        case .blue:
            return UIColor(hex: 0x2C5EA8)
        case .clay:
            return UIColor(hex: 0xA4552E)
        case .green:
            return UIColor(hex: 0x2F6B4F)
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
