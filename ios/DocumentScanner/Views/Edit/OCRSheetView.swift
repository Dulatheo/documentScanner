import SwiftUI

/// Wraps `OCRSheetView` with its own subscription to the current page's
/// `PageEditState`. `EditFlowView` only observes `EditSession` (not the
/// nested `PageEditState`), so a background OCR run flipping
/// `isRecognizingText`/`ocrText` wouldn't otherwise trigger the `.sheet`
/// content closure to re-evaluate — this view's `@ObservedObject` gives it
/// an independent, live subscription to those changes.
struct OCRSheetContainer: View {
    @ObservedObject var page: PageEditState
    var onCopy: () -> Void
    var onDone: () -> Void

    var body: some View {
        OCRSheetView(
            isBusy: page.isRecognizingText,
            text: page.ocrText,
            onCopy: onCopy,
            onDone: onDone
        )
    }
}

/// Full-screen page for the Text (OCR) tool (DESIGN_SPEC §4.3, Premium —
/// see §5/§7): "Reading page…" while busy, then the recognized text with a
/// **Copy All** action. A full page rather than a bottom sheet gives the
/// text room to breathe and makes it selectable — a cramped, fixed-height
/// sheet was awkward to read and copy from on a page with more than a few
/// lines. (No separate "Keep as searchable" action: recognized text is
/// already embedded as the PDF's invisible text layer automatically
/// whenever OCR has run on a page, regardless of what happens in this
/// view — the button used to exist but did nothing but close the screen,
/// same as Done.)
struct OCRSheetView: View {
    let isBusy: Bool
    let text: String?
    let onCopy: () -> Void
    let onDone: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recognized text")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.ink)
                Spacer()
                Button("Done", action: onDone)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.ink2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider().overlay(theme.line)

            if isBusy {
                Spacer()
                Text("Reading page\u{2026}")
                    .font(.system(size: 14))
                    .foregroundColor(theme.ink2)
                Spacer()
            } else {
                ScrollView {
                    // `.textSelection(.enabled)` lets the user drag out and
                    // copy just part of the text with the system's own
                    // selection UI, alongside "Copy All" below for the
                    // common case of wanting the whole page at once.
                    Text(text ?? "")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(theme.ink)
                        .lineSpacing(7)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }

                Button(action: onCopy) {
                    Text("Copy All")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(theme.accent))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}
