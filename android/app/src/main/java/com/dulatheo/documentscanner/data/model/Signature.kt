package com.dulatheo.documentscanner.data.model

/** A single point in a signature stroke, in the signature canvas's own
 * (unscaled) coordinate space — see [Signature.strokes]. */
data class SigPoint(val x: Float, val y: Float)

/** One continuous finger-drag while drawing a signature. */
data class SignatureStroke(
    val points: List<SigPoint>,
    val colorHex: String,
    val widthPx: Float,
)

/**
 * A signature captured on the drawing pad and placed on a page.
 *
 * [strokes] are stored in the drawing pad's own coordinate space (see
 * [canvasWidth]/[canvasHeight]) so the signature can be redrawn crisply at
 * any placement size. [x]/[y]/[width]/[height] describe where it sits on the
 * page, normalized to the page image's dimensions (0f..1f) so placement
 * survives page image size differences.
 */
data class Signature(
    val strokes: List<SignatureStroke>,
    val colorHex: String,
    val thickness: Float,
    val canvasWidth: Float,
    val canvasHeight: Float,
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
    /** Rotation around the signature's own center, in degrees (Compose's
     * `Modifier.rotate`/Android `Canvas.rotate` convention: positive =
     * clockwise). Defaults to 0 so documents saved before this field
     * existed still decode correctly (see [com.dulatheo.documentscanner
     * .util.JsonCodec.decodeSignature]). */
    val rotation: Float = 0f,
)

/** One recognized word within an [OcrLine], used only for DOCX table
 * detection (DESIGN_SPEC §5/§9) — an unusually large horizontal gap
 * between two adjacent words on the same line suggests a table column
 * break, which line-level boxes alone can't reveal. */
data class OcrWord(
    val text: String,
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
)

/** A single OCR'd line of text on a page, with its bounding box normalized
 * to the page image's dimensions (0f..1f), and whether the user has toggled
 * a highlight over it. [words] is empty for lines recognized before it was
 * added (see [com.dulatheo.documentscanner.util.JsonCodec.decodeOcrLines]). */
data class OcrLine(
    val text: String,
    val left: Float,
    val top: Float,
    val right: Float,
    val bottom: Float,
    val highlighted: Boolean = false,
    val words: List<OcrWord> = emptyList(),
)
