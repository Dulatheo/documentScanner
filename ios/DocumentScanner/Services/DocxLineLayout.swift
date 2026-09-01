import Foundation

/// Approximates paragraph-level layout for DOCX export (DESIGN_SPEC §5/§9
/// "Office format export") from OCR bounding-box geometry alone — neither
/// Vision nor ML Kit report font weight/style/underline, only recognized
/// text plus a position, so this reconstructs what geometry *can* tell us
/// (alignment, relative emphasis, paragraph breaks) and nothing more:
/// bold/italic/underline detection would need actual pixel-level image
/// analysis (stroke thickness, underline strokes), a separate and riskier
/// "Advanced OCR"-sized feature, not a refinement of this one.
enum DocxLineLayout {
    struct Line {
        let text: String
        /// OOXML `w:jc` value: "left", "center", or "right".
        let alignment: String
        /// `w:sz`/`w:szCs` value — font size in half-points.
        let halfPointSize: Int
        /// Approximated from size alone (see type-level doc) — lines
        /// noticeably larger than the page's median line height are
        /// treated as emphasized/heading-like, not a real bold detection.
        let bold: Bool
        /// True when the vertical gap before this line is notably larger
        /// than the page's typical line-to-line gap, suggesting a
        /// paragraph break rather than a mere line wrap.
        let extraSpaceBefore: Bool
    }

    /// Base body-text size (11pt, a common Word default) that the relative
    /// scaling below is anchored to.
    private static let baseFontSizePt: Double = 11
    private static let minFontSizePt: Double = 8
    private static let maxFontSizePt: Double = 36
    /// A line's box height must exceed the page's median by this factor to
    /// be treated as emphasized/heading-like.
    private static let boldRatioThreshold: Double = 1.4
    /// Fraction of the page width within which a box edge counts as
    /// "at the margin" (OCR boxes are never pixel-perfect).
    private static let marginTolerance: Double = 0.02
    /// How far a line's horizontal center may sit from the page's center
    /// and still count as centered.
    private static let centerTolerance: Double = 0.05
    /// A centered line must be no wider than this fraction of the page's
    /// content width — otherwise ordinary full-width body lines that
    /// happen to look symmetric would be misclassified as centered.
    private static let centeredMaxWidthFraction: Double = 0.85
    /// A gap must exceed the page's median line gap by this factor to
    /// count as a paragraph break rather than ordinary line spacing.
    private static let paragraphGapFactor: Double = 1.6

    static func analyze(_ lines: [OCRLine]) -> [Line] {
        guard !lines.isEmpty else { return [] }

        // Vision's normalizedBox uses a bottom-left origin (y increases
        // upward), so the top-most line on the page has the largest
        // (y + height) — sort descending by that to get reading order.
        let sorted = lines.sorted {
            ($0.normalizedBox.y + $0.normalizedBox.height) > ($1.normalizedBox.y + $1.normalizedBox.height)
        }

        let pageLeftMargin = sorted.map(\.normalizedBox.x).min() ?? 0
        let pageRightEdge = sorted.map { $0.normalizedBox.x + $0.normalizedBox.width }.max() ?? 1
        let contentWidth = max(pageRightEdge - pageLeftMargin, 0.01)

        let sortedHeights = sorted.map(\.normalizedBox.height).sorted()
        let medianHeight = sortedHeights[sortedHeights.count / 2]

        func topDownTop(_ box: CGRectCodable) -> Double { 1 - (box.y + box.height) }
        func topDownBottom(_ box: CGRectCodable) -> Double { 1 - box.y }

        var gaps: [Double] = []
        for i in 1..<sorted.count {
            gaps.append(max(topDownTop(sorted[i].normalizedBox) - topDownBottom(sorted[i - 1].normalizedBox), 0))
        }
        let medianGap = gaps.isEmpty ? 0 : gaps.sorted()[gaps.count / 2]

        return sorted.enumerated().map { index, line in
            let box = line.normalizedBox
            let minX = box.x
            let maxX = box.x + box.width
            let midX = (minX + maxX) / 2
            let lineWidth = box.width

            let nearLeft = (minX - pageLeftMargin) < marginTolerance
            let nearRight = (pageRightEdge - maxX) < marginTolerance
            let centerOffset = abs(midX - 0.5)

            let alignment: String
            if nearLeft && nearRight {
                alignment = "left"
            } else if centerOffset < centerTolerance && lineWidth < contentWidth * centeredMaxWidthFraction {
                alignment = "center"
            } else if nearRight && !nearLeft {
                alignment = "right"
            } else {
                alignment = "left"
            }

            let ratio = medianHeight > 0 ? box.height / medianHeight : 1
            let fontSizePt = min(max(baseFontSizePt * ratio, minFontSizePt), maxFontSizePt)
            let halfPointSize = Int((fontSizePt * 2).rounded())
            let bold = ratio >= boldRatioThreshold

            var extraSpaceBefore = false
            if index > 0 {
                let gap = max(topDownTop(box) - topDownBottom(sorted[index - 1].normalizedBox), 0)
                extraSpaceBefore = medianGap > 0 && gap > medianGap * paragraphGapFactor
            }

            return Line(
                text: line.text,
                alignment: alignment,
                halfPointSize: halfPointSize,
                bold: bold,
                extraSpaceBefore: extraSpaceBefore
            )
        }
    }
}
