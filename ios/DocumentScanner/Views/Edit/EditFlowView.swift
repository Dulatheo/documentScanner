import SwiftData
import SwiftUI

/// The per-page editor (DESIGN_SPEC §4.3): Cancel/"Page X of Y"/Save top
/// bar, the page on a paper card with the active tool's overlay, a
/// contextual hint, and the five-tool bottom bar.
struct EditFlowView: View {
    @ObservedObject var session: EditSession
    @ObservedObject var toastCenter: ToastCenter
    @ObservedObject var premiumManager: PremiumManager
    /// Size of the saved-documents library *before* this save — used to
    /// gate the free-tier save limit (DESIGN_SPEC §5 "limited document
    /// storage"). Only relevant when saving a brand-new document; re-saving
    /// an existing one never counts against the cap.
    let documentCount: Int
    var onCancel: () -> Void
    var onSaved: (DocumentModel) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var modelContext

    @State private var activeTool: EditTool?
    @State private var showOCRSheet = false
    @State private var showCommentsPage = false
    @State private var isDrawingSignature = false
    @State private var placingSignature: Signature?
    @State private var showPaywall = false
    @State private var showSaveLimitAlert = false
    @State private var showSaveLimitPaywall = false
    /// Set by "Export" on the save-limit dialog — opens the same Export
    /// sheet used elsewhere (PDF/JPG choice, PDF password protection) over
    /// the current pages, without ever adding the document to the library
    /// (see `exportWithoutSaving()`).
    @State private var saveLimitExportTarget: ExportTarget?
    /// Confirms deleting the current page (DESIGN_SPEC §4.3 "delete a
    /// scanned page") — e.g. after scanning the same page a few times and
    /// finding one capture came out badly during review.
    @State private var showDeletePageConfirm = false
    /// Live Brightness/Contrast while the Adjust tool's sliders are being
    /// dragged (DESIGN_SPEC §4.3 "Adjust tool") — kept separate from
    /// `PageEditState.brightness/contrast` so dragging can preview
    /// instantly via cheap SwiftUI `.brightness()/.contrast()` view
    /// modifiers instead of re-running CoreImage on every frame; only
    /// committed to the real pixel data (`PageEditState.commitAdjustments`)
    /// once the drag ends.
    @State private var liveBrightness: Double = 0
    @State private var liveContrast: Double = 1
    /// The current page's crop + filter result with brightness/contrast
    /// still at their neutral defaults — computed once when the Adjust
    /// tool opens (DESIGN_SPEC §4.3 "Adjust tool"), so the live
    /// `.brightness()/.contrast()` preview modifiers apply on top of a
    /// clean base instead of stacking on an image that already has the
    /// *previous* committed brightness/contrast baked into its pixels.
    /// Nil until that one-time computation finishes.
    @State private var adjustBaseImage: UIImage?
    /// Which premium-gated tool (`.sign` or `.ocr`) triggered `showPaywall`,
    /// so a successful trial/subscription can resume the tool the user
    /// actually tapped instead of always reopening Sign.
    @State private var pendingPremiumTool: EditTool?

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().overlay(theme.line)

                // Swipeable, one page per screen (DESIGN_SPEC §4.3) — the
                // chevrons in `topBar` still work too (both drive
                // `session.currentIndex` through `EditSession.goTo(_:)`,
                // which commits any in-progress crop on the page being left
                // before switching, exactly like the chevrons always did).
                //
                // `.scrollDisabled(placingSignature != nil)` on both the
                // per-page ScrollView and the TabView itself: previous
                // attempts tried to out-arbitrate these ancestors' native
                // pan/scroll recognizers with SwiftUI-side `.highPriorityGesture`
                // tuning, which never actually fixed "the signature won't
                // move horizontally" — most tellingly, it *also* didn't move
                // when the TabView wasn't even in the touch's ancestor chain
                // at all in one attempt, which points at the vertical
                // ScrollView (present regardless of page count) actually
                // winning the *whole* drag, not just contesting the
                // horizontal component: a vertical drag under that theory
                // would scroll the page itself (with the signature just
                // going along for the ride, unmoved relative to it), which
                // looks like "it moves in Y" without the signature's own
                // position ever actually changing, while a horizontal drag —
                // nothing to scroll that way — does nothing at all.
                // `.scrollDisabled` is the official, targeted tool for this:
                // unlike `.disabled()`, it only turns off the container's
                // own scrolling, not hit-testing for its children, so the
                // signature's own gestures stay fully functional.
                TabView(selection: Binding(get: { session.currentIndex }, set: { session.goTo($0) })) {
                    ForEach(Array(session.pages.enumerated()), id: \.element.id) { index, pageState in
                        ScrollView {
                            pageCard(for: pageState)
                                .padding(.horizontal, 26)
                                .padding(.vertical, 22)
                        }
                        .scrollDisabled(placingSignature != nil)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .scrollDisabled(placingSignature != nil)
                .onChange(of: session.currentIndex) { _, _ in
                    // Swiping to a different page while the Adjust tool is
                    // still active (nothing stops that — unlike Sign
                    // placement, the pager isn't disabled for Adjust) needs
                    // to re-sync the live preview to the new page's own
                    // values, since `liveBrightness`/`liveContrast`/
                    // `adjustBaseImage` are shared state, not per-page.
                    if activeTool == .adjust {
                        loadAdjustPreview()
                    }
                }

                bottomBar
            }
        }
        .fullScreenCover(isPresented: $showOCRSheet) {
            OCRSheetContainer(
                page: session.current,
                onCopy: {
                    UIPasteboard.general.string = session.current.ocrText
                    toastCenter.show("Copied")
                },
                onDone: { showOCRSheet = false }
            )
            // A further-nested `.fullScreenCover` on top of EditFlowView's
            // own — needs its own toast overlay for the same reason
            // EditFlowView does (see the one at the bottom of this file).
            .toastOverlay(toastCenter)
        }
        .fullScreenCover(isPresented: $showCommentsPage) {
            CommentsPageView(
                comments: $session.comments,
                currentPageIndex: session.currentIndex,
                onDone: { showCommentsPage = false }
            )
        }
        .fullScreenCover(isPresented: $isDrawingSignature) {
            SignaturePadView(
                onCancel: {
                    isDrawingSignature = false
                    if placingSignature == nil { activeTool = nil }
                },
                onDone: { draft in
                    isDrawingSignature = false
                    placingSignature = Signature(
                        strokes: draft.strokes,
                        color: draft.color,
                        thickness: draft.thickness,
                        x: 0.28,
                        y: 0.5,
                        width: 0.4,
                        aspectRatio: draft.aspectRatio
                    )
                }
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(premiumManager: premiumManager) { outcome in
                showPaywall = false
                switch outcome {
                case .trialStarted:
                    toastCenter.show("Trial started \u{2014} enjoy Premium!")
                    resumePendingPremiumTool()
                case .subscribed:
                    toastCenter.show("Welcome to Premium!")
                    resumePendingPremiumTool()
                case .restored:
                    toastCenter.show("Purchases restored")
                case .notRestored:
                    toastCenter.show("No previous purchase found")
                case .dismissed:
                    activeTool = nil
                }
                pendingPremiumTool = nil
            }
        }
        .sheet(isPresented: $showSaveLimitPaywall) {
            PaywallView(
                premiumManager: premiumManager,
                reason: "You've reached the free plan's \(PremiumManager.freeDocumentLimit)-document limit"
            ) { outcome in
                showSaveLimitPaywall = false
                switch outcome {
                case .trialStarted:
                    toastCenter.show("Trial started \u{2014} enjoy Premium!")
                    performSave()
                case .subscribed:
                    toastCenter.show("Welcome to Premium!")
                    performSave()
                case .restored:
                    toastCenter.show("Purchases restored")
                    if premiumManager.isPremium { performSave() }
                case .notRestored:
                    toastCenter.show("No previous purchase found")
                case .dismissed:
                    break
                }
            }
        }
        .sheet(item: $saveLimitExportTarget) { target in
            ExportSheetView(document: target.document, pendingSave: target.pendingSave, premiumManager: premiumManager) {
                let tempImagePaths = target.document.orderedPages.flatMap { [$0.imagePath, $0.originalImagePath].compactMap { $0 } }
                for path in tempImagePaths { ImageStore.delete(path) }
                saveLimitExportTarget = nil
                onCancel()
            }
            .presentationDetents([.height(560)])
            .presentationDragIndicator(.visible)
        }
        .alert("Document limit reached", isPresented: $showSaveLimitAlert) {
            Button(premiumManager.hasUsedTrial ? "Upgrade to Premium" : "Start Free Trial") {
                showSaveLimitPaywall = true
            }
            Button("Export") {
                exportWithoutSaving()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Free plan is limited to \(PremiumManager.freeDocumentLimit) saved documents. Upgrade for unlimited storage, export this one without saving, or cancel.")
        }
        .alert("Delete this page?", isPresented: $showDeletePageConfirm) {
            Button("Delete", role: .destructive) { deleteCurrentPage() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        // EditFlowView is itself presented via `.fullScreenCover` from
        // RootView, a separate UIKit-hosted hierarchy that doesn't
        // composite with RootView's own `.toastOverlay` — so every toast
        // triggered from in here (Signature added, the premium-paywall
        // outcomes above) was silently invisible without its own overlay.
        .toastOverlay(toastCenter)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.system(size: 15))
                .foregroundColor(theme.ink2)

            Spacer()

            HStack(spacing: 10) {
                if session.pageCount > 1 {
                    Button {
                        session.goToPrevious()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(session.currentIndex == 0 ? theme.ink3 : theme.ink2)
                    }
                    .disabled(session.currentIndex == 0)
                }

                Text(session.pageLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.ink)

                if session.pageCount > 1 {
                    Button {
                        session.goToNext()
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundColor(session.currentIndex == session.pageCount - 1 ? theme.ink3 : theme.ink2)
                    }
                    .disabled(session.currentIndex == session.pageCount - 1)
                }

                Button {
                    showDeletePageConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(theme.ink2)
                }
                .padding(.leading, 4)
            }

            Spacer()

            // Re-editing an already-saved document (DESIGN_SPEC §4.4): this
            // is the same screen a fresh capture uses, just seeded from an
            // existing DocumentModel (`EditSession.load(from:)`) — the only
            // top-bar difference is this button, since there's no unsaved
            // "document" being created for the first time to announce.
            Button(session.existingDocument == nil ? "Save" : "Export", action: save)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(theme.bg)
    }

    // MARK: - Page card

    private func pageCard(for pageState: PageEditState) -> some View {
        // The Adjust preview state is shared across the whole flow, not
        // per-page, so it's only handed to the page actually being edited —
        // every other page in the pager falls back to its own already-
        // committed image untouched (see `PageEditorView.displayImage`).
        let isCurrent = pageState.id == session.current.id
        return PageEditorView(
            pageState: pageState,
            activeTool: activeTool,
            placingSignature: $placingSignature,
            adjustPreviewImage: isCurrent ? adjustBaseImage : nil,
            liveBrightness: liveBrightness,
            liveContrast: liveContrast
        )
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 4).fill(theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.line, lineWidth: 1))
        .paperShadow(theme)
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if let placing = placingSignature {
            signaturePlacementBar(placing)
        } else {
            VStack(spacing: 0) {
                if let hint = activeTool?.hint {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundColor(theme.ink2)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity)
                }

                if activeTool == .adjust {
                    adjustSliders
                }

                HStack(spacing: 8) {
                    ForEach(EditTool.allCases) { tool in
                        toolButton(tool)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 30)
                .padding(.top, activeTool == nil ? 12 : 0)
            }
            .background(theme.surface)
            .overlay(Divider().overlay(theme.line), alignment: .top)
        }
    }

    /// Brightness/Contrast sliders (DESIGN_SPEC §4.3 "Adjust tool"), shown
    /// above the tool row while Adjust is active. Dragging updates
    /// `liveBrightness`/`liveContrast` continuously for the live SwiftUI
    /// preview (see `PageEditorView`); releasing commits the real,
    /// precisely-computed pixels via `PageEditState.commitAdjustments`.
    private var adjustSliders: some View {
        VStack(spacing: 10) {
            adjustSlider(label: "Brightness", value: $liveBrightness, range: -0.3...0.3)
            adjustSlider(label: "Contrast", value: $liveContrast, range: 0.7...1.5)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func adjustSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(theme.ink2)
                .frame(width: 74, alignment: .leading)
            Slider(value: value, in: range) { isEditing in
                if !isEditing {
                    session.current.commitAdjustments(brightness: liveBrightness, contrast: liveContrast)
                }
            }
            .tint(theme.accent)
        }
    }

    private func toolButton(_ tool: EditTool) -> some View {
        let isActive = activeTool == tool
        let showsProBadge = (tool == .sign || tool == .ocr) && !premiumManager.isPremium
        return Button {
            selectTool(tool)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 20))
                Text(tool.label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isActive ? theme.accent : theme.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(isActive ? theme.accentSoft : Color.clear))
            .overlay(alignment: .topTrailing) {
                if showsProBadge {
                    Text("PRO")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.accent))
                        .offset(x: -4, y: 4)
                }
            }
        }
    }

    private func signaturePlacementBar(_ signature: Signature) -> some View {
        VStack(spacing: 12) {
            Text("Drag to position \u{00b7} pull the corner to resize")
                .font(.system(size: 12))
                .foregroundColor(theme.ink2)

            HStack(spacing: 10) {
                ForEach(Theme.SignatureColor.allCases) { option in
                    Button {
                        placingSignature?.color = option
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(signature.color == option ? theme.accent : theme.line, lineWidth: signature.color == option ? 2 : 1))
                    }
                }

                Spacer()

                Button("Redraw") {
                    placingSignature = nil
                    isDrawingSignature = true
                }
                .font(.system(size: 13))
                .foregroundColor(theme.ink2)

                Button("Done") {
                    commitSignature()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.accent))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 40)
        .background(theme.surface)
        .overlay(Divider().overlay(theme.line), alignment: .top)
    }

    // MARK: - Actions

    private func selectTool(_ tool: EditTool) {
        if activeTool == .crop, tool != .crop {
            session.current.commitCropIfNeeded()
        }
        if activeTool == tool {
            activeTool = nil
            return
        }
        // Sign and Text recognition are premium-only (DESIGN_SPEC §4.3/§7)
        // — gate before touching `activeTool`/opening the drawing pad or
        // the recognized-text page, and re-check on every tap (rather than
        // trusting a possibly-stale `isPremium`) since a trial started
        // elsewhere in the app could have expired since this screen last
        // refreshed it. Comment isn't gated — it doesn't touch OCR.
        if tool == .sign || tool == .ocr {
            premiumManager.refresh()
            guard premiumManager.isPremium else {
                pendingPremiumTool = tool
                showPaywall = true
                return
            }
        }
        activeTool = tool
        switch tool {
        case .crop:
            break
        case .adjust:
            loadAdjustPreview()
        case .comment:
            showCommentsPage = true
        case .ocr:
            showOCRSheet = true
            runOCRIfNeeded()
        case .sign:
            isDrawingSignature = true
        }
    }

    /// Resumes whichever premium-gated tool (`.sign` or `.ocr`) sent the
    /// user to the paywall, once a trial/subscription just made them
    /// premium — so completing checkout drops straight back into the tool
    /// they originally tapped instead of requiring a second tap.
    private func resumePendingPremiumTool() {
        if pendingPremiumTool == .ocr {
            activeTool = .ocr
            showOCRSheet = true
            runOCRIfNeeded()
        } else {
            isDrawingSignature = true
        }
    }

    /// Seeds the Adjust tool's live sliders from the current page's
    /// committed values and (re)computes `adjustBaseImage` — the crop +
    /// filter result with brightness/contrast still neutral — so the live
    /// preview has a clean base to apply `.brightness()/.contrast()` on
    /// top of. Called when Adjust is selected and again if the user swipes
    /// to a different page while it's still active.
    private func loadAdjustPreview() {
        let page = session.current
        liveBrightness = page.brightness
        liveContrast = page.contrast
        adjustBaseImage = nil
        DocumentEnhancer.applyAsync(page.filter, to: page.recroppedImage) { filtered in
            guard page === session.current else { return }
            adjustBaseImage = filtered
        }
    }

    private func runOCRIfNeeded() {
        let page = session.current
        guard page.ocrText == nil, !page.isRecognizingText else { return }
        page.isRecognizingText = true
        Task {
            let result = await OCRService.recognize(page.image)
            page.ocrText = result.fullText
            page.ocrLines = result.lines
            page.isRecognizingText = false
        }
    }

    private func commitSignature() {
        guard let signature = placingSignature else { return }
        session.current.signature = signature
        placingSignature = nil
        activeTool = nil
        toastCenter.show("Signature added")
    }

    /// Builds (or updates, for a re-edit) the `DocumentModel` for the
    /// current session's pages, writing page images to disk — but never
    /// touching `modelContext`. Shared by `performSave()` (which then
    /// inserts/persists it) and `exportWithoutSaving()` (which hands it
    /// straight to export, unpersisted).
    private func buildDocument() -> DocumentModel {
        session.current.commitCropIfNeeded()

        let document = session.existingDocument ?? DocumentModel(name: session.documentName)

        for pageState in session.pages {
            let imageFilename = ImageStore.save(pageState.image)
            let originalFilename = ImageStore.save(pageState.originalImage)

            let pageModel: PageModel
            if let existingID = pageState.existingPageID,
               let match = document.pages.first(where: { $0.id == existingID }) {
                pageModel = match
                pageModel.imagePath = imageFilename
                pageModel.originalImagePath = originalFilename
            } else {
                pageModel = PageModel(order: pageState.order, imagePath: imageFilename, originalImagePath: originalFilename)
                // Setting the inverse side is enough — SwiftData automatically
                // keeps `document.pages` in sync for a `@Relationship(inverse:)`
                // pair. Also appending here would insert `pageModel` twice.
                pageModel.document = document
            }
            pageModel.order = pageState.order
            pageModel.ocrText = pageState.ocrText
            pageModel.ocrLines = pageState.ocrLines
            pageModel.highlightRegions = pageState.highlightRegions
            pageModel.signature = pageState.signature
            pageModel.filter = pageState.filter
            pageModel.brightness = pageState.brightness
            pageModel.contrast = pageState.contrast
        }

        // Comments (DESIGN_SPEC §4.3 "Comment tool") — buffered in
        // `session.comments` alongside already-loaded ones (see
        // `EditSession.load(from:)`), written out the same way a fresh
        // page becomes a `PageModel` above: only the ones without an
        // `existingCommentID` are genuinely new here, since a loaded
        // comment's `CommentModel` already exists on `document.comments`.
        for draft in session.comments where draft.existingCommentID == nil {
            let comment = CommentModel(text: draft.text, createdAt: draft.createdAt, pageIndex: draft.pageIndex)
            comment.document = document
        }

        return document
    }

    /// Entry point for the Save button — gates brand-new documents behind
    /// the free-tier save limit (DESIGN_SPEC §5 "limited document storage")
    /// before touching `modelContext`; re-saving an existing document always
    /// goes straight through.
    private func save() {
        if session.existingDocument == nil, !premiumManager.canCreateNewDocument(currentCount: documentCount) {
            showSaveLimitAlert = true
            return
        }
        performSave()
    }

    private func performSave() {
        let document = buildDocument()
        if session.existingDocument == nil {
            modelContext.insert(document)
        } else {
            removeDeletedPages(from: document)
        }
        try? modelContext.save()
        onSaved(document)
    }

    /// Deletes any already-persisted page that's no longer in the current
    /// session (DESIGN_SPEC §4.3 "delete a scanned page") — `buildDocument()`
    /// only creates/updates pages present in `session.pages`, it never
    /// removes ones dropped from it, and SwiftData's cascade delete rule
    /// only fires when the *document* itself is deleted, not when a page
    /// is removed from its `pages` array. Also removes the page's on-disk
    /// image files, which nothing else would clean up otherwise.
    private func removeDeletedPages(from document: DocumentModel) {
        let keptIDs = Set(session.pages.compactMap(\.existingPageID))
        for pageModel in document.pages where !keptIDs.contains(pageModel.id) {
            ImageStore.delete(pageModel.imagePath)
            ImageStore.delete(pageModel.originalImagePath)
            modelContext.delete(pageModel)
        }
    }

    /// Removes the currently-viewed page from the session (DESIGN_SPEC
    /// §4.3 "delete a scanned page"). Deleting the last remaining page
    /// leaves nothing to edit, so that closes the whole Edit flow instead
    /// of leaving an empty editor on screen.
    private func deleteCurrentPage() {
        let wasLastPage = session.pageCount <= 1
        session.deletePage(at: session.currentIndex)
        if wasLastPage {
            onCancel()
        }
    }

    /// Opens the standard Export sheet (PDF/JPG choice, PDF password
    /// protection) over the current pages — the document is never inserted
    /// into `modelContext`, so nothing is added to the library regardless
    /// of what's exported. Cleanup of the temporary page images built for
    /// this happens once the sheet is dismissed (see `saveLimitExportTarget`'s
    /// `.sheet`), not here, since the user may export more than one format
    /// before finishing.
    private func exportWithoutSaving() {
        let document = buildDocument()
        saveLimitExportTarget = ExportTarget(document: document, pendingSave: false)
    }
}
