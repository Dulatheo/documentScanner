import SwiftUI
import UIKit

/// One grid cell on Home (DESIGN_SPEC §4.1): a stylized paper preview
/// (real first-page thumbnail once available, else simulated text-line
/// bars), a page-count pill, the name, and the date.
struct DocumentCardView: View {
    let document: DocumentModel

    @Environment(\.theme) private var theme
    @State private var thumbnail: UIImage?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.paper)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1)
                    )
                    .paperShadow(theme)
                    .overlay {
                        if let thumbnail {
                            // `.fit`, not `.fill`: captured pages can now
                            // come out of the camera auto-cropped to all
                            // sorts of aspect ratios, and `.fill` was
                            // cropping/zooming each one differently to
                            // stuff it into the fixed 3:4 card — showing
                            // the whole page letterboxed keeps every card
                            // visually consistent regardless of the page's
                            // own proportions.
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            simulatedLines
                        }
                    }

                Text(document.pageCountLabel)
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.6)
                    .foregroundColor(theme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(theme.accentSoft))
                    .padding(8)
            }

            Text(document.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.ink)
                .lineLimit(1)

            Text(Self.dateFormatter.string(from: document.createdAt))
                .font(.system(size: 11))
                .foregroundColor(theme.ink3)
        }
        .task {
            if let first = document.orderedPages.first {
                thumbnail = ImageStore.load(first.imagePath)
            }
        }
    }

    private var simulatedLines: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(theme.paperLine).frame(width: 52, height: 7)
                .padding(.bottom, 4)
            ForEach([CGFloat(0.92), 0.86, 0.94, 0.64, 0.90, 0.78], id: \.self) { fraction in
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.paperLine.opacity(0.7))
                        .frame(width: proxy.size.width * fraction, height: 4)
                }
                .frame(height: 4)
            }
        }
        .padding(14)
    }
}
