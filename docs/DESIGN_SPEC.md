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

Ink `#171614`, Blue `#2C5EA8`, Clay `#A4552E`, Green `#2F6B4F` — all four
fixed values, deliberately **not** tied to light/dark appearance the way
every other themed color in this app is. A signature is drawn onto a page
that's always white paper regardless of which appearance the app itself is
in, so it must always render dark-on-white; Android's `SignatureColorOptions`
was already fixed hex strings, but iOS's `Theme.SignatureColor.color`
originally mapped `.ink` to `Theme.ink(_:)` — the same dynamic token used
for the app's own UI text, which flips to a near-white tone in dark mode —
so a signature drawn in dark mode rendered as pale, barely-visible ink on
the (white) page. Fixed by making `.ink` (and `PageRenderer`'s `UIColor`
equivalent) always resolve to `#171614` regardless of `ColorScheme`.

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
- **PRO badge**, top-right of the title row (§5): a small pill — crown icon
  + "PRO" — always visible on Home, unlike the inline "Premium for
  unlimited" subtitle link below the title (which only appears once the
  free-tier document limit is worth mentioning to a non-premium user with
  at least one saved document). A free user tapping it opens the same
  paywall every other premium gate opens; once subscribed, it switches to
  a softer fill (`accentSoft` instead of a solid `accent` background) and
  stops being tappable — the paywall screen has no "you're already
  premium" state to show, so there's nothing useful left to open.
- **Grid of document cards**, 2 columns, **fixed 3:4 aspect ratio
  regardless of the page's own proportions** — the thumbnail image inside
  is `scaledToFit` (never cropped/zoomed to fill), so every card reads as
  the same size no matter what aspect ratio a given capture came out at
  (captures can now be auto-cropped to arbitrary quads, so this genuinely
  varies). Each card: `paper` background, a page-count badge (`accentSoft`
  pill, bottom-right, e.g. "3 pgs"), the document name below the card, and
  the date below that. Tapping opens the document in the Edit flow (§4.3/
  §4.4) — there's no separate read-only viewer.
  - **Rename/Delete a saved document**: long-pressing a card (Android:
    `combinedClickable`'s `onLongClick` opening a `DropdownMenu`; iOS:
    `.contextMenu`) offers **Rename** and a destructive **Delete**.
    **Rename** opens a small alert/dialog with a pre-filled text field for
    the document's current name; confirming calls
    `DocumentRepository.renameDocument` (Android) /
    `RootView.renameDocument(_:to:)` (iOS), a plain in-place name update —
    no other document state changes. **Delete** prompts a confirmation
    ("Delete "\<name\>"? / This can't be undone."); confirming removes the
    document's DB/SwiftData record and its page image files from disk
    (`DocumentRepository.deleteDocument` on Android,
    `RootView.deleteDocument(_:)` on iOS) — cascade-delete rules handle the
    page/comment rows themselves, but not the files on disk those rows
    pointed at, so both platforms clean those up explicitly before dropping
    the record.
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
    crop, every page gets the **Auto** filter applied automatically so it
    reads as a processed *scan*, not a cropped photo — exposure/color
    normalization plus a contrast/sharpness pass tuned for text-on-paper.
    `DocumentFilter` (Auto/Original/Grayscale/B&W) and the per-page
    `filter` persisted alongside the rest of a page's edits still exist in
    the data model and rendering pipeline (`DocumentEnhancer`/
    `PageRenderer`), but there is no longer a user-facing **Filter** tool in
    the Edit flow's tool bar to change it after capture — every page simply
    keeps the Auto result. (Android never had this tool; it was removed
    from iOS.) Re-exposing filter choice — as a free option, or bundled
    into Premium — is open for a future round.
    - **iOS `DocumentEnhancer` pipeline** (Auto/Grayscale/B&W): since
      VisionKit's own edge detection is a sealed system component (no
      public API to tune its sensitivity, and `scan.imageOfPage(at:)`
      only ever hands back the already-cropped result, so a bad boundary
      call can't be re-detected from a fresher source afterward), the
      lever this app actually has over *scan quality* is what happens to
      the pixels after that crop. Two CoreImage passes run before the
      existing contrast/saturation/sharpen tweaks, both single-image
      filters chosen deliberately over a two-image blend (divide/
      subtract a blurred background) technique that's harder to get right
      without on-device testing:
      - **Paper white balance** (`whiteBalanced`): finds the brightest
        pixel per channel in the shot (`CIAreaMaximum`, read back via a
        1x1 bitmap render) as a stand-in for "the color of the blank
        paper," then neutralizes it to true white with
        `CIWhitePointAdjust` — removes a warm-lamp or cool-window color
        cast rather than trusting the camera's general-purpose auto white
        balance. Skipped if the brightest pixel isn't actually bright
        (a dim or already-broken shot), since forcing a white point
        against a false signal would make things worse.
      - **Shadow lifting** (`flattenLighting`, `CIHighlightShadowAdjust`):
        evens out a page lit unevenly (a hand's shadow, an angled desk
        lamp) with local, edge-aware tone mapping — the same building
        block behind Photos' Shadows/Highlights sliders — rather than a
        single global brightness curve that can only push the whole
        image lighter or darker at once. B&W applies this more
        aggressively than Auto/Grayscale before its contrast push, which
        is what makes it closer to real adaptive thresholding than a flat
        global contrast curve: without flattening the lighting first, the
        same threshold leaves a shadowed half of the page gray/blotchy
        while the lit half blows out to solid white.
      - Genuine per-pixel adaptive binarization (a true Sauvola/Niblack-
        style local threshold) would need a custom CoreImage kernel,
        which was deliberately not attempted here given no on-device
        build/test loop available to verify kernel math is correct before
        shipping it.

**iOS zoom-transition implementation note**: the scan button → Camera
transition is implemented via `matchedGeometryEffect` with a shared
`@Namespace`, not a plain `.fullScreenCover`/`NavigationLink` push. A
`.fullScreenCover`/pushed `NavigationLink` destination is a *separate* view
hierarchy from the presenting screen, and `matchedGeometryEffect` only
animates smoothly between two views that are simultaneously part of the
*same* hierarchy during the transition — so Camera's destination
(`DocumentCameraView`, a `UIViewControllerRepresentable` wrapping VisionKit)
is presented as a plain conditional overlay (`if showCamera { ... }`)
inside the same `ZStack` as `HomeView`, with the toggle wrapped in
`withAnimation`, rather than through SwiftUI's modal presentation APIs.
This is the standard, broadly-compatible (iOS 17+, no `#available`
branching) way to get a source-rect zoom transition; iOS 18 also ships a
dedicated `NavigationTransition.zoom` API, but building on the
namespace/overlay approach instead keeps one implementation path for both
this iOS version and future ones. Tapping a document card has no such
transition today — Edit (§4.3/§4.4) is presented via `.fullScreenCover`,
which `matchedGeometryEffect` can't reach into, so `documentZoomID(for:)`
is currently a harmless no-op id with nothing to animate into (kept in case
a future card → Edit transition is worth building).

### 4.3 Edit (per-page editor)

Reached after capture finishes, or when re-editing a page from an existing
document. Paginated — "Page X of Y" in the top bar, and (for multi-page
documents) **horizontally swipeable** between pages, not just tap-arrows —
the chevrons still work too, both driving the same underlying page index
so an in-progress crop on the page being left is always committed before
switching, whichever way the user navigates.

**iOS implementation note**: swiping is `TabView(.page style)`, with each
page's content in its own vertical `ScrollView`; both are `.scrollDisabled`
for the duration of signature placement as a defensive measure, but the
real bug behind an earlier "the signature only moves vertically, never
horizontally" report turned out to be unrelated to either container. It
was a stale-snapshot bug in `PageEditorView`'s binding into
`SignaturePlacementView`: `Binding(get: { placing }, ...)` closed over
`placing` — a `let` captured once per `body` evaluation — instead of
reading `placingSignature` itself each time. Placement's drag handler
writes `signature.x` and `signature.y` as two separate statements per
frame; with a snapshot-capturing getter, the second write's implicit
read-modify-write reads that same frozen snapshot rather than the first
write's result, silently discarding it — whichever field is written last
always "wins," which is exactly why signatures could only ever move
vertically, and (by the same mechanism, since `signature.rotation +=
delta` is also a read-modify-write) why the rotate handle never actually
accumulated rotation either. Fixed by having the getter read
`placingSignature` directly.

- Top bar: **Cancel** (discard back to camera/prior state, or to Home for a
  re-edit), page label + prev/next chevrons (`session.pageCount > 1`) + a
  small trash icon, then **Save** or **Export** — see §4.4 for which and
  why.
  - **Delete this page**: tapping the trash icon prompts "Delete this
    page? / This can't be undone." (Delete/Cancel). Covers the case where
    the same page got scanned a few times and one capture came out badly —
    the user can drop it during review instead of saving it into the
    document. Deleting the only remaining page closes the whole Edit flow
    (nothing left to edit); deleting any other page just moves the current
    index to a neighbor and keeps editing. On Android this "last page"
    case falls out for free from the `pages.isEmpty()` guard already at
    the top of `EditScreen` (it exits to the caller on the next
    recomposition); iOS's `EditFlowView.deleteCurrentPage()` checks
    `pageCount <= 1` explicitly and calls `onCancel()` itself.
    - **Deleting a page while re-editing an existing document** (§4.4) is
      deliberately *not* the same as deleting one from a fresh capture — the
      file on disk is still referenced by that document's persisted row
      until Save/Export actually commits, so deleting it immediately would
      corrupt the document if the user backs out instead of saving.
      **iOS**: SwiftData's cascade delete only fires when the *document*
      is deleted, not when a page is dropped from its relationship array,
      so `EditFlowView.performSave()` calls `removeDeletedPages(from:)` to
      explicitly `modelContext.delete()` any persisted page no longer
      present in `session.pages` (plus its on-disk image files via
      `ImageStore.delete`) — this only runs for the re-edit case; a
      fresh capture's pages were never in `DocumentModel.pages` to begin
      with. **Android**: `ScanSessionViewModel.deletePage(index)` only
      deletes the removed page's image file(s) immediately when
      `existingDocumentId == null` (a fresh capture); for a re-edit, that
      cleanup is deferred to `DocumentRepository.updateDocument`, which
      diffs the saved pages against the ones still present in the session
      and deletes both the dropped `PageEntity` rows and their files
      together, atomically with the rest of the save.
- Center: the page rendered on a `paper` card (drop shadow, hairline
  border).
- **Tool bar** (5 equal-width buttons, bottom): **Crop**, **Adjust**,
  **Comment**, **Text** (OCR), **Sign**. Active tool is visually selected
  (`accentSoft` background + `accent` icon/label). A one-line contextual
  hint above the tool bar changes per active tool ("Drag the corners to fit
  the page" / "Adjust brightness and contrast" / "View and add comments" /
  "Text recognition" / "Draw your signature"). **Sign** and **Text** both
  carry a small **PRO** badge (top-right corner of the button) when the
  user isn't currently premium — see §5 for the gating and paywall behind
  it. Tapping either while free routes to the paywall instead of opening
  the tool, same mechanism for both (`pendingPremiumTool` on both platforms
  remembers which one was tapped, so completing a trial/subscription
  resumes that tool rather than always reopening Sign). There used to be a
  sixth tool, **Highlight** (tap an OCR'd line to toggle a translucent color
  band over it) — removed as redundant now that **Comment** covers
  "flagging something on a page" more usefully, and to keep the bar at a
  clean five buttons rather than growing it to six.
  - **Crop**: adjustable quad/rect overlay with draggable corner handles;
    commits a perspective-corrected crop of the page image. (If using
    VisionKit/ML Kit capture, an initial auto-crop is already applied — this
    tool lets the user refine it.)
  - **Comment**: opens a full-screen page (not a bottom sheet, same
    reasoning as the Text tool below) listing the document's comments so
    far (empty state: "No comments yet") plus a composer — a text field
    (placeholder "Note for this page") and a **Post** button, disabled
    until there's non-blank text. Free, not Premium-gated. Works
    identically for a brand-new capture and a re-edit of an already-saved
    document (§4.4): posting a comment doesn't write to the database
    immediately — it's buffered (`EditSession.comments` / `DraftComment` on
    iOS, `ScanSessionViewModel.comments` / `DraftComment` on Android) the
    same way page edits stay in memory until Save/Export, at which point
    every buffered comment without an already-persisted counterpart
    becomes a real `CommentModel`/`CommentEntity` row tagged with the page
    index it was added from. Re-editing a saved document seeds this buffer
    from its existing comments (`EditSession.load(from:)` /
    `ScanSessionViewModel.startExistingSession`) so both old and new
    comments show in the same list. iOS presents it via `.fullScreenCover`;
    Android via a `Dialog(properties = DialogProperties(usePlatformDefaultWidth
    = false))`, same as the Text tool's page.
  - **Adjust**: two sliders, **Brightness** and **Contrast**, each a
    standard platform slider (track + draggable thumb). Applied on top of
    whatever the page currently looks like (crop + the page's other
    processing), not a replacement for it. The two platforms implement this
    with genuinely different architectures, not just different code:
    - **iOS**: brightness/contrast are baked into `PageEditState.image`'s
      actual pixels via `DocumentEnhancer.applyAdjustments` (one more
      `CIColorControls` pass, after whatever `DocumentFilter` is active —
      see §4.2's scan-filter note). Dragging a slider doesn't re-run
      CoreImage on every frame — that would be far too slow — it shows a
      live SwiftUI `.brightness()/.contrast()` preview on top of a
      brightness/contrast-neutral base (`adjustBaseImage`, computed once
      when Adjust opens), and only commits the real, precisely-recomputed
      pixels (`PageEditState.commitAdjustments`) when the drag ends.
      `PageModel.brightness`/`.contrast` persist the values (for a future
      re-edit entry point to read back from, mirroring `PageModel.filter` —
      neither is actually restored into a fresh `PageEditState` today,
      since there's no live way to reach re-editing yet, same caveat as
      `filter`).
    - **Android**: never baked into `imagePath` at all — applied live via
      an `android.graphics.ColorMatrix`/`androidx.compose.ui.graphics.ColorMatrix`
      brightness-contrast matrix (`util/ColorAdjust.kt`), the same
      "composite at render/export time, never touch the file" treatment
      `PageRenderer` already gives highlights and the signature. `PageCard`
      applies it as a Compose `ColorFilter` on screen; `PageRenderer.flatten`
      applies the `android.graphics` equivalent when baking the flat export
      bitmap. Since nothing is ever baked into the stored file, there's no
      "live preview vs. committed pixels" distinction to manage — the
      slider's value *is* the live state, written straight into the
      `DraftPage`/`PageEntity` on every drag tick. `PageEntity.brightness`/
      `.contrast` are new Room columns (schema bumped to version 2 with
      `fallbackToDestructiveMigration()` — pre-release, no real install
      base yet to preserve).
  - **Text (OCR), Premium** (see §5/§7): runs on-device text recognition
    (`Vision`/`VNRecognizeTextRequest` on iOS, ML Kit **Text Recognition
    v2** on Android) and opens a **full-screen page** (not a bottom sheet —
    a fixed-height sheet was cramped for reading/copying anything longer
    than a few lines): "Reading page…" while busy, then the recognized text
    filling the screen with a single **Copy All** action, which copies the
    full text to the clipboard and shows a **"Copied"** toast so tapping it
    has visible confirmation. The text itself is also directly selectable
    (`.textSelection(.enabled)` on iOS, `SelectionContainer` on Android), so
    a user who only wants part of it can drag out a selection with the
    system's own UI instead of copying everything. iOS presents it via
    `.fullScreenCover`; Android via a
    `Dialog(properties = DialogProperties(usePlatformDefaultWidth = false))`
    rather than a plain full-size overlay Box, so the system back
    button/gesture dismisses it for free. There used to be a second
    action, **"Keep as searchable"** — removed after confirming it did
    nothing a user could actually feel: OCR'd text is embedded into the
    exported PDF automatically whenever recognition has run, regardless of
    whether this button was ever tapped, so it was a no-op control that
    only added confusion.
    - **Toast-inside-a-modal bug** (surfaced by the "Copied" toast above,
      but not specific to it): both platforms mount their toast overlay
      once, at the app root (`RootView`/`MainActivity`), sized to that root
      view's own hierarchy. A `.fullScreenCover` (iOS) or `Dialog`
      (Android) opens a genuinely separate presentation layer/window that
      doesn't composite with an ancestor's overlay, so any toast triggered
      from *inside* one — "Copied" here, but also e.g. "Signature added"
      inside the Edit flow's own `.fullScreenCover` on iOS — was silently
      invisible. Fixed by mounting a second overlay sharing the same
      underlying toast state (`ToastCenter`/`ToastState`) inside each
      nested presentation that needed one, rather than trying to route
      toasts back up to the root layer.
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
- Saving a brand-new capture moves it into the library, shows a toast
  ("Saved to Documents"), and opens the Export sheet.

### 4.4 Re-editing a saved document (no separate Document Viewer)

Tapping a document card on Home (§4.1) does **not** open a separate
read-only viewer — it reopens the exact same Edit flow (§4.3) a fresh
capture uses, seeded from that document, with every tool
(Crop/Adjust/Comment/Text/Sign) available and working identically either
way. An earlier design had a dedicated Document Viewer screen (page list +
a Comments section below it + a bottom "Comment"/"Export" bar); it was
retired in favor of full reuse, since a viewer that could only add
comments and export was duplicating most of Edit's own UI while offering
strictly less — this way every editing capability just works on a saved
document too, with no separate screen to keep in sync.

- **Entry point**: iOS's `EditSession.load(from:)` and Android's
  `ScanSessionViewModel.startExistingSession(document)` reconstruct an
  editable session from a `DocumentModel`/`DocumentWithDetails` — each
  page's image (loading `originalImagePath` when present so Crop still has
  the pristine source to work from), its `filter`/`brightness`/`contrast`,
  its OCR text/lines, its signature, and the document's comments, all
  mapped into the same in-memory types (`PageEditState`/`DraftPage`,
  `DraftComment`) a fresh capture builds directly from the camera. Crop
  quads are the one thing that don't round-trip — they were never
  persisted on either platform — so re-opening Crop on a saved page starts
  from a fresh inset rectangle, same as re-cropping an already-cropped
  fresh-capture page always has.
  - **Page identity round-trips for Save**: each reconstructed page keeps
    a handle back to its real persisted row — `PageEditState.existingPageID`
    on iOS, `DraftPage.id` (which already doubled as the eventual
    `PageEntity.id` even for fresh captures) on Android — so Save can
    match modified/kept/deleted pages against the document's actual rows
    and upsert or delete them in place instead of creating duplicates. See
    §4.3's page-delete note above for the deferred-file-deletion half of
    this.
- **Top bar**: identical to §4.3's, except the trailing button reads
  **Export** instead of **Save** (`session.existingDocument == nil` on iOS,
  `scanSession.existingDocumentId == null` on Android decides which). Both
  buttons call the same save path — `EditFlowView.performSave()` /
  `EditScreen`'s `performSaveOrExport()` — which persists the pages/
  comments (updating the existing document's rows rather than inserting a
  new document) and then opens the Export sheet exactly like a fresh
  save's "Save" does, just skipping the "Saved to Documents" toast (nothing
  new was created) in favor of "Changes saved" on iOS, or no toast at all
  before the sheet opens on Android — both platforms still land on the
  same Export sheet either way, so exporting the just-re-edited document
  is always one tap away. Re-saving an existing document never counts
  against the free-tier save limit (§5) — only creating a brand-new one
  does.
  - Android-specific behavior note: prior to this reuse work, tapping Save
    on a fresh capture required a follow-up tap on the (separate) viewer's
    own "Export" button to actually see the Export sheet — an
    inconsistency with iOS, which already opened it automatically right
    after saving. Consolidating Save and Export into one
    `performSaveOrExport()` (used for both cases now) closed that gap by
    always opening the Export sheet inline after persisting, matching
    iOS's already-proven flow.

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

## 5. Premium & Paywall

Sign is the first premium-gated tool (§4.3); more may follow (see §9's
notes on future premium candidates). Entitlement is a **local mock** on
both platforms right now — a `PremiumManager` (iOS: `UserDefaults`-backed
`ObservableObject`; Android: `SharedPreferences`-backed plain class) that
tracks `hasUsedTrial`/trial-end-date/`isSubscribed` and exposes
`isPremium()`. Tapping the paywall's CTA grants entitlement immediately —
there is no real payment processing yet, so the whole trial/subscribe UX
can be built and tested without App Store Connect / Play Console
subscription products existing. Wiring `startTrial`/`subscribe`/
`restorePurchases` to real StoreKit 2 (iOS) / Play Billing Library
(Android) calls is a separate, later step once those products are created;
the gating check and paywall UI shouldn't need to change when that happens.

- **Gating**: tapping **Sign** or **Text** in the Edit tool bar calls
  `premiumManager.isPremium()` (re-checked on every tap, not cached, so an
  expired trial is caught immediately) before opening the signature pad or
  the recognized-text page. If not premium, the paywall presents instead
  and the tool never activates; which of the two was tapped is remembered
  (`pendingPremiumTool`) so a successful trial/subscription resumes that
  same tool rather than always reopening Sign. **Comment** is not gated —
  it's a plain note field, unrelated to OCR or any other premium feature.
- **Badge**: the Sign and Text tool buttons each show a small **PRO** pill
  (top-right corner) whenever the user isn't currently premium; it
  disappears once they are (trial or subscribed).
- **Trial**: 3 days, one-time-per-device (`hasUsedTrial` never resets).
  Two paywall copy variants:
  - **Never used the trial**: "Try Premium free for 3 days" headline,
    **Start Free Trial** primary button, fine print noting the paid rate
    it converts to after 3 days.
  - **Already used the trial** (including an expired one): plain "Unlock
    Premium" headline, no trial mention, **Subscribe — $4.99/mo** primary
    button. ($4.99/mo is placeholder copy, not a configured real price —
    see the mock-entitlement note above.)
  - Both variants share: a feature-highlight list (signing, "more premium
    tools on the way," supporting development), a **Restore Purchases**
    link, and a dismiss (✕) button that backs out without changing
    `activeTool`'s premium-gated state.

Sign is no longer the only gate — **Text (OCR)** (§4.3), **limited document
storage**, and **PDF password protection** (the latter two drawn from §9's
brainstorm list) are all implemented the same way:
`premiumManager.isPremium()`/`canCreateNewDocument` checked at the point of
use, paywall shown on failure, entitlement re-checked live rather than
cached.

- **Limited document storage**: scanning itself is unrestricted on both
  platforms — the camera and gallery-import entry points always work,
  since blocking capture wastes the time a user just spent scanning and
  these entry points can't be un-done cleanly if the user is denied
  afterward. The cap instead applies to **saving**: a free account can have
  at most `PremiumManager.freeDocumentLimit` / `FREE_DOCUMENT_LIMIT` (3)
  documents in the library; Premium removes it. Checked when **Save** is
  tapped in the Edit flow (iOS: `EditFlowView.save()`; Android:
  `EditScreen`'s Save action, via `EditViewModel.documentCount()`) —
  re-saving an already-saved document (a re-edit) is never gated, only
  creating a brand-new one.
  - **At the limit**: Save shows a dialog — "Document limit reached: Free
    plan is limited to 3 saved documents. Upgrade for unlimited storage,
    export this one without saving, or cancel." — with three actions:
    - **Start Free Trial** / **Upgrade to Premium** (label depends on
      `hasUsedTrial`) opens the paywall; on trial-start/subscribe/restored
      success the save is retried automatically.
    - **Export** opens the same Export sheet used everywhere else (PDF/JPG
      choice, PDF password protection) over the current pages — the
      document is never added to the library regardless of which format
      is chosen, so nothing here counts against the cap. Dismissing that
      sheet (by exporting or by Cancel/Close) always ends the edit session.
    - **Cancel** dismisses the dialog; the user stays on the Edit screen
      with nothing saved or exported.
  - **Discoverability**: the cap is surfaced before anyone hits it — Home's
    subtitle line reads "N of 3 free documents — Premium for unlimited" for
    a non-premium user with documents (or "Nothing saved yet · 3 free
    documents" when empty), styled in the accent color with an underline
    (vs. the plain muted count once premium) so it visually reads as a
    tappable link, not just informational text. Tapping it (when not
    premium) opens the paywall directly as a standing shortcut — so the
    limit isn't only ever explained by a dialog shown once someone's
    already blocked.
- **PDF password protection**: a small lock icon on the PDF row of the
  Export sheet (JPG is unaffected) — tapping the row itself exports the
  PDF as before; tapping the lock icon is the dedicated premium gate.
  Premium users get a password prompt (SwiftUI `.alert` + `SecureField` /
  Compose `AlertDialog` + `OutlinedTextField`) instead of expanding the
  Export sheet itself, preserving its fixed, non-resizable height (§4.5).
  Free users see the paywall (reason: "Password-protecting PDFs is a Premium
  feature") first; success reopens the password prompt. Same password is
  used as both the PDF's "open" and "permissions" password — there's no
  separate "restrict editing" concept in this app to justify two.
  - **Discoverability**: a small **PRO** badge sits on the lock icon for a
    non-premium user (hidden once they're premium), and the icon itself no
    longer needs a label to be found.
  - **Freemium upsell on plain export**: a free user tapping the PDF row
    itself (not the lock) sees a one-time-per-tap prompt — "Protect this
    PDF? Add a password so only people who have it can open this file.
    Available with Premium." — with **Add Password** (routes into the same
    paywall → password-prompt flow as the lock icon) and **Export Without
    Password** (proceeds exactly as before). This only fires for free users
    exporting a PDF; premium users and JPG exports are unaffected.
  - **iOS**: PDFKit already ships on-device — `PDFDocument(data:).write(to:
    withOptions: [.userPasswordOption:, .ownerPasswordOption:])` loads the
    already-written unprotected PDF and overwrites it in place encrypted.
  - **Android**: `android.graphics.pdf.PdfDocument` (used for PDF generation
    itself) has no encryption support at all, so this adds
    `com.tom-roush:pdfbox-android` (Apache 2.0, an actively-maintained
    Android port of Apache PDFBox) as a narrowly-scoped dependency —
    `PdfPasswordProtector` loads the already-generated PDF file with
    `PDDocument.load`, applies a `StandardProtectionPolicy` (128-bit), and
    saves it back in place. Requires one-time
    `PDFBoxResourceLoader.init(context)`, called from
    `DocumentScannerApp.onCreate`.
- **Office format export** (DOCX/XLSX/PPTX — DESIGN_SPEC §9): three new
  rows in the Export sheet, each **entirely** Premium-gated (whole row, not
  an add-on like the PDF lock icon) — tapping one while not premium opens
  the paywall (reason: "Office format export is a Premium feature") and
  retries the same export on success, exactly like the Sign tool's gating.
  A **PRO** badge sits on each row's format-icon badge for a free user.

  **CloudConvert was tried and dropped.** A test integration briefly routed
  these three formats through CloudConvert's paid conversion API (upload
  the same PDF plain PDF export produces, poll, download) to see whether a
  real conversion engine handled layout better than the hand-rolled
  writers below. It didn't look meaningfully better, and it added real
  per-conversion cost, a network dependency the rest of the app doesn't
  have, an API key shipped client-side, and documents leaving the device —
  so it was removed entirely (`CloudConvertService` on both platforms,
  `CloudConvertConfig`/`local.properties` API key plumbing, and the
  Android `INTERNET` permission it needed) in favor of going back to the
  on-device writers described below, which is what ships now.

  Hand-rolled OOXML on both platforms rather than a dependency (see the
  Office-export feasibility note in §9) — DOCX/XLSX/PPTX are all just ZIP
  archives of XML parts:
  - **DOCX**: one paragraph per OCR'd line, a page break between pages.
    Alignment, relative emphasis, paragraph spacing, and simple tables are
    approximated purely from each line's (and, for tables, each word's)
    OCR bounding box (`DocxLineLayout.analyze` / `DocxTableDetector`, same
    logic hand-ported on both platforms):
    - **Alignment**: a line's left/right edges are compared against the
      page's overall left margin and right edge (from all its lines) to
      classify it left/center/right — e.g. a line whose midpoint sits near
      the page's horizontal center and that's meaningfully narrower than
      the page's content width reads as centered.
    - **Font size is intentionally fixed** (11pt for every line) — an
      earlier version scaled it by each line's box-height ratio, but OCR
      box heights turned out too noisy a signal: the result looked
      inconsistent with the actual scan rather than matching it, so this
      was reverted. A line much taller than the page's median line height
      (≥1.4×) is still marked **bold**, as a plausible stand-in for real
      emphasis, since size is the only signal available.
    - **Paragraph spacing**: an extra blank paragraph is inserted before
      any line whose vertical gap from the previous one is notably larger
      (>1.6×) than the page's typical line-to-line gap, approximating a
      paragraph break rather than a mere line wrap.
    - **Table detection** (`DocxTableDetector`): a table row reaches OCR as
      one of two shapes, and both are handled:
      - **Same OCR line, several words**: columns cramped close enough
        together that the OCR engine still grouped them into one line — an
        unusually large gap between two adjacent words (learned per-page:
        ≥3× the page's typical inter-word gap, floor 2% of page width) is
        treated as a column break, splitting that line into cells.
      - **Separate OCR lines, same row**: a wide-gapped layout — a
        genuinely tabular scan (e.g. a two-column glossary/translation
        sheet) where each column's cell is far enough from its neighbor
        that the OCR engine's own line-grouping already reports them as
        distinct lines, not one line with an internal gap. `rowBands`
        groups lines whose vertical extents overlap by more than half the
        shorter line's height — i.e. they sit side by side — into one row
        *before* any word-gap analysis runs; each line in a multi-line
        band becomes one cell directly. **This is the far more common
        shape in practice**, since OCR line-grouping keys off proximity
        and real table columns are deliberately spaced apart — a first
        version of this detector only looked for the same-line-several-
        words shape, so it never even considered a well-spaced two-column
        table a candidate, and every line landed in the exported sheet's
        column A regardless of source layout.

      Either way, consecutive rows that split into the *same number* of
      cells at matching horizontal positions (within 4% of page width) are
      grouped into one real OOXML `<w:tbl>` (DOCX) or spread across
      spreadsheet columns A, B, C… (XLSX, below); a lone multi-column row
      with no matching neighbor above or below stays a plain paragraph
      (≥2 rows required to call it a table). Requires word-level OCR
      boxes for the same-line shape, which weren't previously captured —
      `OCRWord`/`OcrWord` added to the `OCRLine`/`OcrLine` model (both
      decode-safely for documents saved before this field existed). Purely
      geometric, on both platforms — ML Kit already returns word-level
      boxes via `Line.elements` (just wasn't read before); Vision computes
      them per word via `VNRecognizedText.boundingBox(for:)` on
      word-boundary substring ranges. This is a heuristic on noisy OCR
      data, not real table recognition — no ground truth to check it
      against, so it works well on clean, well-spaced tables and can
      misfire on tight layouts, multi-line cells (a cell whose text wraps
      to a different number of lines than its row neighbor breaks the
      row-band pairing for those particular lines — the well-behaved rows
      around it are unaffected), or merged cells.
    - **What this can't do**: neither Vision (iOS) nor ML Kit (Android)
      report actual font weight, italics, or underline — only recognized
      text and a bounding box. Real bold/underline detection would need
      pixel-level image analysis (stroke thickness, underline strokes
      beneath the baseline), which is separate, riskier computer-vision
      work — closer to the `Advanced OCR` candidate below than a
      refinement of this export format. The "bold" above is therefore a
      size-based approximation, not a real style detection; likewise table
      detection is geometric guesswork, not layout recognition.
  - **XLSX**: one worksheet per page (using inline strings, so no
    shared-strings table is needed). Reuses the *same* `DocxTableDetector`
    table detection DOCX's export uses (above) rather than its own separate
    logic — a run of lines detected as a grid-like table spreads its cells
    across columns A, B, C… one spreadsheet row per detected table row;
    everything else (ordinary paragraph lines, or a page where no table was
    detected at all) still goes one line per row in column A, since there's
    no column structure to split it by there. Originally this format always
    put every OCR'd line in column A regardless of layout, so a genuinely
    tabular scan (e.g. a two-column glossary/translation sheet) exported as
    a single lopsided column instead of a real two-column sheet — wiring in
    the existing detector fixed that without inventing a second heuristic.
    Same caveat as DOCX's table detection applies here too: geometric
    guesswork on noisy OCR data, works well on clean well-spaced tables,
    can misfire on tight layouts, multi-line cells, or merged cells.
  - **OCR-on-demand**: normal editing only runs OCR when the Text tool is
    opened, so a page nobody visited that tool on has nothing recognized
    yet — unlike PDF/JPG (which always have the page
    image to fall back on), DOCX/XLSX have *only* OCR text, so exporting
    with empty `ocrLines` would silently produce a blank document/sheet.
    Both formats run OCR live for any page missing it before building
    (iOS: `OCRService.ensureLines(for:)`, caching the result back onto the
    page; Android: `OoxmlUtil.ensureOcrLines`), so the export always
    reflects the page's actual text regardless of what the user did during
    editing.
  - **PPTX**: one slide per page, each a full-bleed picture of the
    flattened page (same rendering as JPG export) sized to a fixed
    US-Letter-proportioned slide (7.5in × 10in) so the image doesn't need
    aspect-fit math. No real "slide content" beyond the page image itself.
  - **iOS**: `OOXMLZipWriter` — Foundation has no ZIP writer, and pulling
    in a compression library just for a few KB of XML wasn't worth it, so
    every entry is written **stored** (uncompressed), which is fully legal
    per the ZIP spec and universally supported by Word/Excel/PowerPoint.
    `DocxExportService`/`XlsxExportService`/`PptxExportService` each build
    their XML parts and hand them to it.
  - **Android**: `java.util.zip.ZipOutputStream` (already in the JDK) does
    the ZIP packaging directly — no custom zip-format code needed there,
    just the XML generation (`DocxExportService`/`XlsxExportService`/
    `PptxExportService`) plus a shared `OoxmlUtil` for XML-escaping and
    entry-writing.
  - None of this has been opened in real Word/Excel/PowerPoint (no Office
    suite in the sandbox this was built in) — verify on real documents
    before relying on it.

## 6. Data model

```
Document
  id: UUID
  name: String                 // default "Scan N"; user-renamable from Home's long-press menu (§4.1)
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
  highlightedLineIndices/Regions: [...]   // vestigial — the Highlight tool that
                                // wrote these was removed (§4.3); kept in the
                                // schema/rendering/export pipeline only so a
                                // document saved before that removal still
                                // renders its highlights, never newly set
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

## 7. Platform implementation notes

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

## 8. Deliberate simplifications vs. the interactive mock

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

## 9. Future premium candidates

Brainstormed; three have since been built (see §5's "Limited document
storage", "PDF password protection", and "Office format export" — struck
through below), the rest are still **not built**. Listed here so a future
round doesn't have to re-derive the list from scratch. Roughly grouped
from "small lift, obvious value" to "bigger lift, needs its own design
pass":

- ~~**Batch/unlimited scanning**~~ — done, §5, as a **saved-document** cap
  rather than a scanning cap (scanning itself stays unrestricted; see §5's
  "Limited document storage" for why).
- ~~**More export formats (DOCX/XLSX/PPTX)**~~ — done, §5, hand-rolled
  OOXML on both platforms rather than a paid SDK (Aspose/Syncfusion/
  GroupDocs) or a heavy library like Apache POI — all on-device, so
  unlimited Premium use costs nothing marginal, the same reasoning that
  already applied to unrestricted PDF/JPG export. Worth remembering:
  DOCX carries real content (the OCR'd text); XLSX/PPTX only ever have
  "OCR lines in column A" / "one full-page image per slide" to work with,
  since this app has no detected table or slide-layout structure — real
  tabular/layout reconstruction is `Advanced OCR`/`AI-assisted
  features`-sized work, below, not a refinement of this feature. Still
  open: custom watermarks, higher-resolution export, batch export of
  multiple documents at once.
- **Cloud backup/sync** — currently everything is local-only; syncing
  across a user's devices is a natural premium tier (also the biggest
  lift, since there's no backend at all today).
- **Advanced OCR** — multi-language recognition, exporting recognized text
  as a structured format (CSV for tables, etc.), batch OCR across a whole
  document at once.
- **AI-assisted features** — summarize a document, extract key fields
  (dates, totals, names) as structured data, answer questions about a
  document's contents, merge/reorder pages across multiple documents.
  Highest lift (needs an LLM API integration + likely a backend proxy for
  the API key), but also the most differentiated relative to other scanner
  apps.
- ~~**Password-protected PDF export**~~ — done, §5. **Custom
  branding/no-watermark** export remains open, if a free tier ever adds a
  watermark.
