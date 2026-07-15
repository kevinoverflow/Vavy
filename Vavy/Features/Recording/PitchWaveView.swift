import SwiftUI

/// Scrolling live pitch trace. Shows the trailing window of `points` so it
/// visually scrolls as new points are appended during recording. `nil`
/// entries are gaps (unvoiced/silent frames) and break the line.
struct PitchWaveView: View {
    let points: [Double?]

    private let maxVisible = 150
    private let semitoneScale: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            let midY = size.height * 0.72

            var grid = Path()
            grid.move(to: CGPoint(x: 0, y: midY))
            grid.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)

            let visible = Array(points.suffix(maxVisible))
            guard visible.count > 1 else { return }
            let stepX = size.width / CGFloat(max(maxVisible - 1, 1))

            var path = Path()
            var started = false
            var lastPoint: CGPoint?
            for (index, value) in visible.enumerated() {
                let x = CGFloat(index) * stepX
                guard let value else {
                    started = false
                    continue
                }
                let y = midY - CGFloat(value) * semitoneScale
                if started {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.move(to: CGPoint(x: x, y: y))
                    started = true
                }
                lastPoint = CGPoint(x: x, y: y)
            }
            context.stroke(
                path,
                with: .color(Color(uiColor: .systemBlue)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )

            if let lastPoint {
                let dotRect = CGRect(x: lastPoint.x - 5, y: lastPoint.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: dotRect), with: .color(Color(uiColor: .systemBlue)))
            }
        }
        .frame(height: 96)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct PitchWaveView_Previews: PreviewProvider {
    static var previews: some View {
        PitchWaveView(points: samplePoints())
            .padding()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }

    private static func samplePoints() -> [Double?] {
        var points: [Double?] = []
        for i in 0..<90 {
            if i % 23 == 0 {
                points.append(nil)
                continue
            }
            let wobble: Double = sin(Double(i) * 0.12) * 1.2
            let drift: Double = Double(i) * 0.035
            points.append(wobble + drift)
        }
        return points
    }
}
