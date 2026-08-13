import SwiftData
import SwiftUI

/// The per-page editor (DESIGN_SPEC §4.3): Cancel/"Page X of Y"/Save top
/// bar, the page on a paper card with the active tool's overlay, a
/// contextual hint, and the four-tool bottom bar.
struct EditFlowView: View {
    @ObservedObject var session: EditSession
    var onCancel: () -> Void
    var onSaved: (DocumentModel) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var toastCenter: ToastCenter

    @State private var activeTool: EditTool?
    @State private var showOCRSheet = false
    @State private var isDrawingSignature = false
    @State private var placingSignature: Signature?

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().overlay(theme.line)

                ScrollView {
                    pageCard
                        .padding(.horizontal, 26)
                        .padding(.vertical, 22)
                }

                bottomBar
            }
        }
        .sheet(isPresented: $showOCRSheet) {
            OCRSheetView(
                isBusy: session.current.isRecognizingText,
                text: session.current.ocrText,
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

    private var pageCard: some View {
        PageEditorView(pageState: session.current, activeTool: activeTool, placingSignature: $placingSignature)
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

    private func save() {
        session.current.commitCropIfNeeded()

        let document = session.existingDocument ?? DocumentModel(name: session.documentName)
        if session.existingDocument == nil {
            modelContext.insert(document)
        }

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
                pageModel.document = document
                document.pages.append(pageModel)
            }
            pageModel.order = pageState.order
            pageModel.ocrText = pageState.ocrText
            pageModel.ocrLines = pageState.ocrLines
            pageModel.highlightRegions = pageState.highlightRegions
            pageModel.signature = pageState.signature
        }

        try? modelContext.save()
        onSaved(document)
    }
}
