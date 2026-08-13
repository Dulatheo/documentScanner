import SwiftUI

/// Bottom sheet for the Text (OCR) tool (DESIGN_SPEC §4.3): "Reading
/// page…" while busy, then the recognized text with Copy and "Keep as
/// searchable" actions.
struct OCRSheetView: View {
    let isBusy: Bool
    let text: String?
    let onCopy: () -> Void
    let onKeepSearchable: () -> Void
    let onDone: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recognized text")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.ink)
                Spacer()
                Button("Done", action: onDone)
                    .font(.system(size: 14))
                    .foregroundColor(theme.ink2)
            }

            if isBusy {
                Text("Reading page\u{2026}")
                    .font(.system(size: 13))
                    .foregroundColor(theme.ink2)
                    .padding(.vertical, 26)
            } else {
                ScrollView {
                    Text(text ?? "")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(theme.ink)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(maxHeight: 250)
                .background(RoundedRectangle(cornerRadius: 12).fill(theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))

                HStack(spacing: 10) {
                    Button(action: onCopy) {
                        Text("Copy text")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.accent))
                    }
                    Button(action: onKeepSearchable) {
                        Text("Keep as searchable")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 42)
        .background(theme.surface)
        .clipShape(RoundedCorner(radius: 20, corners: [.topLeft, .topRight]))
    }
}

/// Rounds only the specified corners (top corners for bottom sheets).
struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
