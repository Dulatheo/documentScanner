import SwiftData
import SwiftUI

/// The per-page editor (DESIGN_SPEC §4.3): Cancel/"Page X of Y"/Save top
/// bar, the page on a paper card with the active tool's overlay, a
/// contextual hint, and the four-tool bottom bar.
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var activeTool: EditTool?
    @State private var showOCRSheet = false
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

                bottomBar
            }
        }
        .sheet(isPresented: $showOCRSheet) {
            OCRSheetContainer(
                page: session.current,
                onCopy: {
                    UIPasteboard.general.string = session.current.ocrText
                    toastCenter.show("Copied")
                },
                onKeepSearchable: { showOCRSheet = false },
                onDone: { showOCRSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
                    isDrawingSignature = true
                case .subscribed:
                    toastCenter.show("Welcome to Premium!")
                    isDrawingSignature = true
                case .restored:
                    toastCenter.show("Purchases restored")
                case .notRestored:
                    toastCenter.show("No previous purchase found")
                case .dismissed:
                    activeTool = nil
                }
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
            .presentationDetents([.height(380)])
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
            }

            Spacer()

            Button("Save", action: save)
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
        PageEditorView(pageState: pageState, activeTool: activeTool, placingSignature: $placingSignature)
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

    private func toolButton(_ tool: EditTool) -> some View {
        let isActive = activeTool == tool
        let showsProBadge = tool == .sign && !premiumManager.isPremium
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
                            .fill(option.color(colorScheme))
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
        // Sign is premium-only (DESIGN_SPEC §4.3/§7) — gate before touching
        // `activeTool`/opening the drawing pad, and re-check on every tap
        // (rather than trusting a possibly-stale `isPremium`) since a trial
        // started elsewhere in the app could have expired since this screen
        // last refreshed it.
        if tool == .sign {
            premiumManager.refresh()
            guard premiumManager.isPremium else {
                showPaywall = true
                return
            }
        }
        activeTool = tool
        switch tool {
        case .crop:
            break
        case .highlight:
            runOCRIfNeeded()
        case .ocr:
            showOCRSheet = true
            runOCRIfNeeded()
        case .sign:
            isDrawingSignature = true
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
        }
        try? modelContext.save()
        onSaved(document)
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
