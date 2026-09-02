import SwiftUI

/// Documents home (DESIGN_SPEC §4.1): grid of scanned documents, empty
/// state, and floating scan button.
struct HomeView: View {
    let documents: [DocumentModel]
    /// Shared with `RootView`, which owns the Camera/Document-Viewer overlay
    /// state, so `matchedGeometryEffect` can animate the scan button and
    /// tapped document card into their respective destinations — see the
    /// iOS zoom-transition implementation note in DESIGN_SPEC §4.2.
    let zoomNamespace: Namespace.ID
    /// Zoom-transitions into the Document Viewer from the tapped card's own
    /// frame (DESIGN_SPEC §4.1) — replaces `NavigationLink`, which would
    /// push into a separate view hierarchy `matchedGeometryEffect` can't
    /// animate across.
    let onSelectDocument: (DocumentModel) -> Void
    /// Deletes a saved document (DESIGN_SPEC §4.1 "delete a saved
    /// document") — image files and the SwiftData record alike; `HomeView`
    /// only drives the confirmation UI.
    let onDeleteDocument: (DocumentModel) -> Void
    /// Renames a saved document in place (DESIGN_SPEC §4.1 "rename a saved
    /// document").
    let onRenameDocument: (DocumentModel, String) -> Void
    @ObservedObject var premiumManager: PremiumManager
    @ObservedObject var toastCenter: ToastCenter

    @Environment(\.theme) private var theme
    @Environment(\.appActions) private var actions
    @State private var showPaywall = false
    @State private var pendingDeleteDocument: DocumentModel?
    @State private var pendingRenameDocument: DocumentModel?
    @State private var renameInput = ""

    /// Surfaces the free-tier document cap (DESIGN_SPEC §5 "limited document
    /// storage") before the user hits it, rather than only ever explaining
    /// itself via the paywall that appears once they're already blocked.
    /// Only the "Premium for unlimited" portion (see `header`) is styled
    /// and tappable — this is the plain lead-in text before it, so it's
    /// empty once premium (nothing left to show) or when there's nothing
    /// to attach the link to yet (the empty-library case has no natural
    /// place for it).
    private var subtitlePrefix: String {
        // `String(localized:)`, not a plain literal/interpolation — this is
        // a `Text(subtitlePrefix)` call (verbatim, unlocalized) since
        // `subtitlePrefix`'s type is `String`; the catalog lookup has to
        // happen here, when each branch's value is produced.
        if premiumManager.isPremium {
            if documents.isEmpty { return String(localized: "Nothing saved yet") }
            return documents.count == 1
                ? String(localized: "1 document")
                : String(localized: "\(documents.count) documents")
        }
        if documents.isEmpty {
            return String(localized: "Nothing saved yet \u{00b7} \(PremiumManager.freeDocumentLimit) free documents")
        }
        return String(localized: "\(documents.count) of \(PremiumManager.freeDocumentLimit) free documents \u{2014} ")
    }

    private var showPremiumLink: Bool {
        !premiumManager.isPremium && !documents.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if documents.isEmpty {
                        EmptyStateView(onScan: actions.startCamera)
                            .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                            ForEach(documents) { document in
                                Button {
                                    onSelectDocument(document)
                                } label: {
                                    DocumentCardView(document: document)
                                }
                                .buttonStyle(.plain)
                                .matchedGeometryEffect(id: documentZoomID(for: document), in: zoomNamespace)
                                .contextMenu {
                                    Button {
                                        renameInput = document.name
                                        pendingRenameDocument = document
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        pendingDeleteDocument = document
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 150)
            }

            bottomFade
            scanButton
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(premiumManager: premiumManager) { outcome in
                showPaywall = false
                switch outcome {
                case .trialStarted:
                    toastCenter.show(String(localized: "Trial started \u{2014} enjoy Premium!"))
                case .subscribed:
                    toastCenter.show(String(localized: "Welcome to Premium!"))
                case .restored:
                    toastCenter.show(String(localized: "Purchases restored"))
                case .notRestored:
                    toastCenter.show(String(localized: "No previous purchase found"))
                case .dismissed:
                    break
                }
            }
        }
        .alert(
            "Delete \u{201c}\(pendingDeleteDocument?.name ?? "")\u{201d}?",
            isPresented: Binding(
                get: { pendingDeleteDocument != nil },
                set: { if !$0 { pendingDeleteDocument = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let document = pendingDeleteDocument {
                    onDeleteDocument(document)
                }
                pendingDeleteDocument = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteDocument = nil }
        } message: {
            Text("This can't be undone.")
        }
        .alert(
            "Rename document",
            isPresented: Binding(
                get: { pendingRenameDocument != nil },
                set: { if !$0 { pendingRenameDocument = nil } }
            )
        ) {
            TextField("Document name", text: $renameInput)
            Button("Save") {
                if let document = pendingRenameDocument {
                    let trimmed = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onRenameDocument(document, trimmed)
                    }
                }
                pendingRenameDocument = nil
            }
            Button("Cancel", role: .cancel) { pendingRenameDocument = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Documents")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(theme.ink)
                HStack(spacing: 0) {
                    Text(subtitlePrefix)
                        .font(.system(size: 13))
                        .foregroundColor(theme.ink3)
                    if showPremiumLink {
                        Text("Premium for unlimited")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.accent)
                            .underline()
                            .onTapGesture { showPaywall = true }
                    }
                }
            }
            Spacer()
            proBadge
                .padding(.top, 4)
        }
    }

    /// Top-right entry point into Premium (DESIGN_SPEC §5) — always visible
    /// on Home, unlike the inline "Premium for unlimited" subtitle link
    /// above, which only shows once the free-tier document limit is worth
    /// mentioning. A free user taps it to open the paywall (same one
    /// limit/tool gating opens); once subscribed it becomes a plain,
    /// non-interactive status pill — `PaywallView` has no "already premium"
    /// state to show, so tapping it again would have nothing useful to do.
    private var proBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("PRO")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundColor(premiumManager.isPremium ? theme.accent : .white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(premiumManager.isPremium ? theme.accentSoft : theme.accent))
        .onTapGesture {
            if !premiumManager.isPremium { showPaywall = true }
        }
    }

    private var bottomFade: some View {
        LinearGradient(colors: [theme.bg.opacity(0), theme.bg], startPoint: .top, endPoint: .bottom)
            .frame(height: 120)
            .allowsHitTesting(false)
    }

    private var scanButton: some View {
        VStack(spacing: 12) {
            if !documents.isEmpty {
                Button {
                    actions.startPhotoImport()
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(theme.ink2)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(theme.surface))
                        .overlay(Circle().stroke(theme.line, lineWidth: 1))
                }
                // `Text(...)`, not a bare literal — `accessibilityLabel`
                // has both a `Text`-taking overload (localizes, like
                // `Text(_:)` does) and a generic `StringProtocol` one
                // (verbatim); forcing `Text` here is unambiguous, where a
                // bare literal argument risks Swift picking either.
                .accessibilityLabel(Text("Import from Photos"))
            }
            Button {
                actions.startCamera()
            } label: {
                Image(systemName: "viewfinder")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(theme.accent))
                    .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 6)
            }
            .accessibilityLabel(Text("Scan a document"))
            // Zoom-transition source (DESIGN_SPEC §4.1/§4.2): Camera is
            // presented from `RootView` as a same-hierarchy overlay tagged
            // with this same id, so it animates open from this button's own
            // frame instead of a plain `.fullScreenCover` slide-up.
            .matchedGeometryEffect(id: "cameraZoom", in: zoomNamespace)
        }
        .padding(.bottom, 30)
    }
}
