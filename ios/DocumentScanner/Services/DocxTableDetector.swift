import Foundation

/// Detects simple grid-like tables within a page's OCR lines, purely from
/// bounding-box geometry (DESIGN_SPEC §5/§9 "Office format export" table
/// detection). A table row reaches OCR as one of two shapes, and both are
/// handled:
/// - **Same `OCRLine`, several words**: cramped columns close enough
///   together that Vision/ML Kit still grouped them into one line — split
///   by an unusually large gap between two adjacent *words* on that line.
/// - **Separate `OCRLine`s, same row**: a wide-gapped layout (e.g. a
///   two-column glossary/translation table) where each column's cell is
///   far enough from its neighbor that the OCR engine's own line-grouping
///   already treats them as distinct lines — these are found first by
///   `rowBands(in:)`, which groups lines whose vertical extents
///   substantially overlap (i.e. they sit side by side on the same row)
///   before any word-gap logic runs. This is in practice the far more
///   common shape for a real multi-column table, since OCR line-grouping
///   keys off proximity, and table columns are deliberately spaced apart.
///
/// Consecutive rows that split into the same number of cells at matching
/// horizontal positions are grouped into one table; everything else stays
/// a plain paragraph line elsewhere in the export.
///
/// This is a heuristic on noisy OCR data, not real table recognition —
/// there's no ground truth to check it against. It works well on clean,
/// well-spaced tables and can misfire on tight layouts, multi-line cells,
/// or merged cells.
enum DocxTableDetector {
    struct DetectedTable {
        /// Indices into the *sorted* (reading-order) line array this table
        /// consumed — the caller renders everything outside these ranges
        /// as ordinary paragraphs.
        let lineIndices: Range<Int>
        let rows: [[String]]
    }

    private struct Cell {
        let text: String
        let minX: Double
    }

    /// A group of one or more OCR lines that sit on the same table row —
    /// either several separate lines side by side, or (the `lines.count
    /// == 1` case) a single line whose own word gaps may still split it
    /// into more than one cell. `lineIndices` is these lines' contiguous
    /// position in the original sorted array.
    private struct RowBand {
        let lineIndices: Range<Int>
        let lines: [OCRLine]
    }

    /// A gap must be at least this many times the page's typical
    /// inter-word gap to count as a column break.
    private static let gapFactor: Double = 3
    /// ...and at least this wide outright, in normalized page-width
    /// units, so a page with almost no word-spacing data to learn a
    /// typical gap from doesn't flag ordinary word spacing.
    private static let minGapWidth: Double = 0.02
    /// How far a cell's left edge may drift between rows and still count
    /// as "the same column."
    private static let columnAlignmentTolerance: Double = 0.04
    /// Minimum rows for a run of same-shaped lines to count as a real
    /// table rather than a coincidental one-off multi-column line.
    private static let minTableRows = 2
    /// Two lines count as "the same row" once their vertical extents
    /// overlap by at least this fraction of the shorter line's height —
    /// side-by-side cells on one row nearly coincide vertically, while
    /// lines stacked within a wrapped multi-line cell (or an unrelated
    /// line below) don't overlap vertically at all.
    private static let rowOverlapFactor: Double = 0.5

    /// `sortedLines` must already be in top-to-bottom reading order (see
    /// `DocxLineLayout.analyze`'s sort, which callers should apply first).
    static func detect(in sortedLines: [OCRLine]) -> [DetectedTable] {
        guard sortedLines.count >= minTableRows else { return [] }

        let bands = rowBands(in: sortedLines)

        // Only used for the same-line word-gap fallback below — computed
        // once, page-wide, same as before.
        let allGaps = sortedLines.flatMap(gaps)
        let medianGap = allGaps.isEmpty ? 0 : allGaps.sorted()[allGaps.count / 2]
        let threshold = max(medianGap * gapFactor, minGapWidth)

        let cellsPerBand: [[Cell]] = bands.map { band in
            if band.lines.count >= 2 {
                // Already separate lines side by side — each *is* a cell,
                // no word-gap analysis needed.
                return band.lines.sorted { $0.normalizedBox.x < $1.normalizedBox.x }
                    .map { Cell(text: $0.text, minX: $0.normalizedBox.x) }
            } else {
                return cells(in: band.lines[0], threshold: threshold)
            }
        }

        var tables: [DetectedTable] = []
        var index = 0
        while index < cellsPerBand.count {
            guard cellsPerBand[index].count >= 2 else {
                index += 1
                continue
            }
            var end = index + 1
            while end < cellsPerBand.count,
                  cellsPerBand[end].count == cellsPerBand[index].count,
                  columnsAlign(cellsPerBand[index], cellsPerBand[end]) {
                end += 1
            }
            if end - index >= minTableRows {
                let rows = cellsPerBand[index..<end].map { row in row.map(\.text) }
                let lineIndices = bands[index].lineIndices.lowerBound..<bands[end - 1].lineIndices.upperBound
                tables.append(DetectedTable(lineIndices: lineIndices, rows: rows))
            }
            index = end
        }
        return tables
    }

    /// Greedily groups `sortedLines` into row bands: starting a new band at
    /// each line whose vertical extent doesn't sufficiently overlap the
    /// current band's combined extent so far. Since the input is already
    /// top-to-bottom sorted, lines belonging to the same row are expected
    /// to be adjacent, so one linear pass suffices.
    private static func rowBands(in sortedLines: [OCRLine]) -> [RowBand] {
        var bands: [RowBand] = []
        var i = 0
        while i < sortedLines.count {
            var bandLow = sortedLines[i].normalizedBox.y
            var bandHigh = sortedLines[i].normalizedBox.y + sortedLines[i].normalizedBox.height
            var bandLines = [sortedLines[i]]
            var j = i + 1
            while j < sortedLines.count {
                let line = sortedLines[j]
                let lineLow = line.normalizedBox.y
                let lineHigh = line.normalizedBox.y + line.normalizedBox.height
                let overlap = min(bandHigh, lineHigh) - max(bandLow, lineLow)
                let minHeight = min(bandHigh - bandLow, lineHigh - lineLow)
                guard minHeight > 0, overlap > minHeight * rowOverlapFactor else { break }
                bandLines.append(line)
                bandLow = min(bandLow, lineLow)
                bandHigh = max(bandHigh, lineHigh)
                j += 1
            }
            bands.append(RowBand(lineIndices: i..<j, lines: bandLines))
            i = j
        }
        return bands
    }

    private static func gaps(in line: OCRLine) -> [Double] {
        guard line.words.count >= 2 else { return [] }
        let sorted = line.words.sorted { $0.normalizedBox.x < $1.normalizedBox.x }
        var result: [Double] = []
        for i in 1..<sorted.count {
            let previous = sorted[i - 1].normalizedBox
            let gap = sorted[i].normalizedBox.x - (previous.x + previous.width)
            if gap > 0 { result.append(gap) }
        }
        return result
    }

    private static func cells(in line: OCRLine, threshold: Double) -> [Cell] {
        guard line.words.count >= 2 else {
            return [Cell(text: line.text, minX: line.normalizedBox.x)]
        }
        let sorted = line.words.sorted { $0.normalizedBox.x < $1.normalizedBox.x }
        var result: [Cell] = []
        var currentWords: [OCRWord] = [sorted[0]]
        for i in 1..<sorted.count {
            let lastBox = currentWords[currentWords.count - 1].normalizedBox
            let gap = sorted[i].normalizedBox.x - (lastBox.x + lastBox.width)
            if gap > threshold {
                result.append(makeCell(from: currentWords))
                currentWords = [sorted[i]]
            } else {
                currentWords.append(sorted[i])
            }
        }
        result.append(makeCell(from: currentWords))
        return result
    }

    private static func makeCell(from words: [OCRWord]) -> Cell {
        let text = words.map(\.text).joined(separator: " ")
        let minX = words.map(\.normalizedBox.x).min() ?? 0
        return Cell(text: text, minX: minX)
    }

    private static func columnsAlign(_ a: [Cell], _ b: [Cell]) -> Bool {
        guard a.count == b.count else { return false }
        for (cellA, cellB) in zip(a, b) where abs(cellA.minX - cellB.minX) > columnAlignmentTolerance {
            return false
        }
        return true
    }
}
