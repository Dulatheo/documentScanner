import SwiftUI

/// "Add comment" bottom sheet (DESIGN_SPEC §4.4).
struct CommentSheetView: View {
    var onPost: (String) -> Void
    var onCancel: () -> Void

    @Environment(\.theme) private var theme
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add comment")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.ink)
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(.system(size: 14))
                    .foregroundColor(theme.ink2)
            }

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
                    .frame(height: 90)
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))

            Button {
                let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onPost(trimmed)
                draft = ""
            } label: {
                Text("Post")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.accent))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
    }
}
