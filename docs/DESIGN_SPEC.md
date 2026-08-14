# Document Scanner — Design Spec

Source: Claude Design project `Document Scanner.dc.html` (imported 2026-08-13).
Raw reference files are kept in `docs/design/` for context; this document is
the authoritative, implementation-ready spec both native apps are built from.

## 1. Product

A local-first document scanner: capture paper documents with the camera,
turn them into clean multi-page scans, lightly edit them (crop, highlight,
OCR, sign), keep them in a library with per-document comments, and export/
share as PDF or JPG. No backend — everything lives on-device.

## 2. Repository shape

Single monorepo (see root README for rationale):

```
/docs/                shared design reference + this spec
/ios/                 SwiftUI app (Xcode project)
/android/             Kotlin + Jetpack Compose app (Gradle project)
```

## 3. Visual language

### 3.1 Color tokens

| Token | Light | Dark |
|---|---|---|
| `bg` | `#F6F4F1` | `#121110` |
| `surface` | `#FFFFFF` | `#1B1A18` |
| `ink` (primary text) | `#171614` | `#F2F0EC` |
| `ink2` (secondary text) | `rgba(23,22,20,.60)` | `rgba(242,240,236,.60)` |
| `ink3` (tertiary text) | `rgba(23,22,20,.36)` | `rgba(242,240,236,.32)` |
| `line` (hairline border) | `rgba(23,22,20,.10)` | `rgba(242,240,236,.12)` |
| `accent` | `#A4552E` (clay) | `#DE8E60` |
| `accentSoft` (accent fill) | `rgba(164,85,46,.10)` | `rgba(222,142,96,.15)` |
| `paper` (page background) | `#FFFDFB` | `#242120` |
| `paperLine` (simulated text line) | `rgba(23,22,20,.13)` | `rgba(242,240,236,.17)` |
| `highlight` | `rgba(226,178,62,.55)` | `rgba(226,178,62,.32)` |

Card/paper shadow: `0 1px 2px rgba(23,22,20,.06), 0 10px 28px rgba(23,22,20,.07)`
(dark: `0 1px 2px rgba(0,0,0,.5), 0 10px 28px rgba(0,0,0,.35)`).

Both apps must support light and dark mode, following the OS setting by
default (`prefers-color-scheme` equivalent — `@Environment(\.colorScheme)`
on iOS, `isSystemInDarkTheme()` on Android).

### 3.2 Typography

- iOS: system font (SF Pro / SF Pro Display via `-apple-system`), matching
  Apple's Human Interface Guidelines type scale.
- Android: **Roboto**, matching Material 3 default type scale.
- Screen title (e.g. "Documents"): 28–30sp/pt, weight 600, tight tracking.
- Body/labels: 13–15sp/pt, weight 400–500.

### 3.3 Signature colors

Ink (= `ink` token), Blue `#2C5EA8`, Clay `#A4552E`, Green `#2F6B4F`.

### 3.4 App icon

Rounded-square tile, background `#A4552E` (clay). Centered glyph: a
document/page shape in `#F6F4F1` (paper) with a folded top-right corner in
`#D9D4CD`, two short horizontal accent-colored (`#A4552E`) lines representing
text, and four paper-colored (`#F6F4F1`) corner-bracket strokes (viewfinder
scan corners) framing the whole glyph — i.e. the page sits "inside a scan
frame." Export at all required platform sizes (iOS: 1024 App Store + the
standard icon set; Android: adaptive icon foreground/background layers at
standard mipmap densities).

## 4. Screens & flows

State machine: `home → camera → edit → (export sheet → share) → home`, with
a parallel `home → doc viewer (existing document) → (comment | export sheet
→ share) → home/doc viewer`.

### 4.1 Home ("Documents")

- Large title "Documents" + subtitle: document count (e.g. "3 documents")
  or "Nothing saved yet" when empty.
- Search affordance (circular icon button, top-right) — only shown once at
  least one document exists. MVP: local filter-as-you-type over document
  names.
- **Grid of document cards**, 2 columns. Each card: a stylized paper preview
  (rounded rect, `paper` background, a few simulated text-line bars) showing
  a real thumbnail of the document's first page once available, a page-count
  badge (`accentSoft` pill, bottom-right, e.g. "3 pgs"), the document name
  below the card, and the date below that. Tapping opens the Document
  Viewer.
- **Empty state**: centered icon tile (viewfinder/scan-corners glyph),
  "No documents yet", helper copy ("Scanned documents are saved here. Point
  your camera at a page to begin."), and a primary "Scan a document" button.
- **Floating scan button**: 64pt/dp circle, `accent` background, camera/
  scan-corners icon, pinned bottom-center over a bottom fade gradient.
  Always visible on Home (in addition to the empty-state CTA). Opens Camera.

### 4.2 Camera (capture)

Full-screen camera capture used to build up a multi-page document before
committing it to the library.

- Top instruction pill: "Position the document in the frame" over the live
  preview.
- Viewfinder guide: rounded-rect frame with 4 corner brackets. A subtle
  animated horizontal sweep line while idle communicates "scanning".
- Bottom control bar (dark scrim): **Cancel** (left, text button, discards
  captures and returns Home), **shutter** (center, large white circle),
  **gallery/photo picker** (right, imports an existing photo as a page).
- Each shutter tap captures a page and shows a **per-shot review step**
  (full-screen captured photo, bottom bar with **Retake** — secondary/
  outlined, bottom-left — and **Done** — primary/filled `accent`, bottom-
  right/prominent). Tapping **Done** commits the page to the capture stack
  (a thumbnail "flies" into the stack indicator with a brief shutter-flash
  and the count badge increments) and returns to the live camera for the
  next page; tapping **Retake** discards the shot and returns to the live
  camera to reshoot the same page.
- Once `captures > 0`, a **"Done · N pages"** pill appears (and the stack
  thumbnail itself is tappable) to finish the whole capture session and
  proceed to the page editor for the first captured page.
- Platform capture implementation (**this diverges by platform** — see
  below):
  - **Android**: uses the platform's built-in document-scanning capture UI
    so edge detection / auto-crop / multi-page flow is production quality
    rather than hand-rolled — ML Kit **Document Scanner API**
    (`GmsDocumentScanning`), which provides its own capture → auto-crop →
    multi-page → review flow. This replaces the mock's custom shutter/
    gallery/stack chrome with the platform's native equivalent; behaviorally
    it satisfies the same user story (frame a page, capture multiple pages,
    review, continue). Android's per-shot review step is whatever
    `GmsDocumentScanning` itself presents (not independently customizable,
    same rationale as iOS's original VisionKit approach below).
  - **iOS**: originally used `VNDocumentCameraViewController` (VisionKit)
    for the same reason as Android. That was replaced with a **fully custom
    AVFoundation camera** (live `AVCaptureSession` preview, `AVCapturePhotoOutput`
    for the shutter, a hand-built per-shot review screen) after user testing
    on-device showed VisionKit's own per-shot review screen — a sealed,
    non-customizable system UI — put **Retake** in the prominent position
    and the "keep this page" action in a small, easy-to-miss back-chevron,
    which is confusing and is exactly the "Retake secondary / Done primary"
    layout above. Apple's public API for `VNDocumentCameraViewController`
    doesn't expose any way to relabel, reposition, or intercept that screen,
    so matching the desired UX required dropping VisionKit and hand-rolling
    capture. The trade-off: iOS loses VisionKit's built-in real-time edge
    detection / auto-crop; iOS relies on the existing manual **Crop** tool in
    the Edit flow (§4.3) for perspective correction instead of an
    auto-detected quad at capture time.

### 4.3 Edit (per-page editor)

Reached after capture finishes, or when re-editing a page from an existing
document. Paginated — "Page X of Y" in the top bar.

- Top bar: **Cancel** (discard back to camera/prior state), page label,
  **Save** (commits the document and opens the Export sheet with
  `pendingSave = true`).
- Center: the page rendered on a `paper` card (drop shadow, hairline
  border).
- **Tool bar** (4 equal-width buttons, bottom): **Crop**, **Highlight**,
  **Text** (OCR), **Sign**. Active tool is visually selected
  (`accentSoft` background + `accent` icon/label). A one-line contextual
  hint above the tool bar changes per active tool ("Drag the corners to fit
  the page" / "Tap a line of text to highlight it" / "Text recognition" /
  "Draw your signature").
  - **Crop**: adjustable quad/rect overlay with draggable corner handles;
    commits a perspective-corrected crop of the page image. (If using
    VisionKit/ML Kit capture, an initial auto-crop is already applied — this
    tool lets the user refine it.)
  - **Highlight**: on-page OCR text regions become tappable; tapping toggles
    a translucent `highlight` color band over that line/region.
  - **Text (OCR)**: runs on-device text recognition (`Vision`/`VNRecognizeTextRequest`
    on iOS, ML Kit **Text Recognition v2** on Android) and opens a bottom
    sheet: "Reading page…" while busy, then the recognized text in a
    scrollable monospace-ish block with **Copy text** and **Keep as
    searchable** (embeds the OCR text layer into the page/PDF) actions.
  - **Sign**: opens a full-screen, landscape signature pad — "Sign with your
    finger", a canvas with a baseline guide, a color picker (Ink/Blue/Clay/
    Green), a thickness slider, **Clear**, **Cancel**, **Done**. On Done,
    drops into a placement mode over the page: the signature can be dragged
    and resized (corner handle) before **Done** commits it at that
    position/size. **Redraw** returns to the drawing canvas.
- Saving moves the (new or edited) document into the library, shows a toast
  ("Saved to Documents"), and opens the Export sheet.

### 4.4 Document viewer

- Top bar: **Documents** back button (with chevron, `accent` color) / the
  document's name, centered.
- Body: the page(s) rendered as `paper` cards (with any committed
  highlights/signature baked in), scrollable for multi-page documents.
  Below the pages, a **Comments** section (label "COMMENTS", each comment a
  card with the note text and "You · <relative time> · page N" meta).
- Bottom bar: **Comment** and **Export**, two equal-width icon+label
  buttons.
- **Comment sheet**: bottom sheet, title "Add comment", a multiline text
  field (placeholder "Note for this page"), **Post** button (disabled/no-op
  on empty text), **Cancel** to dismiss.

### 4.5 Export sheet

Bottom sheet, title "Export document", subtitle varies ("Saved to
Documents · choose a format to share" right after saving a new scan, or
"Choose a format to share" when exporting an existing document). Two
options:

- **PDF document** — "Searchable text, all pages" (multi-page PDF; embeds
  any OCR'd text as an invisible text layer when available).
- **JPG images** — "One image per page".

Dismiss button: "Close" (post-save flow) or "Cancel" (existing-doc flow).

### 4.6 Share

Selecting a format in the Export sheet should hand the generated file
(PDF or one/more JPGs) to the **platform's native share surface** —
`UIActivityViewController` on iOS, an `ACTION_SEND`/`ACTION_SEND_MULTIPLE`
chooser `Intent` on Android — rather than reimplementing a custom share
sheet. This is a deliberate, idiomatic simplification vs. the mock's custom
share-sheet mockup: native share gives real access to every installed app,
Files/Save-to-Files, printing (`UIPrintInteractionController` /
Android `PrintManager` — offer this as one of the native share/print
options), and copy, which is exactly the intent behind the mock's
"Messages / Mail / Notes / Files … Copy / Save to Files / Print" list.
After the OS share sheet is dismissed, finish the flow: return to the
document (or Home, if this followed a fresh save) and clear pending-save
state.

### 4.7 Toast

Transient, centered, low on screen (above the tab/tool bar), dark pill,
white text, auto-dismiss ~1.6s. Used for confirmations: "Saved to
Documents", "Signature added", "Copied", "Added from gallery", etc.

## 5. Data model

```
Document
  id: UUID
  name: String                 // default "Scan N"; user-renamable (nice-to-have)
  createdAt: Date
  pages: [Page]                // ordered
  comments: [Comment]

Page
  id: UUID
  order: Int
  imagePath: String            // cropped page image on disk
  originalImagePath: String?   // pre-crop capture, kept for re-crop
  ocrText: String?             // null until OCR has been run
  highlightedLineIndices/Regions: [...]   // OCR line regions marked highlighted
  signature: Signature?

Signature
  strokes: [[Point]]           // per-stroke point lists, for redraw/placement
  color: Color
  thickness: Double
  x, y, width: Double           // placement on the page, normalized to page size

Comment
  id: UUID
  text: String
  authorLabel: String           // "You" (no accounts/backend in MVP)
  createdAt: Date
  pageIndex: Int?
```

Persistence: **SwiftData** on iOS, **Room** on Android. Page images are
stored as files in the app's local documents/sandbox directory, referenced
by path/UUID from the database — not stored as blobs.

## 6. Platform implementation notes

- **iOS**: SwiftUI, iOS 17+ target. SwiftData for persistence. VisionKit
  (`VNDocumentCameraViewController`) for capture. Vision framework
  (`VNRecognizeTextRequest`) for OCR. PDFKit (`PDFDocument`/`PDFPage`, with
  a `PDFTextLayer`/annotation for searchable text) for PDF export.
  `UIActivityViewController` (wrapped via `UIViewControllerRepresentable`)
  for share. Custom `Canvas`/`Path`-based drawing view for the signature pad.
- **Android**: Kotlin + Jetpack Compose, Material 3. Room for persistence.
  ML Kit Document Scanner (`GmsDocumentScanning`) for capture. ML Kit Text
  Recognition v2 for OCR. `PdfDocument` (or a small PDF library) for PDF
  export with an embedded text layer. `Intent.ACTION_SEND`/chooser for
  share. Custom `Canvas`-based drawing surface (pointer input) for the
  signature pad.
- Both apps implement the same navigation/state machine (§4) and the same
  color tokens (§3.1), each in its platform-idiomatic way (SwiftUI
  environment values / Compose `MaterialTheme` color scheme) so the two
  apps read as the same product.

## 7. Deliberate simplifications vs. the interactive mock

The `.dc.html` file is a clickable prototype built on a small custom
UI-templating runtime (`support.js`), not a real app — it exists to pin down
layout, copy, and interaction sequencing. Two places where the native apps
should do *more* than the mock, not less:

1. **Capture**: the mock's camera screen is a static art-directed frame.
   Android uses the OS's real document-scanning capture (ML Kit) for genuine
   edge detection and multi-page capture. iOS originally did the same with
   VisionKit, but now uses a custom AVFoundation camera instead — see §4.2
   for why — so it implements the mock's live-preview/shutter/stack chrome
   directly rather than delegating to a system scanner, and doesn't get
   auto edge-detection at capture time (the manual Crop tool in §4.3 covers
   that instead).
2. **Share**: the mock's share sheet is a hand-drawn list of four apps; the
   real apps hand off to the OS's native share surface, which is strictly
   more capable and is what users expect on both platforms.

Everything else in §4 — screens, copy, tool set, sheet behavior, toasts —
should be matched closely.
