import Foundation

/// Illustrative 5-point semitone contours per Vietnamese tone, used only to
/// draw the "Expected" reference line in `ToneContourChartView`. These are
/// hand-shaped to match the linguistic description each tone is taught with
/// (and the rules `ToneContourAnalyzer` classifies against) — they are not
/// measured from real speaker data, same "heuristic v1" caveat as the
/// classifier itself.
enum ToneReferenceContours {
    static func contour(for tone: VietnameseTone) -> [Double?] {
        switch tone {
        case .ngang:
            // Level, unmarked.
            return [0, 0.2, 0, -0.2, 0]
        case .sac:
            // Clear, steady rise.
            return [0, 1.3, 2.6, 4.0, 5.3]
        case .huyen:
            // Gentle, steady fall.
            return [0, -1.3, -2.6, -3.9, -5.2]
        case .hoi:
            // Dips, then rises again — continuous voicing, no break.
            return [0, -2.0, -3.2, -1.8, 0.3]
        case .nga:
            // Dips, breaks (glottal interruption), then rises sharply.
            return [0, -2.5, nil, -0.5, 5.0]
        case .nang:
            // Low, falling, and checked short — often cut off before the end.
            return [-1.0, -2.0, -3.0, -3.8, nil]
        }
    }
}
