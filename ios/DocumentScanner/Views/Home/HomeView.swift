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
    @ObservedObject var premiumManager: PremiumManager
    @ObservedObject var toastCenter: ToastCenter

    @Environment(\.theme) private var theme
    @Environment(\.appActions) private var actions
    @State private var showPaywall = false
    @State private var pendingDeleteDocument: DocumentModel?

    /// Surfaces the free-tier document cap (DESIGN_SPEC §5 "limited document
    /// storage") before the user hits it, rather than only ever explaining
    /// itself via the paywall that appears once they're already blocked.
    /// Only the "Premium for unlimited" portion (see `header`) is styled
    /// and tappable — this is the plain lead-in text before it, so it's
    /// empty once premium (nothing left to show) or when there's nothing
    /// to attach the link to yet (the empty-library case has no natural
    /// place for it).
    private var subtitlePrefix: String {
        if premiumManager.isPremium {
            return documents.isEmpty ? "Nothing saved yet" : (documents.count == 1 ? "1 document" : "\(documents.count) documents")
        }
        if documents.isEmpty {
            return "Nothing saved yet \u{00b7} \(PremiumManager.freeDocumentLimit) free documents"
        }
        return "\(documents.count) of \(PremiumManager.freeDocumentLimit) free documents \u{2014} "
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
                    toastCenter.show("Trial started \u{2014} enjoy Premium!")
                case .subscribed:
                    toastCenter.show("Welcome to Premium!")
                case .restored:
                    toastCenter.show("Purchases restored")
                case .notRestored:
                    toastCenter.show("No previous purchase found")
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
    }

    private var header: some View {
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
                .accessibilityLabel("Import from Photos")
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
            .accessibilityLabel("Scan a document")
            // Zoom-transition source (DESIGN_SPEC §4.1/§4.2): Camera is
            // presented from `RootView` as a same-hierarchy overlay tagged
            // with this same id, so it animates open from this button's own
            // frame instead of a plain `.fullScreenCover` slide-up.
            .matchedGeometryEffect(id: "cameraZoom", in: zoomNamespace)
        }
        .padding(.bottom, 30)
    }
}
