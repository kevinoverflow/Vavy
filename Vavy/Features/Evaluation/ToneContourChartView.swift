import SwiftUI

/// Compares the expected canonical tone contour against the learner's
/// actual detected contour. Both are 5-point speaker-normalized (semitone)
/// contours with possible gaps (`nil` = no voiced frames in that quintile —
/// itself a feature, e.g. ngã's glottal break).
struct ToneContourChartView: View {
    let expected: [Double?]
    let actual: [Double?]

    private let semitoneScale: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                legendItem(color: Color(uiColor: .systemBlue), label: "You", dashed: false)
                legendItem(color: Color(uiColor: .secondaryLabel), label: "Expected", dashed: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            GeometryReader { geo in
                let size = geo.size
                let baseline = size.height * 0.5
                let xs = (0..<5).map { CGFloat($0) / 4 * size.width }

                Canvas { context, _ in
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: baseline))
                    grid.addLine(to: CGPoint(x: size.width, y: baseline))
                    context.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 1)

                    let expectedSegments = segments(from: expected, xs: xs, baseline: baseline)
                    for segment in expectedSegments {
                        context.stroke(
                            smoothPath(segment),
                            with: .color(.secondary.opacity(0.6)),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4])
                        )
                    }

                    if let gapIndex = expected.indices.dropFirst().dropLast().first(where: { expected[$0] == nil }) {
                        let neighborValues = [expected[gapIndex - 1], expected[gapIndex + 1]].compactMap { $0 }
                        if !neighborValues.isEmpty {
                            let avg = neighborValues.reduce(0, +) / Double(neighborValues.count)
                            let y = baseline - CGFloat(avg) * semitoneScale
                            let dotRect = CGRect(x: xs[gapIndex] - 3, y: y - 3, width: 6, height: 6)
                            context.fill(Path(ellipseIn: dotRect), with: .color(Color(uiColor: .systemOrange)))
                        }
                    }

                    let actualSegments = segments(from: actual, xs: xs, baseline: baseline)
                    for segment in actualSegments {
                        context.stroke(
                            smoothPath(segment),
                            with: .color(Color(uiColor: .systemBlue)),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                    if let lastPoint = actualSegments.last?.last {
                        let dotRect = CGRect(x: lastPoint.x - 4.5, y: lastPoint.y - 4.5, width: 9, height: 9)
                        context.fill(Path(ellipseIn: dotRect), with: .color(Color(uiColor: .systemBlue)))
                        context.stroke(Path(ellipseIn: dotRect), with: .color(Color(uiColor: .tertiarySystemBackground)), lineWidth: 2)
                    }
                }
            }
            .frame(height: 130)
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Splits a contour into contiguous runs of voiced points (breaking at
    /// `nil` gaps), mapped to view-space coordinates.
    private func segments(from contour: [Double?], xs: [CGFloat], baseline: CGFloat) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        for (index, value) in contour.enumerated() {
            guard let value else {
                if !current.isEmpty { result.append(current); current = [] }
                continue
            }
            current.append(CGPoint(x: xs[index], y: baseline - CGFloat(value) * semitoneScale))
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Catmull-Rom-style smoothing through the given points.
    private func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }

        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }

    private func legendItem(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            LegendSwatch(color: color, dashed: dashed)
                .frame(width: 14, height: 8)
            Text(label)
        }
    }

    private struct LegendSwatch: View {
        let color: Color
        let dashed: Bool

        var body: some View {
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                let style = dashed ? StrokeStyle(lineWidth: 2, dash: [3, 2]) : StrokeStyle(lineWidth: 2)
                context.stroke(path, with: .color(color), style: style)
            }
        }
    }
}

struct ToneContourChartView_Previews: PreviewProvider {
    static var previews: some View {
        ToneContourChartView(
            expected: ToneReferenceContours.contour(for: .nga),
            actual: [0, 1.1, 2.2, 3.3, 4.2]
        )
        .padding()
        .background(Color.black)
        .previewLayout(.sizeThatFits)
    }
}
