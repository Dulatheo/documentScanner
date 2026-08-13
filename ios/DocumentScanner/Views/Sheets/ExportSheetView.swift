import SwiftUI

private struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Export sheet (DESIGN_SPEC §4.5): choose PDF (multi-page, searchable
/// text layer when OCR has run) or JPG (one file per page), then hand off
/// to the native share surface (§4.6).
struct ExportSheetView: View {
    let document: DocumentModel
    let pendingSave: Bool
    var onFinish: () -> Void

    @Environment(\.theme) private var theme
    @State private var activeShare: ShareItem?
    @State private var isExporting = false

    private var subtitle: String {
        pendingSave ? "Saved to Documents \u{00b7} choose a format to share" : "Choose a format to share"
    }

    private var dismissLabel: String { pendingSave ? "Close" : "Cancel" }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Export document")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(theme.ink3)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            VStack(spacing: 10) {
                exportOption(badge: "PDF", title: "PDF document", subtitle: "Searchable text, all pages") {
                    exportPDF()
                }
                exportOption(badge: "JPG", title: "JPG images", subtitle: "One image per page") {
                    exportJPGs()
                }
            }

            Button(dismissLabel, action: onFinish)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).stroke(theme.line, lineWidth: 1))
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .sheet(item: $activeShare) { item in
            ShareSheet(items: item.urls, onDismiss: onFinish)
        }
    }

    private func exportOption(badge: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(theme.accentSoft))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(theme.ink3)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.line, lineWidth: 1))
        }
        .disabled(isExporting)
    }

    private func exportPDF() {
        isExporting = true
        Task {
            let url = PDFExportService.makePDF(for: document)
            await MainActor.run {
                isExporting = false
                activeShare = ShareItem(urls: [url])
            }
        }
    }

    private func exportJPGs() {
        isExporting = true
        Task {
            let urls = JPGExportService.makeJPGs(for: document)
            await MainActor.run {
                isExporting = false
                activeShare = ShareItem(urls: urls)
            }
        }
    }
}
