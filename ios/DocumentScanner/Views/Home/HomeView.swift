import SwiftUI

/// Documents home (DESIGN_SPEC §4.1): grid of scanned documents, empty
/// state, floating scan button, and a lightweight local search-as-you-type
/// filter over document names once at least one document exists.
struct HomeView: View {
    let documents: [DocumentModel]

    @Environment(\.theme) private var theme
    @Environment(\.appActions) private var actions

    @State private var isSearching = false
    @State private var query = ""

    private var filteredDocuments: [DocumentModel] {
        guard isSearching, !query.isEmpty else { return documents }
        return documents.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var subtitle: String {
        documents.isEmpty ? "Nothing saved yet" : (documents.count == 1 ? "1 document" : "\(documents.count) documents")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    if isSearching {
                        searchField
                    }

                    if documents.isEmpty {
                        EmptyStateView(onScan: actions.startCamera)
                            .padding(.top, 60)
                    } else if filteredDocuments.isEmpty {
                        Text("No documents match \u{201c}\(query)\u{201d}")
                            .font(.system(size: 14))
                            .foregroundColor(theme.ink2)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                            ForEach(filteredDocuments) { document in
                                NavigationLink(value: document) {
                                    DocumentCardView(document: document)
                                }
                                .buttonStyle(.plain)
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
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Documents")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundColor(theme.ink)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(theme.ink3)
            }
            Spacer()
            if !documents.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { isSearching.toggle() }
                    if !isSearching { query = "" }
                } label: {
                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.ink2)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(theme.surface))
                        .overlay(Circle().stroke(theme.line, lineWidth: 1))
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(theme.ink3)
            TextField("Search documents", text: $query)
                .foregroundColor(theme.ink)
        }
        .font(.system(size: 15))
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))
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
        }
        .padding(.bottom, 30)
    }
}
