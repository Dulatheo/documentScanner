import SwiftUI

/// Empty state per DESIGN_SPEC §4.1.
struct EmptyStateView: View {
    let onScan: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 26)
                    .fill(theme.surface)
                    .frame(width: 112, height: 112)
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(theme.line, lineWidth: 1))
                    .paperShadow(theme)
                Image(systemName: "viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(theme.accent)
            }
            .padding(.bottom, 20)

            Text("No documents yet")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(theme.ink)

            Text("Scanned documents are saved here. Point your camera at a page to begin.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .foregroundColor(theme.ink2)
                .frame(maxWidth: 250)
                .lineSpacing(3)

            Button(action: onScan) {
                HStack(spacing: 9) {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 16, weight: .medium))
                    Text("Scan a document")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent))
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
