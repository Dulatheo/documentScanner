import Foundation

/// Reconstructs page structure for DOCX export (DESIGN_SPEC §5/§9 "Office
/// format export") from OCR bounding-box geometry alone. Neither Vision nor
/// ML Kit report font weight/style, only recognized text plus a position,
/// so this rebuilds what geometry *can* tell us:
///
/// 1. **Columns** (`segments(_:)`): a vertical gutter that (almost) no line
///    crosses splits the page into side-by-side columns — e.g. a bilingual
///    contract with one language per column. Without this, sorting every
///    line top-to-bottom interleaves the two columns line by line.
/// 2. **Rows**: Vision often splits one justified line into several
///    observations at wide word gaps; lines that sit on the same row within
///    a column are joined back together left to right.
/// 3. **Paragraphs** (`paragraphs(_:in:)`): consecutive rows are merged
///    into one paragraph unless something signals a break — a first-line
///    indent, a short previous line, a larger vertical gap, or a list
///    marker — so a wrapped sentence becomes one Word paragraph that
///    reflows, instead of one hard paragraph per scanned line.
///
/// Alignment (left/center/right/justified), a first-line indent and a
/// size-based "heading-like" bold are inferred per paragraph. This is a
/// heuristic on noisy OCR data; it's tuned on real scanned contracts but
/// can misjudge unusual layouts.
enum DocxLineLayout {
    struct Paragraph {
        let text: String
        /// OOXML `w:jc` value: "left", "center", "right" or "both".
        let alignment: String
        let firstLineIndent: Bool
        /// Approximated from line height alone — not real bold detection.
        let bold: Bool
        /// A larger-than-usual vertical gap preceded this paragraph.
        let spaceBefore: Bool
    }

    /// Horizontal extent (normalized page width) of a region's text — the
    /// whole page for full-width flow, or one column.
    struct Bounds {
        let minX: Double
        let maxX: Double
        var width: Double { max(maxX - minX, 0.01) }
        var midX: Double { (minX + maxX) / 2 }
    }

    enum Segment {
        /// Full-width content, in reading order.
        case flow([OCRLine], Bounds)
        /// Side-by-side columns covering the same vertical stretch.
        case columns(left: [OCRLine], Bounds, right: [OCRLine], Bounds)
    }

    // MARK: - Tuning

    /// The gutter is searched for only within this central band of the page.
    private static let gutterSearchRange = 0.25...0.75
    /// Step between candidate gutter positions.
    private static let gutterStep = 0.005
    /// How far (normalized page width) a line may poke past the gutter
    /// before it counts as crossing it — see `findGutter`.
    private static let gutterSlack = 0.035
    /// Each column must hold at least this fraction of the page's lines.
    private static let minColumnShare = 0.2
    /// A column must look like prose, not a narrow table column: at least
    /// this share of its lines span most of the column's width.
    private static let proseLineShare = 0.3
    private static let proseLineWidth = 0.6
    /// A row starting this far (fraction of region width) right of the
    /// region's left edge counts as indented.
    private static let indentFraction = 0.03
    /// A row ending this far (fraction of region width) short of the
    /// region's right edge counts as a paragraph's last line.
    private static let shortLineFraction = 0.12
    /// A gap must exceed the region's median row gap by this factor to
    /// count as a paragraph break.
    private static let paragraphGapFactor = 1.8
    /// A paragraph's rows must be this many times the median row height
    /// to be treated as heading-like (bold).
    private static let boldRatioThreshold = 1.4
    /// Vertical half-window (normalized page height) for `localEdges`.
    private static let localWindow = 0.08
    /// Two lines are on the same row once their vertical extents overlap
    /// by at least this fraction of the shorter one's height.
    private static let rowOverlapFactor = 0.5

    // MARK: - Columns

    static func segments(_ lines: [OCRLine]) -> [Segment] {
        let sorted = lines.sorted { top($0) < top($1) }
        let pageBounds = bounds(of: sorted)
        guard sorted.count >= 6, let gutter = findGutter(sorted) else {
            return sorted.isEmpty ? [] : [.flow(sorted, pageBounds)]
        }

        let spans: (OCRLine) -> Bool = { crosses($0, gutter) }
        let leftAll = sorted.filter { !spans($0) && midX($0) < gutter }
        let rightAll = sorted.filter { !spans($0) && midX($0) >= gutter }
        let leftBounds = bounds(of: leftAll)
        let rightBounds = bounds(of: rightAll)

        var segments: [Segment] = []
        var flow: [OCRLine] = []
        var left: [OCRLine] = []
        var right: [OCRLine] = []

        func flushColumns() {
            guard !left.isEmpty || !right.isEmpty else { return }
            segments.append(.columns(left: left, leftBounds, right: right, rightBounds))
            left = []
            right = []
        }
        func flushFlow() {
            guard !flow.isEmpty else { return }
            segments.append(.flow(flow, pageBounds))
            flow = []
        }

        for line in sorted {
            if spans(line) {
                flushColumns()
                flow.append(line)
            } else {
                flushFlow()
                if midX(line) < gutter { left.append(line) } else { right.append(line) }
            }
        }
        flushColumns()
        flushFlow()
        return segments
    }

    /// Finds an x position in the middle of the page that (almost) no line
    /// crosses, with enough prose-like text on both sides to call it a
    /// two-column layout rather than, say, a table or a centered title.
    ///
    /// A slightly rotated photo makes the columns' edges drift by a percent
    /// or so down the page, so neighboring columns can overlap a little in
    /// x — a line only counts as crossing a candidate gutter when it
    /// extends more than `gutterSlack` past it on *both* sides.
    private static func findGutter(_ lines: [OCRLine]) -> Double? {
        // A few lines (a title, a signature line) may cross the gutter.
        let tolerance = max(1, Int(Double(lines.count) * 0.06))
        let candidates = stride(from: gutterSearchRange.lowerBound, through: gutterSearchRange.upperBound, by: gutterStep)
        let crossings = candidates.map { x in (x, lines.filter { crosses($0, x) }.count) }

        // Longest run of open candidates; ties go to the emptiest run.
        var best: (start: Double, end: Double, cost: Int)?
        var run: (start: Double, end: Double, cost: Int)?
        for (x, count) in crossings + [(2, Int.max)] {
            if count <= tolerance {
                run = run.map { ($0.start, x, $0.cost + count) } ?? (x, x, count)
            } else if let current = run {
                if best == nil
                    || current.end - current.start > best!.end - best!.start + gutterStep / 2
                    || (abs((current.end - current.start) - (best!.end - best!.start)) < gutterStep / 2 && current.cost < best!.cost) {
                    best = current
                }
                run = nil
            }
        }
        guard let best else { return nil }
        let gutter = (best.start + best.end) / 2

        let left = lines.filter { !crosses($0, gutter) && midX($0) < gutter }
        let right = lines.filter { !crosses($0, gutter) && midX($0) >= gutter }
        let minLines = max(3, Int(Double(lines.count) * minColumnShare))
        guard left.count >= minLines, right.count >= minLines,
              looksLikeProse(left), looksLikeProse(right) else { return nil }
        return gutter
    }

    private static func crosses(_ line: OCRLine, _ x: Double) -> Bool {
        minX(line) < x - gutterSlack && maxX(line) > x + gutterSlack
    }

    private static func looksLikeProse(_ lines: [OCRLine]) -> Bool {
        let rows = mergeRows(lines)
        let region = bounds(of: lines)
        let wide = rows.filter { $0.maxX - $0.minX >= region.width * proseLineWidth }.count
        return Double(wide) >= Double(rows.count) * proseLineShare
    }

    // MARK: - Paragraphs

    /// Merges `lines` (one column, or a full-width run) into paragraphs.
    /// `region` is the horizontal extent of the whole column/page the lines
    /// belong to, so a short run (a lone title) still judges its alignment
    /// against the real page edges rather than its own.
    ///
    /// Indent/short-line/alignment checks compare each row against its
    /// *local* text edges (from nearby rows) rather than the region's
    /// overall extent: in a slightly rotated or curved photo the margin
    /// drifts down the page, and a page-wide minimum would make every row
    /// near the bottom look indented.
    static func paragraphs(_ lines: [OCRLine], in region: Bounds) -> [Paragraph] {
        let rows = mergeRows(lines)
        guard !rows.isEmpty else { return [] }
        let edges = rows.map { localEdges(of: $0, among: rows, region: region) }

        let heights = rows.map(\.height).sorted()
        let medianHeight = heights[heights.count / 2]
        var gaps: [Double] = []
        for i in 1..<rows.count {
            gaps.append(max(rows[i].top - rows[i - 1].bottom, 0))
        }
        let medianGap = gaps.isEmpty ? 0 : gaps.sorted()[gaps.count / 2]
        let indentThreshold = max(region.width * indentFraction, 0.008)

        func isIndented(_ i: Int) -> Bool { rows[i].minX - edges[i].minX > indentThreshold }
        func isShort(_ i: Int) -> Bool { edges[i].maxX - rows[i].maxX > edges[i].width * shortLineFraction }
        func isBigGap(_ gap: Double) -> Bool {
            if medianGap > 0 { return gap > max(medianGap * paragraphGapFactor, medianHeight * 0.5) }
            return gap > medianHeight * 0.8
        }

        var groups: [[Int]] = []
        var spaceBefore: [Bool] = []
        for (i, row) in rows.enumerated() {
            guard i > 0 else {
                groups.append([i])
                spaceBefore.append(false)
                continue
            }
            let previous = rows[i - 1]
            let gap = row.top - previous.bottom
            let heightJump = abs(row.height - previous.height) > medianHeight * 0.5
            let breaks = isIndented(i) || isShort(i - 1) || isBigGap(gap)
                || startsWithListMarker(row.text) || heightJump
            if breaks {
                groups.append([i])
                spaceBefore.append(isBigGap(gap))
            } else {
                groups[groups.count - 1].append(i)
            }
        }

        return zip(groups, spaceBefore).map { group, spaceBefore in
            let firstIndex = group[0]
            let first = rows[firstIndex]
            let edge = edges[firstIndex]
            let alignment: String
            if group.count > 1 {
                alignment = "both"
            } else {
                let width = first.maxX - first.minX
                let centerOffset = abs((first.minX + first.maxX) / 2 - edge.midX)
                let leftInset = first.minX - edge.minX
                let rightInset = edge.maxX - first.maxX
                if centerOffset < edge.width * 0.06,
                   width < edge.width * 0.8,
                   leftInset > edge.width * 0.08 {
                    alignment = "center"
                } else if rightInset < edge.width * 0.03, leftInset > edge.width * 0.3 {
                    alignment = "right"
                } else {
                    alignment = "left"
                }
            }
            let averageHeight = group.map { rows[$0].height }.reduce(0, +) / Double(group.count)
            return Paragraph(
                text: joinRows(group.map { rows[$0].text }),
                alignment: alignment,
                firstLineIndent: alignment != "center" && alignment != "right" && isIndented(firstIndex),
                bold: medianHeight > 0 && averageHeight / medianHeight >= boldRatioThreshold,
                spaceBefore: spaceBefore
            )
        }
    }

    /// The text edges around `row`: the second-outermost left/right edge
    /// among rows within `localWindow` vertically (second, so one stray
    /// OCR box poking into the margin doesn't count). Falls back to the
    /// whole region when there are too few neighbors to judge.
    private static func localEdges(of row: Row, among rows: [Row], region: Bounds) -> Bounds {
        let neighbors = rows.filter { abs($0.top - row.top) <= localWindow }
        guard neighbors.count >= 5 else { return region }
        let lefts = neighbors.map(\.minX).sorted()
        let rights = neighbors.map(\.maxX).sorted(by: >)
        return Bounds(minX: lefts[1], maxX: rights[1])
    }

    /// "1.", "1.2.", "2)", "а)", "-", "•" … at the start of a row.
    private static func startsWithListMarker(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, "-–—•·▪●".contains(first) { return true }
        return trimmed.range(of: #"^(\d{1,3}(\.\d{1,3})*[.)]|\p{L}\))\s"#, options: .regularExpression) != nil
    }

    /// Joins wrapped lines with a space, except after a trailing hyphen
    /// (a word or compound split across lines — "мекен-" + "жайында").
    private static func joinRows(_ texts: [String]) -> String {
        var result = ""
        for raw in texts {
            // A column divider rule is sometimes read as a stray "|".
            let text = raw
                .replacingOccurrences(of: #"^[\s,.]*\|\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if result.isEmpty {
                result = text
            } else if result.hasSuffix("-"), result.dropLast().last?.isLetter == true {
                result += text
            } else {
                result += " " + text
            }
        }
        return result
    }

    // MARK: - Rows

    private struct Row {
        var text: String
        var minX: Double
        var maxX: Double
        var top: Double
        var bottom: Double
        var height: Double { bottom - top }
    }

    /// Groups lines that sit side by side with substantially overlapping
    /// vertical extents into one row, ordered left to right; rows come
    /// back top to bottom.
    private static func mergeRows(_ lines: [OCRLine]) -> [Row] {
        let sorted = lines.sorted { top($0) < top($1) }
        var rows: [(row: Row, parts: [OCRLine])] = []
        for line in sorted {
            let lineTop = top(line)
            let lineBottom = bottom(line)
            if var last = rows.last {
                let overlap = min(last.row.bottom, lineBottom) - max(last.row.top, lineTop)
                let minHeight = min(last.row.height, lineBottom - lineTop)
                // Fragments of one row sit side by side; a line that
                // horizontally overlaps a part already in the row is the
                // next line down, however much their boxes overlap.
                let sideBySide = last.parts.allSatisfy { part in
                    min(maxX(part), maxX(line)) - max(minX(part), minX(line)) < 0.01
                }
                if minHeight > 0, overlap > minHeight * rowOverlapFactor, sideBySide {
                    last.parts.append(line)
                    last.row.minX = min(last.row.minX, minX(line))
                    last.row.maxX = max(last.row.maxX, maxX(line))
                    last.row.top = min(last.row.top, lineTop)
                    last.row.bottom = max(last.row.bottom, lineBottom)
                    rows[rows.count - 1] = last
                    continue
                }
            }
            rows.append((Row(text: "", minX: minX(line), maxX: maxX(line), top: lineTop, bottom: lineBottom), [line]))
        }
        return rows.map { entry in
            var row = entry.row
            row.text = entry.parts.sorted { minX($0) < minX($1) }.map(\.text).joined(separator: " ")
            return row
        }
    }

    // MARK: - Geometry (top-down page coordinates)

    // Vision's normalizedBox has a bottom-left origin; these flip it so
    // `top` grows downward the way a reader scans the page.
    private static func top(_ line: OCRLine) -> Double { 1 - (line.normalizedBox.y + line.normalizedBox.height) }
    private static func bottom(_ line: OCRLine) -> Double { 1 - line.normalizedBox.y }
    private static func minX(_ line: OCRLine) -> Double { line.normalizedBox.x }
    private static func maxX(_ line: OCRLine) -> Double { line.normalizedBox.x + line.normalizedBox.width }
    private static func midX(_ line: OCRLine) -> Double { line.normalizedBox.x + line.normalizedBox.width / 2 }

    private static func bounds(of lines: [OCRLine]) -> Bounds {
        guard !lines.isEmpty else { return Bounds(minX: 0, maxX: 1) }
        return Bounds(minX: lines.map(minX).min() ?? 0, maxX: lines.map(maxX).max() ?? 1)
    }
}
