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
    @ObservedObject var premiumManager: PremiumManager

    @Environment(\.theme) private var theme
    @Environment(\.appActions) private var actions

    /// Surfaces the free-tier document cap (DESIGN_SPEC §5 "unlimited
    /// scanning") before the user hits it, rather than only ever explaining
    /// itself via the paywall that appears once they're already blocked.
    private var subtitle: String {
        if premiumManager.isPremium {
            return documents.isEmpty ? "Nothing saved yet" : (documents.count == 1 ? "1 document" : "\(documents.count) documents")
        }
        if documents.isEmpty {
            return "Nothing saved yet \u{00b7} \(PremiumManager.freeDocumentLimit) free documents"
        }
        return "\(documents.count) of \(PremiumManager.freeDocumentLimit) free documents \u{2014} Premium for unlimited"
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Documents")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.5)
                .foregroundColor(theme.ink)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(theme.ink3)
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
