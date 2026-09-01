import SwiftUI

private struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Export sheet (DESIGN_SPEC §4.5): choose PDF (multi-page, searchable
/// text layer when OCR has run), JPG (one file per page), or one of three
/// Premium Office formats — DOCX/XLSX/PPTX (§5/§9) — then hand off to the
/// native share surface (§4.6). PDF can optionally be password-protected
/// (also Premium) via the row's trailing lock button; tapping the rest of
/// the row still exports unprotected, same as before that feature existed.
struct ExportSheetView: View {
    let document: DocumentModel
    let pendingSave: Bool
    @ObservedObject var premiumManager: PremiumManager
    var onFinish: () -> Void

    @Environment(\.theme) private var theme
    @State private var activeShare: ShareItem?
    @State private var isExporting = false
    @State private var showPasswordPrompt = false
    @State private var passwordInput = ""
    @State private var showPaywall = false
    @State private var showPasswordSuggestion = false
    @State private var showOfficePaywall = false
    /// The Office-format export deferred while `showOfficePaywall` is up —
    /// run once the user actually gets premium, so completing a trial or
    /// subscription proceeds straight into the export they originally
    /// tapped, rather than requiring a second tap.
    @State private var pendingOfficeExport: (() -> Void)?

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

            ScrollView {
                VStack(spacing: 10) {
                    pdfOption
                    exportOption(badge: "JPG", title: "JPG images", subtitle: "One image per page") {
                        exportJPGs()
                    }
                    officeExportOption(badge: "DOC", title: "Word document", subtitle: "Recognized text, all pages") {
                        exportDocx()
                    }
                    officeExportOption(badge: "XLS", title: "Excel spreadsheet", subtitle: "One row per line of text") {
                        exportXlsx()
                    }
                    officeExportOption(badge: "PPT", title: "PowerPoint slides", subtitle: "One slide per page") {
                        exportPptx()
                    }
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
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                premiumManager: premiumManager,
                reason: "Password-protecting PDFs is a Premium feature"
            ) { outcome in
                showPaywall = false
                switch outcome {
                case .trialStarted, .subscribed:
                    passwordInput = ""
                    showPasswordPrompt = true
                case .restored, .notRestored, .dismissed:
                    break
                }
            }
        }
        .alert("Protect PDF", isPresented: $showPasswordPrompt) {
            SecureField("Password", text: $passwordInput)
            Button("Export") { exportPDF(password: passwordInput) }
            Button("Cancel", role: .cancel) { passwordInput = "" }
        } message: {
            Text("Anyone opening this PDF will need this password.")
        }
        .alert("Protect this PDF?", isPresented: $showPasswordSuggestion) {
            Button("Add Password") { showPaywall = true }
            Button("Export Without Password", role: .cancel) { exportPDF(password: nil) }
        } message: {
            Text("Add a password so only people who have it can open this file. Available with Premium.")
        }
        .sheet(isPresented: $showOfficePaywall) {
            PaywallView(
                premiumManager: premiumManager,
                reason: "Office format export is a Premium feature"
            ) { outcome in
                showOfficePaywall = false
                switch outcome {
                case .trialStarted, .subscribed:
                    pendingOfficeExport?()
                case .restored:
                    if premiumManager.isPremium { pendingOfficeExport?() }
                case .notRestored, .dismissed:
                    break
                }
                pendingOfficeExport = nil
            }
        }
    }

    /// The PDF row is its own layout (rather than reusing `exportOption`)
    /// since it has a second, independently-tappable lock button — the row
    /// uses `.onTapGesture` for "export unprotected" instead of wrapping the
    /// whole thing in a `Button`, so the nested lock `Button` isn't fighting
    /// an outer one for the same touch.
    private var pdfOption: some View {
        HStack(spacing: 13) {
            Text("PDF")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(theme.accentSoft))

            VStack(alignment: .leading, spacing: 2) {
                Text("PDF document")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(theme.ink)
                Text("Searchable text, all pages")
                    .font(.system(size: 11))
                    .foregroundColor(theme.ink3)
            }
            Spacer()

            Button {
                if premiumManager.isPremium {
                    passwordInput = ""
                    showPasswordPrompt = true
                } else {
                    showPaywall = true
                }
            } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.ink2)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(theme.bg))
                    .overlay(alignment: .topTrailing) {
                        if !premiumManager.isPremium {
                            Text("PRO")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(theme.accent))
                                .offset(x: 4, y: -2)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isExporting else { return }
            if premiumManager.isPremium {
                exportPDF(password: nil)
            } else {
                showPasswordSuggestion = true
            }
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

    /// Like `exportOption`, but gated behind Premium with a **PRO** badge
    /// on the icon — used for the Office-format rows. Tapping it while not
    /// premium defers `action` and shows the paywall instead of running it.
    private func officeExportOption(badge: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            if premiumManager.isPremium {
                action()
            } else {
                pendingOfficeExport = action
                showOfficePaywall = true
            }
        } label: {
            HStack(spacing: 13) {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(theme.accentSoft))
                    .overlay(alignment: .topTrailing) {
                        if !premiumManager.isPremium {
                            Text("PRO")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(theme.accent))
                                .offset(x: 8, y: -6)
                        }
                    }

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

    private func exportPDF(password: String?) {
        isExporting = true
        let trimmed = password?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePassword = (trimmed?.isEmpty ?? true) ? nil : trimmed
        Task {
            let url = PDFExportService.makePDF(for: document, password: effectivePassword)
            await MainActor.run {
                isExporting = false
                passwordInput = ""
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

    private func exportDocx() {
        isExporting = true
        Task {
            let url = await DocxExportService.makeDocx(for: document)
            await MainActor.run {
                isExporting = false
                activeShare = ShareItem(urls: [url])
            }
        }
    }

    private func exportXlsx() {
        isExporting = true
        Task {
            let url = await XlsxExportService.makeXlsx(for: document)
            await MainActor.run {
                isExporting = false
                activeShare = ShareItem(urls: [url])
            }
        }
    }

    private func exportPptx() {
        isExporting = true
        Task {
            let url = PptxExportService.makePptx(for: document)
            await MainActor.run {
                isExporting = false
                activeShare = ShareItem(urls: [url])
            }
        }
    }
}
