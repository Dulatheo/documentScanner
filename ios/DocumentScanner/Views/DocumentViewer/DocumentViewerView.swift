import SwiftData
import SwiftUI
import UIKit

/// Document viewer (DESIGN_SPEC §4.4): back-to-Documents header, the
/// page(s) with any committed highlights/signature, a Comments section,
/// and a Comment/Export bottom bar.
struct DocumentViewerView: View {
    @Bindable var document: DocumentModel
    /// Shared with `RootView`/`HomeView` so `matchedGeometryEffect` can
    /// animate this screen's root from the tapped document card's frame —
    /// see the iOS zoom-transition implementation note in DESIGN_SPEC §4.2.
    let zoomNamespace: Namespace.ID
    /// Zooms back out to the document card's frame and dismisses this
    /// overlay. Replaces `\.dismiss`: this view is now a same-hierarchy
    /// overlay presented by `RootView` (`if let viewingDocument { ... }`),
    /// not a pushed `NavigationLink` destination, so there's no
    /// `NavigationStack` to pop.
    let onBack: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.appActions) private var actions
    @Environment(\.modelContext) private var modelContext

    @State private var showCommentSheet = false

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Divider().overlay(theme.line)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(document.orderedPages) { page in
                            pageView(page)
                        }

                        if !document.comments.isEmpty {
                            commentsSection
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 40)
                }

                bottomBar
            }
        }
        .matchedGeometryEffect(id: documentZoomID(for: document), in: zoomNamespace)
        .sheet(isPresented: $showCommentSheet) {
            CommentSheetView { text in
                let comment = CommentModel(text: text, pageIndex: 0)
                // Setting the inverse side is enough — SwiftData automatically
                // keeps `document.comments` in sync for a `@Relationship(inverse:)`
                // pair. Also appending here would insert `comment` twice.
                comment.document = document
                try? modelContext.save()
                showCommentSheet = false
            } onCancel: {
                showCommentSheet = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                onBack()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Documents")
                        .font(.system(size: 15))
                }
                .foregroundColor(theme.accent)
            }

            Spacer()

            Text(document.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.ink)
                .lineLimit(1)

            Spacer()

            Color.clear.frame(width: 56, height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(theme.bg)
    }

    private func pageView(_ page: PageModel) -> some View {
        PageCompositeView(
            image: ImageStore.load(page.imagePath) ?? UIImage(),
            highlightRegions: page.highlightRegions,
            signature: page.signature
        )
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 4).fill(theme.paper))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.line, lineWidth: 1))
        .paperShadow(theme)
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMMENTS")
                .font(.system(size: 12, weight: .medium))
                .tracking(0.5)
                .foregroundColor(theme.ink3)

            ForEach(document.sortedComments) { comment in
                VStack(alignment: .leading, spacing: 5) {
                    Text(comment.text)
                        .font(.system(size: 13))
                        .foregroundColor(theme.ink)
                        .lineSpacing(3)
                    Text(comment.metaLabel())
                        .font(.system(size: 11))
                        .foregroundColor(theme.ink3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))
            }
        }
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            bottomButton(systemImage: "bubble.left", label: "Comment") {
                showCommentSheet = true
            }
            bottomButton(systemImage: "square.and.arrow.up", label: "Export") {
                actions.openExport(document, false)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 40)
        .background(theme.surface)
        .overlay(Divider().overlay(theme.line), alignment: .top)
    }

    private func bottomButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(theme.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}
