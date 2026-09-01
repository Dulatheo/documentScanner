import SwiftUI

/// Result of a signing session, before placement: normalized strokes plus
/// the ink style used. `EditFlowView` assigns an initial placement and
/// hands this off to `SignaturePlacementView`.
struct SignatureDraftResult {
    var strokes: [SignatureStroke]
    var color: Theme.SignatureColor
    /// Normalized as a fraction of the drawing canvas width.
    var thickness: Double
    var aspectRatio: Double
}

/// Full-screen signature pad (DESIGN_SPEC §4.3). The mock presents this as
/// a landscape pad; rather than force a real device-orientation change (and
/// its app-wide side effects), the content is laid out landscape-shaped and
/// rotated into the portrait screen — the same visual result, no
/// `AppDelegate` orientation plumbing required.
struct SignaturePadView: View {
    var onCancel: () -> Void
    var onDone: (SignatureDraftResult) -> Void

    @Environment(\.theme) private var theme

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var color: Theme.SignatureColor = .ink
    @State private var thickness: Double = 5
    @State private var canvasSize: CGSize = .zero

    var body: some View {
        GeometryReader { screen in
            let w = screen.size.height
            let h = screen.size.width
            theme.bg.ignoresSafeArea()
            landscapeContent(width: w, height: h)
                .frame(width: w, height: h)
                .rotationEffect(.degrees(90))
                .position(x: screen.size.width / 2, y: screen.size.height / 2)
        }
        .ignoresSafeArea()
    }

    private func landscapeContent(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .font(.system(size: 15))
                    .foregroundColor(theme.ink2)
                Spacer()
                Text("Sign with your finger")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.ink)
                Spacer()
                Button(action: finish) {
                    Text("Done")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(theme.accent))
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)

            canvas
                .padding(.bottom, 12)

            controls
        }
        .padding(EdgeInsets(top: 14, leading: 58, bottom: 14, trailing: 22))
    }

    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.paper)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))

                Canvas { context, size in
                    var path = Path()
                    for stroke in strokes + [currentStroke] {
                        guard let first = stroke.first else { continue }
                        path.move(to: first)
                        for p in stroke.dropFirst() { path.addLine(to: p) }
                    }
                    context.stroke(
                        path,
                        with: .color(color.color),
                        style: StrokeStyle(lineWidth: CGFloat(thickness), lineCap: .round, lineJoin: .round)
                    )
                }

                VStack {
                    Spacer()
                    Rectangle().fill(theme.paperLine).frame(height: 1)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 52)
                }
                VStack {
                    Spacer()
                    HStack {
                        Text("Sign above the line")
                            .font(.system(size: 11))
                            .foregroundColor(theme.ink3)
                        Spacer()
                    }
                    .padding(.leading, 40)
                    .padding(.bottom, 30)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        currentStroke.append(value.location)
                    }
                    .onEnded { _ in
                        if !currentStroke.isEmpty {
                            strokes.append(currentStroke)
                        }
                        currentStroke = []
                    }
            )
            .onAppear { canvasSize = proxy.size }
            .onChange(of: proxy.size) { _, newValue in canvasSize = newValue }
        }
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 22) {
            HStack(spacing: 10) {
                ForEach(Theme.SignatureColor.allCases) { option in
                    Button {
                        color = option
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle().stroke(color == option ? theme.accent : theme.line, lineWidth: color == option ? 2 : 1)
                            )
                    }
                    .accessibilityLabel(option.displayName)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Thickness")
                    .font(.system(size: 11))
                    .foregroundColor(theme.ink3)
                Slider(value: $thickness, in: 2...14)
                    .tint(theme.accent)
            }

            RoundedRectangle(cornerRadius: 6)
                .fill(color.color)
                .frame(width: 34, height: max(CGFloat(thickness), 2))

            Button("Clear") {
                strokes = []
                currentStroke = []
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(theme.ink2)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 11).stroke(theme.line, lineWidth: 1))
        }
    }

    private func finish() {
        guard canvasSize.width > 0, canvasSize.height > 0, !strokes.isEmpty else {
            onCancel()
            return
        }
        let normalizedStrokes = strokes.map { stroke in
            SignatureStroke(points: stroke.map {
                CodablePoint(x: Double($0.x / canvasSize.width), y: Double($0.y / canvasSize.height))
            })
        }
        let result = SignatureDraftResult(
            strokes: normalizedStrokes,
            color: color,
            thickness: thickness / Double(canvasSize.width),
            aspectRatio: Double(canvasSize.height / canvasSize.width)
        )
        onDone(result)
    }
}
