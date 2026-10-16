# CLAUDE.md — iOS Native App Agent

## Mission

Build the native iOS client for a strict Vietnamese pronunciation tutor.

The app is not a generic flashcard app and not a speech-to-text demo. It is a guided pronunciation tutor:

1. Show a Vietnamese word or sentence.
2. Let the learner record themselves.
3. Send the recording and prompt id to the backend.
4. Display a strict pronunciation evaluation.
5. Encourage repetition until the learner passes.

V1 uses Azure Pronunciation Assessment through the backend. V2 adds MFA-backed timing/phonetic feedback on the backend. Do not implement PhoWhisper or local ASR in V1.

**Revised**: for `tone_minimal_pair` items, the app now also runs a rule-based, on-device pitch/tone-shape classifier (`ToneContourAnalyzer.swift`) and sends the result to the backend as an additional evidence field. This is classic DSP over an explicit pitch signal, not a trained model and not speech-to-text — it is not "local ASR" or "PhoWhisper" in the sense the prohibition above means. The backend still makes every final pass/fail decision; see "On-device tone analysis" below and `PROJECT_SUMMARY.md`.

---

## Product principles

### Strict tutor, not friendly score screen

The app must be willing to show:

> Not passed. Recognized correctly, but the tone was not strict enough.

A high-level score alone is not acceptable. The evaluation view must always prefer actionable feedback:

- Main issue: tone, vowel, initial consonant, final consonant, completeness, or audio quality.
- Expected sound or tone.
- What the user likely did instead.
- A small corrective drill.

### Scripted practice first

The app already knows what the learner is supposed to say. The backend evaluates against the known prompt.

Do not design the V1 UX around open conversation or free speaking.

### Hardcoded training data first

Anki import is out of scope for the first implementation. Build with hardcoded Vietnamese practice items first. Anki/CSV/TSV import comes later after the tutoring loop is strong.

---

## Target platform and stack

Use:

- Swift
- SwiftUI
- Swift Concurrency, `async`/`await`
- AVFoundation for recording and playback
- Native networking with `URLSession`
- No cross-platform framework
- No Azure key inside the iOS app
- No MFA on-device
- No local PhoWhisper in V1

Recommended minimum deployment target can be decided by the project owner, but keep the implementation compatible with current iOS versions and avoid unnecessary bleeding-edge APIs.

---

## App flow

```text
LessonView
  ↓
User sees prompt: "mã"
  ↓
Tap microphone
  ↓
Recording starts
  ↓
Tap stop
  ↓
Upload audio + item_id to backend
  ↓
Show Evaluating state
  ↓
EvaluationView shows pass/fail + strict feedback
  ↓
Try again or next prompt
```

---

## Main screens

### 1. LessonView

Responsibilities:

- Display the current Vietnamese prompt.
- Show optional metadata: tone, category, target dialect, meaning.
- Provide a listen button placeholder for native audio.
- Provide a record button.
- Navigate to evaluation state after upload.

The prompt should be visually dominant.

Example layout:

```text
mã
ngã tone · Northern / Hanoi

[Listen]
[Record]
```

### 2. Recording state

Responsibilities:

- Show that recording is active.
- Show elapsed time.
- Allow stop/cancel.
- Prevent recordings that are too long.

V1 can use tap-to-start / tap-to-stop. Do not build push-to-talk first unless explicitly requested.

### 3. EvaluationView

Responsibilities:

- Show one of three states:
   - Passed
   - Not passed
   - Try again because recording quality was bad
- Show scores only as secondary information.
- Show the strict tutor result as the primary feedback.
- Offer Try Again and Next.

Example failed result:

```text
Not passed

Expected: mã
Main issue: Tone

Your base syllable was close, but the tone sounded closer to má.

Fix:
Add the broken rising quality for ngã.

Drill:
mã — má — mã

[Try again] [Next]
```

---

## Suggested project structure

```text
Vavy/
  App/
    VietTutorApp.swift

  Features/
    Lesson/
      LessonView.swift
      LessonViewModel.swift
      LessonCardView.swift

    Recording/
      AudioRecorder.swift
      RecordingButton.swift
      RecordingStateView.swift
      RecordingPlaybackView.swift

    Evaluation/
      EvaluationView.swift
      EvaluationViewModel.swift
      ScoreRowView.swift
      FeedbackCardView.swift

  Core/
    Models/
      TrainingItem.swift
      VietnamesePronunciation.swift
      AssessmentResult.swift
      APIModels.swift

    Networking/
      PronunciationAPIClient.swift
      APIError.swift
      MultipartFormDataBuilder.swift

    Audio/
      AudioSessionManager.swift
      AudioFileValidator.swift
      ToneContourAnalyzer.swift

    Data/
      StarterTrainingData.swift
```

Keep feature code separated from core models and networking.

---

## Data models

### Training item

Use hardcoded local data for V1.

```swift
struct TrainingItem: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let displayText: String
    let meaning: String?
    let targetDialect: Dialect
    let difficulty: Int
    let category: TrainingCategory
    let expected: ExpectedPronunciation
}

enum Dialect: String, Codable {
    case northernHanoi = "northern_hanoi"
}

enum TrainingCategory: String, Codable {
    case toneMinimalPair = "tone_minimal_pair"
    case vowelContrast = "vowel_contrast"
    case finalConsonant = "final_consonant"
    case shortPhrase = "short_phrase"
}

struct ExpectedPronunciation: Codable, Equatable {
    let syllables: [VietnameseSyllableTarget]
}

struct VietnameseSyllableTarget: Codable, Equatable {
    let orthography: String
    let initial: String?
    let rime: String
    let final: String?
    let tone: VietnameseTone
}

enum VietnameseTone: String, Codable {
    case ngang
    case sac
    case huyen
    case hoi
    case nga
    case nang
}
```

### Starter lesson data

Implement at least this first lesson:

```swift
let starterToneItems: [TrainingItem] = [
    TrainingItem(
        id: "tone_ma_ngang",
        text: "ma",
        displayText: "ma",
        meaning: nil,
        targetDialect: .northernHanoi,
        difficulty: 1,
        category: .toneMinimalPair,
        expected: ExpectedPronunciation(syllables: [
            VietnameseSyllableTarget(
                orthography: "ma",
                initial: "m",
                rime: "a",
                final: nil,
                tone: .ngang
            )
        ])
    ),
    TrainingItem(
        id: "tone_ma_sac",
        text: "má",
        displayText: "má",
        meaning: nil,
        targetDialect: .northernHanoi,
        difficulty: 1,
        category: .toneMinimalPair,
        expected: ExpectedPronunciation(syllables: [
            VietnameseSyllableTarget(
                orthography: "má",
                initial: "m",
                rime: "a",
                final: nil,
                tone: .sac
            )
        ])
    )
]
```

Complete the six-tone set:

```text
ma, má, mà, mả, mã, mạ
```

Then add:

```text
ba, bá, bà, bả, bã, bạ
la, lá, là, lả, lã, lạ
xin chào
cảm ơn
không
phở
người
```

---

## Backend API contract

The iOS app communicates only with our Node.js backend.

### Evaluate attempt

```http
POST /v1/attempts/evaluate
Content-Type: multipart/form-data

fields:
  item_id: String
  audio: File
  client_audio_features: String (JSON, optional) — client-side audio quality metrics
  client_tone_features: String (JSON, optional) — on-device pitch/tone-shape
    analysis for tone_minimal_pair items, from ToneContourAnalyzer.swift.
    See "On-device tone analysis" below.
```

Expected response:

```json
{
	"attempt_id": "att_123",
	"status": "not_passed",
	"expected_text": "mã",
	"recognized_text": "má",
	"overall_score": 68,
	"strict_score": 54,
	"main_error": {
		"type": "tone_confusion",
		"expected": "nga",
		"heard_like": "sac",
		"severity": "high",
		"message": "Your base syllable was close, but the tone sounded closer to má than mã."
	},
	"feedback": {
		"title": "Not passed: tone problem",
		"body": "Expected mã with ngã tone. Add the broken rising quality in the middle.",
		"drill": ["mã", "má", "mã"]
	},
	"scores": {
		"azure_accuracy": 72,
		"azure_fluency": 94,
		"azure_completeness": 100,
		"azure_pronunciation": 76
	}
}
```

`status` must be one of:

```text
passed
not_passed
uncertain             # usable audio, conflicting or weak evidence: no verdict
retry_audio_quality   # includes main_error.type no_speech
backend_error
```

Only `passed` and `not_passed` are verdicts (`AssessmentStatus.isVerdict`). Nothing else may count toward item history or be shown as a failure. Unknown future statuses decode as `backendError`.

---

## Audio recording requirements

V1 should use `AVAudioRecorder`.

Requirements:

- Ask for microphone permission before recording.
- Record to a local temporary file.
- Keep attempts short.
- Reject or auto-stop very long recordings.
- Allow playback of the most recent recording during development.
- Delete temporary files after successful upload unless debug mode is enabled.

Suggested V1 format:

- Record as `.m4a` on iOS for convenience.
- Backend converts to WAV PCM 16 kHz mono before sending to Azure.

The backend owns audio conversion. Do not over-optimize audio encoding on iOS in V1.

---

## Audio quality checks on iOS

V1 minimum:

- Check that a file exists.
- Check file duration is not zero.
- Check duration is below max limit.
- Show helpful errors for missing microphone permission.

V2:

- Add basic volume metering.
- Detect silence.
- Warn if the input level is extremely low.
- Warn if the input clips.

Bad audio should produce a retry state, not a pronunciation failure.

---

## On-device tone analysis

For `tone_minimal_pair` items only, `ToneContourAnalyzer.swift` runs a heuristic pitch/tone-shape classifier on the just-recorded PCM samples (via `PCM16WAVFile.samples`), synchronously in `LessonViewModel.stopRecordingAndEvaluate()` right after the existing audio-quality check.

Pipeline: frame the signal (40ms/10ms hop) → YIN-style pitch estimate per frame with an octave-jump continuity constraint → speaker-normalize to semitones relative to the utterance's own voiced-frame median → summarize into a 5-point quintile contour (gaps allowed — a quintile with no voiced frames is `nil`, itself a feature for ngã/nặng) → rule-based classification into one of the six tones with a confidence score.

The result (`ToneAnalysisResult`) is uploaded as the `client_tone_features` multipart field, same pattern as the existing `client_audio_features` field. It is *evidence only*: the backend (`CLIENT_TONE_MODE=evidence_only`) never passes or fails an attempt on it alone. When it confidently disagrees with Azure in either direction, the backend returns `uncertain`. Each result carries `analyzer_version` (`ToneContourAnalyzer.version`); bump it whenever framing, pitch estimation, normalization or classification rules change.

Its accuracy is unmeasured. `VavyTests/ToneContourAnalyzerTests.swift` and `PitchEstimatorTests.swift` contain characterization tests that pin current, partly known-wrong behavior (octave errors, dependence on trailing silence and input gain). A change that improves the analyzer must update those expectations deliberately. To measure the analyzer on labeled recordings, use `Tools/extract-tone-features.sh` with the backend's `npm run eval` (see `vavy-backend/eval/README.md`).

This is a heuristic v1, not a guarantee: hỏi and ngã are phonetically merged (no glottal break) for many speakers/dialects, which no DSP heuristic fixes. A `#if DEBUG` debug view (`toneAnalysisDebugView` in `LessonView.swift`) surfaces detected tone/confidence/contour per attempt — use it to tune the classifier's thresholds against real recordings before trusting it further.

---

## UI state model

Use a simple state enum in the lesson view model:

```swift
enum LessonInteractionState: Equatable {
    case idle
    case requestingMicrophonePermission
    case recording(elapsed: TimeInterval)
    case recorded(fileURL: URL)
    case uploading
    case evaluating
    case result(AssessmentResult)
    case error(String)
}
```

Avoid mixing recording state, networking state, and result state in the view.

---

## Networking requirements

Create `PronunciationAPIClient`.

Responsibilities:

- Build multipart form requests.
- Upload the audio file and `item_id`.
- Decode backend JSON.
- Map backend errors to user-visible messages.
- Use environment-based base URL configuration.

Do not hardcode production URLs inside view files.

Example environments:

```swift
enum APIEnvironment {
    case local
    case staging
    case production
}
```

Local backend URL during development:

```text
http://localhost:3000
```

For physical iPhone testing, use the Mac LAN IP or a tunnel. `localhost` from the phone is the phone itself, not the Mac.

---

## Evaluation display rules

The main feedback card must be driven by `main_error.type`, not by generic score text.

Supported main error types:

```text
tone_confusion
low_accuracy
missing_prompt
extra_speech
vowel_issue
initial_consonant_issue
final_consonant_issue
fluency_issue
audio_too_quiet
audio_too_noisy
audio_clipped
unknown
```

For `retry_audio_quality`, do not show “failed.” Show:

```text
Try again. I could not judge the recording.
```

For `uncertain`, do not show "failed" either. Show:

```text
Try again. I couldn't judge this confidently.
```

For `not_passed`, show:

```text
Not passed.
```

For `passed`, show:

```text
Passed.
```

---

## V1 implementation order

### Milestone 1 — Static UI

- Lesson screen
- Recording button placeholder
- Evaluation screen with fake result
- Hardcoded `ma` tone lesson

Done when the tutoring loop feels right with fake data.

### Milestone 2 — Recording

- Microphone permission
- Start/stop recording
- Save local file
- Playback debug button

Done when a user can record and play back their own voice.

### Milestone 3 — Upload to fake backend

- Multipart upload
- Decode fake result
- Display result

Done when the app can show backend-driven feedback.

### Milestone 4 — Real Azure backend integration

- No iOS change except possibly response-model adjustment
- Display real Azure-derived scores
- Keep feedback strict and clear

### Milestone 5 — Polish the evaluation UX

- Better feedback cards
- Try-again loop
- Progress through lesson items
- Basic history per item

---

## Out of scope for V1

Do not implement these unless explicitly asked:

- PhoWhisper local model
- MLX model runtime
- Core ML speech model
- MFA on-device
- Anki `.apkg` import
- Open-ended conversation
- Social features
- Authentication
- Payments
- Long-form speech evaluation

Note: rule-based DSP pitch tracking over an explicit signal (`ToneContourAnalyzer.swift`, see "On-device tone analysis" above) is a different category of thing from "PhoWhisper local model" and "Core ML speech model" above — it's not a trained model and it doesn't transcribe speech to text. It isn't excluded by this list.

---

## Testing checklist

Before considering iOS V1 done:

- App launches with starter lesson.
- Microphone permission flow works.
- Recording can be started and stopped.
- Recording duration is sane.
- Audio file uploads to backend.
- Network failure shows a useful error.
- Backend result renders correctly.
- `passed`, `not_passed`, and `retry_audio_quality` states all render correctly.
- No Azure secret exists in iOS code, plist, or build settings.
- Temporary audio files are cleaned up or intentionally retained only in debug mode.

---

## Design tone

The UI should feel calm, strict, and teacher-like.

Good copy:

```text
Not passed. Your tone was the issue.
```

Avoid vague or demoralizing copy:

```text
Bad pronunciation.
```

The tutor can be strict without being mean.

---

## References for implementers

- Apple AVAudioRecorder documentation: https://developer.apple.com/documentation/avfaudio/avaudiorecorder
- Azure Pronunciation Assessment documentation: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-pronunciation-assessment
- Azure Speech language support: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support
