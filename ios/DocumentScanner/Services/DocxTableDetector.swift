import Foundation

/// Detects simple grid-like tables within a page's OCR lines, purely from
/// word-level bounding-box gaps (DESIGN_SPEC §5/§9 "Office format export"
/// table detection) — a table row is usually recognized by Vision as one
/// line containing several words, so an unusually large gap between two
/// adjacent words on the same line is treated as a column break.
/// Consecutive lines that split into the same number of cells at matching
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

    /// `sortedLines` must already be in top-to-bottom reading order (see
    /// `DocxLineLayout.analyze`'s sort, which callers should apply first).
    static func detect(in sortedLines: [OCRLine]) -> [DetectedTable] {
        guard sortedLines.count >= minTableRows else { return [] }

        let allGaps = sortedLines.flatMap(gaps)
        let medianGap = allGaps.isEmpty ? 0 : allGaps.sorted()[allGaps.count / 2]
        let threshold = max(medianGap * gapFactor, minGapWidth)

        let cellsPerLine = sortedLines.map { cells(in: $0, threshold: threshold) }

        var tables: [DetectedTable] = []
        var index = 0
        while index < cellsPerLine.count {
            guard cellsPerLine[index].count >= 2 else {
                index += 1
                continue
            }
            var end = index + 1
            while end < cellsPerLine.count,
                  cellsPerLine[end].count == cellsPerLine[index].count,
                  columnsAlign(cellsPerLine[index], cellsPerLine[end]) {
                end += 1
            }
            if end - index >= minTableRows {
                let rows = cellsPerLine[index..<end].map { row in row.map(\.text) }
                tables.append(DetectedTable(lineIndices: index..<end, rows: rows))
            }
            index = end
        }
        return tables
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
