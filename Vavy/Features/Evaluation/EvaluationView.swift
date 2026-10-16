import SwiftUI

struct EvaluationView: View {
    let result: AssessmentResult
    var toneAnalysis: ToneAnalysisResult? = nil
    var expectedTone: VietnameseTone? = nil
    let tryAgainAction: () -> Void
    let nextPromptAction: () -> Void
    let backToLessonAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.status.displayTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(titleColor)
                Spacer()
                if let strictScore = result.strictScore {
                    Text("Strict \(ScoreFormatter.string(from: strictScore))")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(titleColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                labeledText("Expected", value: result.expectedText)
                labeledText("Recognized", value: result.recognizedText ?? "—")
            }

            if let expectedTone, let toneAnalysis, toneAnalysis.contour.contains(where: { $0 != nil }) {
                ToneContourChartView(
                    expected: ToneReferenceContours.contour(for: expectedTone),
                    actual: toneAnalysis.contour
                )
            }

            FeedbackCardView(result: result)

            VStack(alignment: .leading, spacing: 6) {
                Text("Scores")
                    .font(.headline)
                ScoreRowView(label: "Pronunciation", score: result.scores?.pronunciation)
                ScoreRowView(label: "Accuracy", score: result.scores?.accuracy)
                ScoreRowView(label: "Completeness", score: result.scores?.completeness)
                ScoreRowView(label: "Fluency", score: result.scores?.fluency)
                ScoreRowView(label: "Strict score", score: result.strictScore)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 10) {
                PrimaryButton("Try Again", systemImage: "arrow.counterclockwise", action: tryAgainAction)
                Button(action: nextPromptAction) {
                    Label("Next prompt", systemImage: "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button(action: backToLessonAction) {
                    Label("Back to lesson", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            #if DEBUG
            Text("Attempt: \(result.attemptID)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            #endif
        }
        .padding(18)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var titleColor: Color {
        switch result.status {
        case .passed:
            return Color(uiColor: .systemGreen)
        case .retryAudioQuality:
            return Color(uiColor: .systemOrange)
        case .backendError, .uncertain:
            return Color(uiColor: .systemOrange)
        case .notPassed:
            return Color(uiColor: .systemRed)
        }
    }

    private func labeledText(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.body.weight(.medium))
            Spacer()
        }
    }
}

struct EvaluationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ScrollView {
                EvaluationView(
                    result: StarterLessonData.passedAssessment,
                    tryAgainAction: {},
                    nextPromptAction: {},
                    backToLessonAction: {}
                )
                .padding()
            }
            .previewDisplayName("Passed")

            ScrollView {
                EvaluationView(
                    result: StarterLessonData.notPassedAssessment,
                    tryAgainAction: {},
                    nextPromptAction: {},
                    backToLessonAction: {}
                )
                .padding()
            }
            .previewDisplayName("Not passed")

            ScrollView {
                EvaluationView(
                    result: StarterLessonData.retryAudioAssessment,
                    tryAgainAction: {},
                    nextPromptAction: {},
                    backToLessonAction: {}
                )
                .padding()
            }
            .previewDisplayName("Retry audio")

            ScrollView {
                EvaluationView(
                    result: StarterLessonData.uncertainAssessment,
                    tryAgainAction: {},
                    nextPromptAction: {},
                    backToLessonAction: {}
                )
                .padding()
            }
            .previewDisplayName("Uncertain")

            ScrollView {
                EvaluationView(
                    result: StarterLessonData.backendErrorAssessment,
                    tryAgainAction: {},
                    nextPromptAction: {},
                    backToLessonAction: {}
                )
                .padding()
            }
            .previewDisplayName("Backend error")

            ScrollView {
                EvaluationView(
                    result: StarterLessonData.notPassedAssessment,
                    toneAnalysis: ToneAnalysisResult(
                        detectedTone: .sac,
                        confidence: 0.78,
                        contour: [0, 1.1, 2.2, 3.3, 4.2],
                        voicedFrameCount: 40,
                        totalFrameCount: 50,
                        durationMs: 700
                    ),
                    expectedTone: .nga,
                    tryAgainAction: {},
                    nextPromptAction: {},
                    backToLessonAction: {}
                )
                .padding()
            }
            .previewDisplayName("Not passed, with tone chart")
        }
    }
}
