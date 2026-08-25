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
  or "Nothing saved yet" when empty. No search affordance — removed after
  user feedback that it wasn't earning its place on a screen this simple.
- **Grid of document cards**, 2 columns, **fixed 3:4 aspect ratio
  regardless of the page's own proportions** — the thumbnail image inside
  is `scaledToFit` (never cropped/zoomed to fill), so every card reads as
  the same size no matter what aspect ratio a given capture came out at
  (captures can now be auto-cropped to arbitrary quads, so this genuinely
  varies). Each card: `paper` background, a page-count badge (`accentSoft`
  pill, bottom-right, e.g. "3 pgs"), the document name below the card, and
  the date below that. Tapping **zoom-transitions** into the Document
  Viewer (§4.4) from the tapped card's own position/size — see the iOS
  implementation note in §4.2 for how (same technique as the scan button →
  Camera transition).
- **Empty state**: centered icon tile (viewfinder/scan-corners glyph),
  "No documents yet", helper copy ("Scanned documents are saved here. Point
  your camera at a page to begin."), and a primary "Scan a document" button.
- **Floating scan button**: 64pt/dp circle, `accent` background, camera/
  scan-corners icon, pinned bottom-center over a bottom fade gradient.
  Always visible on Home (in addition to the empty-state CTA). Tapping
  **zoom-transitions** into Camera (§4.2) from the button's own position,
  rather than the plain modal slide-up a plain `.fullScreenCover` gives by
  default.

### 4.2 Camera (capture)

Full-screen camera capture used to build up a multi-page document before
committing it to the library. On both platforms this is the OS's own
built-in document-scanning capture UI, not a custom-built camera screen —
see the platform notes below for why, including a reversal on iOS.

- Platform capture implementation (**this diverges by platform**):
  - **Android**: ML Kit **Document Scanner API** (`GmsDocumentScanning`),
    which provides its own capture → live edge detection → auto-crop →
    multi-page → per-shot review flow. This replaces the mock's custom
    shutter/gallery/stack chrome with the platform's native equivalent;
    behaviorally it satisfies the same user story. Android's per-shot
    review step is whatever `GmsDocumentScanning` itself presents — not
    independently customizable.
  - **iOS**: `VNDocumentCameraViewController` (VisionKit) — Apple's own
    document scanner, with the same live edge detection → auto-crop →
    multi-page → per-shot review flow as Android's ML Kit scanner. This app
    briefly replaced it with a fully custom `AVCaptureSession`-based
    camera (live `VNDetectDocumentSegmentationRequest` against the video
    feed, auto-capture, a hand-built review screen) to get control over
    the per-shot review screen's button layout — VisionKit's own review UI
    is a sealed system screen that puts **Retake** in the prominent spot
    and "keep this page" in a small back-chevron, with no public API to
    relabel or reposition it. That custom camera went through repeated
    rounds of on-device bugs (live detection not rendering, coordinate-
    space mismatches between the video buffer and the preview layer, false
    auto-captures from analyzing off-screen content, a `@State` mutation
    silently dropped mid-view-update) — each one individually fixable, but
    the cumulative iteration cost outweighed the button-layout win, and the
    app reverted to VisionKit: Apple's own maintained, known-reliable
    implementation, accepting its review screen's button layout as-is
    rather than continuing to chase custom-camera bugs.
  - **Both platforms — scan filters**: after the platform scanner's own
    crop, every page gets a filter applied so it reads as a processed
    *scan*, not a
    cropped photo — and the user can change which one, the way other
    scanner apps (Adobe Scan, Notes) do. Four filters, applied per page
    (each page in a multi-page document can have its own):
    - **Auto** (default) — exposure/color normalization plus a contrast/
      sharpness pass tuned for text-on-paper.
    - **Original** — no filter, the crop as captured.
    - **Grayscale** — desaturated, mild contrast boost.
    - **B&W** — desaturated with a strong contrast/brightness push, for
      the classic high-contrast "black text, white paper" scanner look.
    - Filter selection is a 5th tool alongside Crop/Highlight/Text/Sign in
      the Edit flow's tool bar (§4.3), showing a row of the 4 options —
      tapping one applies it live to the page preview already on screen.
      The choice is **persisted per page** (re-opening a saved document
      remembers it), and is independent of crop: changing the filter
      re-applies to the already-cropped image rather than re-running
      perspective correction, and re-cropping preserves whatever filter
      is currently selected rather than resetting it.
    - Applying a filter still runs off the main thread with the same
      "show the fast geometric crop immediately, swap the filtered result
      in a moment later" pattern as before, so neither capture nor
      re-cropping loses responsiveness.

**iOS zoom-transition implementation note** (applies to both zoom
transitions above — scan button → Camera, document card → Document
Viewer): implemented via `matchedGeometryEffect` with a shared
`@Namespace`, not a plain `.fullScreenCover`/`NavigationLink` push. A
`.fullScreenCover`/pushed `NavigationLink` destination is a *separate* view
hierarchy from the presenting screen, and `matchedGeometryEffect` only
animates smoothly between two views that are simultaneously part of the
*same* hierarchy during the transition — so each of these two destinations
is presented as a plain conditional overlay (`if isShowing { Destination() }`)
inside the same `ZStack` as its source screen, with the toggle wrapped in
`withAnimation`, rather than through SwiftUI's modal presentation APIs.
Camera's destination is `DocumentCameraView`, a `UIViewControllerRepresentable`
wrapping VisionKit with no `body` of its own to attach the modifier to
internally, so `RootView` chains `.matchedGeometryEffect` onto that call
site directly rather than inside the view like Document Viewer's does. This
is the standard, broadly-compatible (iOS 17+, no `#available` branching)
way to get a source-rect zoom transition; iOS 18 also ships a dedicated
`NavigationTransition.zoom` API, but building on the namespace/overlay
approach instead keeps one implementation path for both this iOS version
and future ones.

### 4.3 Edit (per-page editor)

Reached after capture finishes, or when re-editing a page from an existing
document. Paginated — "Page X of Y" in the top bar, and (for multi-page
documents) **horizontally swipeable** between pages, not just tap-arrows —
the chevrons still work too, both driving the same underlying page index
so an in-progress crop on the page being left is always committed before
switching, whichever way the user navigates.

- Top bar: **Cancel** (discard back to camera/prior state), page label +
  prev/next chevrons (`session.pageCount > 1`), **Save** (commits the
  document and opens the Export sheet with `pendingSave = true`).
- Center: the page rendered on a `paper` card (drop shadow, hairline
  border).
- **Tool bar** (5 equal-width buttons, bottom): **Crop**, **Highlight**,
  **Text** (OCR), **Sign**, **Filter**. Active tool is visually selected
  (`accentSoft` background + `accent` icon/label). A one-line contextual
  hint above the tool bar changes per active tool ("Drag the corners to fit
  the page" / "Tap a line of text to highlight it" / "Text recognition" /
  "Draw your signature" / "Choose how this page looks").
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
    drops into a placement mode over the page: the signature can be
    **dragged** (one finger, both axes), **resized** (corner handle drag,
    bottom-right), and **rotated** (a second, dedicated corner handle drag,
    top-right — tracking the angle from the signature's own center to the
    touch, applying only the *change* in angle each frame so grabbing the
    handle doesn't snap the signature to point at the finger) on both
    platforms before **Done** commits it at that position/size/rotation.
    **Redraw** returns to the drawing canvas. iOS originally used a
    two-finger `RotationGesture` twist for rotation (the "standard iOS
    convention" for combining move/rotate, as in Markup/Photos) but that
    proved unreliable to recognize once Sign placement lived inside the
    per-page `TabView(.page style)` added for swipeable pages (a two-finger
    gesture nested inside a swipe/scroll stack competes with that stack's
    own native `UIScrollView` recognizer far more than a one-finger drag
    does) and wasn't discoverable without a UI hint either, so it moved to
    the same handle-based approach as Android. Both platforms read/write
    the same normalized `rotation` (degrees, clockwise) field, so a
    signature's rotation round-trips correctly regardless of which platform
    placed it.
  - **Filter**: a row of 4 options (**Auto** / **Original** / **Grayscale**
    / **B&W** — see §4.2's "scan filters" note for what each does),
    applied live to the page preview on tap. Persisted per page.
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

Bottom sheet, **fixed height, not resizable/draggable to a different
size** — a single `presentationDetents` value, not `.medium`/`.large` or
the platform default free-form sheet, since its content is a short, fixed
set of rows with nothing that benefits from more room. Title "Export
document", subtitle varies ("Saved to Documents · choose a format to
share" right after saving a new scan, or "Choose a format to share" when
exporting an existing document). Two options:

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
  imagePath: String            // cropped + filtered page image on disk
  originalImagePath: String?   // pre-crop capture, kept for re-crop
  filter: auto | original | grayscale | blackAndWhite   // default auto
  ocrText: String?             // null until OCR has been run
  highlightedLineIndices/Regions: [...]   // OCR line regions marked highlighted
  signature: Signature?

Signature
  strokes: [[Point]]           // per-stroke point lists, for redraw/placement
  color: Color
  thickness: Double
  x, y, width: Double           // placement on the page, normalized to page size
  rotation: Double              // degrees around the signature's own center

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

1. **Capture**: the mock's camera screen is a static art-directed frame with
   a decorative sweep animation, no real detection. Both platforms improve
   on that with genuine live edge detection, auto-crop, and auto-capture on
   a steady frame, by delegating to the OS's own built-in document scanner —
   ML Kit's Document Scanner API on Android, VisionKit's
   `VNDocumentCameraViewController` on iOS (see §4.2 for the iOS detour
   through, and reversal back from, a custom-built camera) — rather than
   hand-rolling the mock's live-preview/shutter/stack chrome.
2. **Share**: the mock's share sheet is a hand-drawn list of four apps; the
   real apps hand off to the OS's native share surface, which is strictly
   more capable and is what users expect on both platforms.

Everything else in §4 — screens, copy, tool set, sheet behavior, toasts —
should be matched closely.
