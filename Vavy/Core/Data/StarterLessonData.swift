import Foundation

enum StarterLessonData {
    static let sampleLesson = Lesson(
        lessonID: "tones_starter_local",
        title: "Six Vietnamese tones",
        targetDialect: .northernHanoi,
        items: starterItems
    )

    static let starterItems: [TrainingItem] = toneItems(for: "m", baseID: "tone_ma", rime: "a")
        + toneItems(for: "b", baseID: "tone_ba", rime: "a")
        + toneItems(for: "l", baseID: "tone_la", rime: "a")
        + phraseItems

    static let passedAssessment = AssessmentResult(
        attemptID: "att_preview_passed",
        status: .passed,
        passed: true,
        expectedText: "mã",
        recognizedText: "Mã.",
        overallScore: 92,
        strictScore: 88,
        scores: AssessmentScores(accuracy: 90, fluency: 100, completeness: 100, pronunciation: 92),
        mainError: nil,
        feedback: AssessmentFeedback(
            title: "Passed",
            body: "The syllable and tone were clear enough for this item.",
            fix: nil,
            drill: nil
        )
    )

    static let notPassedAssessment = AssessmentResult(
        attemptID: "att_preview_failed",
        status: .notPassed,
        passed: false,
        expectedText: "mã",
        recognizedText: "Má.",
        overallScore: 68,
        strictScore: 54,
        scores: AssessmentScores(accuracy: 72, fluency: 94, completeness: 100, pronunciation: 76),
        mainError: AssessmentMainError(
            type: .toneConfusion,
            expected: "ngã",
            heardLike: "sắc",
            severity: "high",
            message: "Your base syllable was close, but the tone sounded closer to má than mã."
        ),
        feedback: AssessmentFeedback(
            title: "Not passed: tone problem",
            body: "Expected mã with ngã tone. Your pronunciation sounded closer to má.",
            fix: "Make the target tone clearer.",
            drill: ["mã", "má", "mã"]
        )
    )

    static let retryAudioAssessment = AssessmentResult(
        attemptID: "att_preview_retry",
        status: .retryAudioQuality,
        passed: false,
        expectedText: "mã",
        recognizedText: nil,
        overallScore: nil,
        strictScore: nil,
        scores: nil,
        mainError: AssessmentMainError(
            type: .audioTooQuiet,
            expected: nil,
            heardLike: nil,
            severity: "medium",
            message: "The recording was too quiet to evaluate reliably."
        ),
        feedback: AssessmentFeedback(
            title: "Try again",
            body: "I could not judge the recording.",
            fix: "Hold the phone closer and speak once after tapping record.",
            drill: nil
        )
    )

    static let uncertainAssessment = AssessmentResult(
        attemptID: "att_preview_uncertain",
        status: .uncertain,
        passed: false,
        expectedText: "mã",
        recognizedText: "Mã.",
        overallScore: 93,
        strictScore: nil,
        scores: AssessmentScores(accuracy: 92, fluency: 100, completeness: 100, pronunciation: 93),
        mainError: AssessmentMainError(
            type: .toneUncertain,
            expected: "nga",
            heardLike: nil,
            severity: "low",
            message: "The tone evidence was conflicting, so this attempt was not judged."
        ),
        feedback: AssessmentFeedback(
            title: "Try again: I couldn't judge the tone",
            body: "The recording was clear, but I could not tell confidently whether the ngã tone was right. This attempt does not count against you.",
            fix: "Say mã once more at a steady volume, with a short pause before and after.",
            drill: ["mã"]
        )
    )

    static let backendErrorAssessment = AssessmentResult(
        attemptID: "att_preview_backend_error",
        status: .backendError,
        passed: false,
        expectedText: "ma",
        recognizedText: nil,
        overallScore: nil,
        strictScore: nil,
        scores: AssessmentScores(accuracy: nil, fluency: nil, completeness: nil, pronunciation: nil),
        mainError: AssessmentMainError(
            type: .backendError,
            expected: nil,
            heardLike: nil,
            severity: "medium",
            message: "The backend could not evaluate this recording."
        ),
        feedback: AssessmentFeedback(
            title: "Could not evaluate",
            body: "Something went wrong while analyzing the recording. Please try again.",
            fix: "Try recording again. If this keeps happening, check the backend logs.",
            drill: nil
        )
    )

    static func localRetryAudioAssessment(
        expectedText: String,
        report: AudioQualityReport
    ) -> AssessmentResult {
        AssessmentResult(
            attemptID: "local_audio_quality_\(UUID().uuidString)",
            status: .retryAudioQuality,
            passed: false,
            expectedText: expectedText,
            recognizedText: nil,
            overallScore: nil,
            strictScore: nil,
            scores: nil,
            mainError: AssessmentMainError(
                type: errorType(for: report),
                expected: nil,
                heardLike: nil,
                severity: "medium",
                message: "Local audio quality check blocked this upload."
            ),
            feedback: AssessmentFeedback(
                title: "Try again",
                body: "I could not judge this recording. Speak only the word shown, a little louder, in a quiet place.",
                fix: nil,
                drill: nil
            )
        )
    }

    private static func toneItems(for initial: String, baseID: String, rime: String) -> [TrainingItem] {
        [
            toneItem(id: "\(baseID)_ngang", text: "\(initial)\(rime)", initial: initial, rime: rime, tone: .ngang),
            toneItem(id: "\(baseID)_sac", text: "\(initial)á", initial: initial, rime: rime, tone: .sac),
            toneItem(id: "\(baseID)_huyen", text: "\(initial)à", initial: initial, rime: rime, tone: .huyen),
            toneItem(id: "\(baseID)_hoi", text: "\(initial)ả", initial: initial, rime: rime, tone: .hoi),
            toneItem(id: "\(baseID)_nga", text: "\(initial)ã", initial: initial, rime: rime, tone: .nga),
            toneItem(id: "\(baseID)_nang", text: "\(initial)ạ", initial: initial, rime: rime, tone: .nang)
        ]
    }

    private static func errorType(for report: AudioQualityReport) -> AssessmentErrorType {
        if report.isTooQuiet {
            return .audioTooQuiet
        }
        if report.isClipped {
            return .audioClipped
        }
        return .unknown
    }

    private static func toneItem(
        id: String,
        text: String,
        initial: String,
        rime: String,
        tone: VietnameseTone
    ) -> TrainingItem {
        TrainingItem(
            id: id,
            text: text,
            displayText: text,
            meaning: nil,
            targetDialect: .northernHanoi,
            difficulty: 1,
            category: .toneMinimalPair,
            expected: ExpectedPronunciation(
                syllables: [
                    VietnameseSyllableTarget(
                        orthography: text,
                        initial: initial,
                        rime: rime,
                        finalSound: nil,
                        tone: tone
                    )
                ]
            )
        )
    }

    private static let phraseItems: [TrainingItem] = [
        phraseItem(id: "phrase_xin_chao", text: "xin chào", difficulty: 1),
        phraseItem(id: "phrase_cam_on", text: "cảm ơn", difficulty: 1),
        phraseItem(id: "word_khong", text: "không", difficulty: 1),
        phraseItem(id: "word_pho", text: "phở", difficulty: 1),
        phraseItem(id: "word_nguoi", text: "người", difficulty: 2)
    ]

    private static func phraseItem(id: String, text: String, difficulty: Int) -> TrainingItem {
        TrainingItem(
            id: id,
            text: text,
            displayText: text,
            meaning: nil,
            targetDialect: .northernHanoi,
            difficulty: difficulty,
            category: .shortPhrase,
            expected: ExpectedPronunciation(
                syllables: [
                    VietnameseSyllableTarget(
                        orthography: text,
                        initial: nil,
                        rime: text,
                        finalSound: nil,
                        tone: .ngang
                    )
                ]
            )
        )
    }
}
