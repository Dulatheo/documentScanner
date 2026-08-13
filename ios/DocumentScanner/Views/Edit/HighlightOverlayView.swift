import SwiftUI

/// Tappable OCR line regions for the Highlight tool (DESIGN_SPEC §4.3):
/// tapping a line toggles a translucent highlight band over it.
struct HighlightOverlayView: View {
    let lines: [OCRLine]
    let highlightedIDs: Set<UUID>
    let imageSize: CGSize
    let size: CGSize
    let onTap: (OCRLine) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        let scale = imageSize.width > 0 ? size.width / imageSize.width : 1
        ZStack(alignment: .topLeading) {
            ForEach(lines) { line in
                let rect = PageRenderer.pixelRect(fromVisionNormalized: line.normalizedBox, imageSize: imageSize)
                let isOn = highlightedIDs.contains(line.id)
                Rectangle()
                    .fill(isOn ? theme.highlight : Color.black.opacity(0.001))
                    .overlay(
                        Rectangle().stroke(isOn ? theme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .position(x: rect.midX * scale, y: rect.midY * scale)
                    .blendMode(isOn ? .multiply : .normal)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(line) }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
