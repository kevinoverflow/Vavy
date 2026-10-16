import Foundation

struct AssessmentResult: Identifiable, Codable, Equatable {
    let attemptID: String
    let status: AssessmentStatus
    let passed: Bool
    let expectedText: String
    let recognizedText: String?
    let overallScore: Double?
    let strictScore: Double?
    let scores: AssessmentScores?
    let mainError: AssessmentMainError?
    let feedback: AssessmentFeedback?

    var id: String { attemptID }

    enum CodingKeys: String, CodingKey {
        case attemptID = "attempt_id"
        case status
        case passed
        case expectedText = "expected_text"
        case recognizedText = "recognized_text"
        case overallScore = "overall_score"
        case strictScore = "strict_score"
        case scores
        case mainError = "main_error"
        case feedback
    }
}

enum AssessmentStatus: String, Codable, Equatable {
    case passed
    case notPassed = "not_passed"
    /// The recording was usable but the evidence was weak or conflicting, so the backend
    /// gave no verdict. Never counts as a failed attempt.
    case uncertain
    case retryAudioQuality = "retry_audio_quality"
    case backendError = "backend_error"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = AssessmentStatus(rawValue: value) ?? .backendError
    }

    /// Whether the backend actually judged the pronunciation. Only verdicts count toward
    /// progress; abstentions (`uncertain`, `retry_audio_quality`, `backend_error`) never do.
    var isVerdict: Bool {
        self == .passed || self == .notPassed
    }

    var displayTitle: String {
        switch self {
        case .passed:
            return "Passed."
        case .notPassed:
            return "Not passed."
        case .uncertain:
            return "Try again. I couldn't judge this confidently."
        case .retryAudioQuality:
            return "Try again. I could not judge the recording."
        case .backendError:
            return "Try again. The tutor could not evaluate this attempt."
        }
    }
}

struct AssessmentScores: Codable, Equatable {
    let accuracy: Double?
    let fluency: Double?
    let completeness: Double?
    let pronunciation: Double?

    enum CodingKeys: String, CodingKey {
        case accuracy
        case fluency
        case completeness
        case pronunciation
        case azureAccuracy = "azure_accuracy"
        case azureFluency = "azure_fluency"
        case azureCompleteness = "azure_completeness"
        case azurePronunciation = "azure_pronunciation"
    }

    init(accuracy: Double?, fluency: Double?, completeness: Double?, pronunciation: Double?) {
        self.accuracy = accuracy
        self.fluency = fluency
        self.completeness = completeness
        self.pronunciation = pronunciation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accuracy = try container.decodeIfPresent(Double.self, forKey: .accuracy)
            ?? container.decodeIfPresent(Double.self, forKey: .azureAccuracy)
        fluency = try container.decodeIfPresent(Double.self, forKey: .fluency)
            ?? container.decodeIfPresent(Double.self, forKey: .azureFluency)
        completeness = try container.decodeIfPresent(Double.self, forKey: .completeness)
            ?? container.decodeIfPresent(Double.self, forKey: .azureCompleteness)
        pronunciation = try container.decodeIfPresent(Double.self, forKey: .pronunciation)
            ?? container.decodeIfPresent(Double.self, forKey: .azurePronunciation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(accuracy, forKey: .accuracy)
        try container.encodeIfPresent(fluency, forKey: .fluency)
        try container.encodeIfPresent(completeness, forKey: .completeness)
        try container.encodeIfPresent(pronunciation, forKey: .pronunciation)
    }
}

struct AssessmentMainError: Codable, Equatable {
    let type: AssessmentErrorType
    let expected: String?
    let heardLike: String?
    let severity: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type
        case expected
        case heardLike = "heard_like"
        case severity
        case message
    }
}

enum AssessmentErrorType: String, Codable, Equatable {
    case backendError = "backend_error"
    case audioQuality = "audio_quality"
    case noSpeech = "no_speech"
    case toneUncertain = "tone_uncertain"
    case incompletePrompt = "incomplete_prompt"
    case toneConfusion = "tone_confusion"
    case pronunciationNotStrictEnough = "pronunciation_not_strict_enough"
    case closeButNotStrict = "close_but_not_strict"
    case lowAccuracy = "low_accuracy"
    case missingPrompt = "missing_prompt"
    case extraSpeech = "extra_speech"
    case vowelIssue = "vowel_issue"
    case initialConsonantIssue = "initial_consonant_issue"
    case finalConsonantIssue = "final_consonant_issue"
    case fluencyIssue = "fluency_issue"
    case audioTooQuiet = "audio_too_quiet"
    case audioTooNoisy = "audio_too_noisy"
    case audioClipped = "audio_clipped"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = AssessmentErrorType(rawValue: value) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .backendError:
            return "Backend error"
        case .audioQuality:
            return "Audio quality"
        case .noSpeech:
            return "No speech recognized"
        case .toneUncertain:
            return "Tone not judged"
        case .incompletePrompt:
            return "Incomplete prompt"
        case .toneConfusion:
            return "Tone"
        case .pronunciationNotStrictEnough:
            return "Pronunciation"
        case .closeButNotStrict:
            return "Almost there"
        case .lowAccuracy:
            return "Accuracy"
        case .missingPrompt:
            return "Missing prompt"
        case .extraSpeech:
            return "Extra speech"
        case .vowelIssue:
            return "Vowel"
        case .initialConsonantIssue:
            return "Initial consonant"
        case .finalConsonantIssue:
            return "Final consonant"
        case .fluencyIssue:
            return "Fluency"
        case .audioTooQuiet:
            return "Audio too quiet"
        case .audioTooNoisy:
            return "Audio too noisy"
        case .audioClipped:
            return "Audio clipped"
        case .unknown:
            return "Pronunciation"
        }
    }
}

struct AssessmentFeedback: Codable, Equatable {
    let title: String?
    let body: String?
    let fix: String?
    let drill: [String]?
}
