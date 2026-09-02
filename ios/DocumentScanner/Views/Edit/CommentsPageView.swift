import SwiftUI

/// Full-screen page for the Comment tool (DESIGN_SPEC §4.3): the
/// document's comments so far, plus a composer to add another. Works the
/// same for a fresh capture (comments buffered in `EditSession.comments`
/// until Save) and a re-edit of an existing document (its already-posted
/// comments loaded in alongside the buffered ones) — see
/// `EditSession.load(from:)`.
struct CommentsPageView: View {
    @Binding var comments: [DraftComment]
    let currentPageIndex: Int
    var onDone: () -> Void

    @Environment(\.theme) private var theme
    @State private var draft = ""

    private var sortedComments: [DraftComment] {
        comments.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments")
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

            if comments.isEmpty {
                Spacer()
                Text("No comments yet")
                    .font(.system(size: 14))
                    .foregroundColor(theme.ink2)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sortedComments) { comment in
                            commentRow(comment)
                        }
                    }
                    .padding(20)
                }
            }

            composer
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private func commentRow(_ comment: DraftComment) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(comment.text)
                .font(.system(size: 14))
                .foregroundColor(theme.ink)
                .lineSpacing(3)
            Text(metaLabel(for: comment))
                .font(.system(size: 11))
                .foregroundColor(theme.ink3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))
    }

    private func metaLabel(for comment: DraftComment) -> String {
        let relative = Self.relativeFormatter.localizedString(for: comment.createdAt, relativeTo: Date())
        if let pageIndex = comment.pageIndex {
            return "You \u{00b7} \(relative) \u{00b7} page \(pageIndex + 1)"
        }
        return "You \u{00b7} \(relative)"
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Note for this page")
                        .font(.system(size: 14))
                        .foregroundColor(theme.ink3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }
                TextEditor(text: $draft)
                    .font(.system(size: 14))
                    .foregroundColor(theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 70)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))

            Button(action: post) {
                Text("Post")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.accent))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(theme.bg)
        .overlay(Divider().overlay(theme.line), alignment: .top)
    }

    private func post() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        comments.append(DraftComment(text: trimmed, pageIndex: currentPageIndex))
        draft = ""
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
