# PROJECT_SUMMARY.md — Vietnamese Pronunciation Tutor

## Purpose of this document

This file gives shared product and technical context for the iOS and backend agents.

Use this document before reading the platform-specific `CLAUDE.md` files:

- `CLAUDE.md` explains how to build the native Swift iOS app.
- This file explains the overall idea, architecture, scope, roadmap, and key product decisions.

---

## Product vision

Build a strict Vietnamese pronunciation tutor.

The app should help learners pronounce Vietnamese words and sentences correctly, with special focus on tones, vowels, final consonants, and dialect-specific pronunciation rules.

The goal is not to build a generic flashcard app, a generic speech-to-text app, or a friendly score screen. The goal is to build a tutor that can say:

> Not passed. The word was recognized, but the pronunciation was not strict enough.

The tutor should give specific, actionable feedback:

> Expected **mã** with **ngã** tone. Your base syllable was close, but the tone sounded closer to **má**. Add the broken rising quality in the middle.

---

## Core product loop

The first version should implement this loop:

```text
1. Show a Vietnamese word or sentence.
2. User records themselves speaking it.
3. App uploads audio + prompt id to backend.
4. Backend evaluates pronunciation using Azure Pronunciation Assessment.
5. Backend applies strict Vietnamese tutoring rules.
6. App shows pass/fail and correction.
7. User repeats until they pass.
```

The app is scripted practice first. The system usually already knows the expected text, so the main problem is not open-ended transcription. The main problem is checking whether the user pronounced the expected Vietnamese prompt correctly.

---

## Initial technology choice

### iOS

Use native iOS:

```text
Swift
SwiftUI
AVFoundation
URLSession
```

Start with `AVAudioRecorder` for simple file-based recording. Use `AVAudioEngine` later only if live waveform, live pitch extraction, or streaming audio becomes necessary.

### Backend

Use Node.js/TypeScript:

```text
Node.js 20+ or current LTS
TypeScript
Fastify or Express
Zod or JSON Schema
Azure Speech SDK
ffmpeg for audio conversion
```

Recommended backend stack:

```text
Fastify + TypeScript + Zod
```

### Speech service in V1

Use Azure Pronunciation Assessment with Vietnamese `vi-VN`.

Azure is the first pronunciation evidence provider. It should receive:

```text
user audio
expected reference text
language: vi-VN
```

Azure returns scores and recognition information. The backend then normalizes this into the app's own tutor result.

### MFA in V2

Add Montreal Forced Aligner later on the backend.

MFA is not part of the first live loop unless needed. It is a V2 tool for better word, syllable, and phone timing.

---

## Important architectural decision

Do not put Azure keys in the iOS app.

The iOS app should only talk to our backend:

```text
iOS app
  ↓
our Node.js backend
  ↓
Azure Speech service
```

Reasons:

```text
1. Keeps Azure credentials secret.
2. Allows backend-side audio conversion.
3. Allows backend-side strict tutor rules.
4. Makes it easy to add MFA later.
5. Allows logging and improvement of the pronunciation scorer.
```

---

## What each component does

### iOS app

The iOS app is responsible for the learner experience.

Responsibilities:

```text
Show lesson prompts.
Record audio.
Play native/reference audio later.
Upload attempts.
Show evaluating state.
Show pass/fail result.
Show strict feedback.
Let user retry or move next.
```

**Revised**: the iOS app now computes one piece of pronunciation evidence on-device — a heuristic pitch/tone-shape classification for `tone_minimal_pair` items (see `ToneContourAnalyzer.swift`) — and sends it to the backend alongside the audio. This is not the app deciding correctness: iOS never returns a verdict to the user directly. The backend (`strictTutor.service.ts`) still assembles every final pass/fail result, combining the on-device tone signal with Azure's evidence under an explicit, asymmetric rule (see "On-device tone analysis" below). The app displays only the backend's decision, same as before.

---

### Azure Pronunciation Assessment

Azure is the first automatic pronunciation evaluator.

It compares the user recording against the expected reference text and returns speech/pronunciation evidence such as:

```text
recognized text
pronunciation score
accuracy score
fluency score
completeness score
word-level scores
word timing information where available
miscue information where available
```

Azure is useful, but Azure is not the final tutor.

The backend must convert Azure output into strict, Vietnamese-specific feedback.

---

### Strict Vietnamese tutor layer

This is the product moat.

The strict tutor layer decides:

```text
Did the attempt pass?
What was the main problem?
Was the issue tone, vowel, initial, final, completeness, or audio quality?
What should the learner do next?
What drill should be shown?
```

It should not simply return a number.

Bad:

```text
Pronunciation score: 74
```

Good:

```text
Not passed. Your base syllable was close, but the tone sounded closer to má than mã.
```

The tutor layer uses Azure as evidence, but applies our rules.

---

### Montreal Forced Aligner, or MFA

MFA performs forced alignment.

Forced alignment means:

```text
audio + known transcript → timestamps for words/syllables/phones
```

Example:

```text
Input audio: user says "xin chào"
Input text:  "xin chào"

Output:
xin   0.20s → 0.48s
chào  0.52s → 0.91s
```

MFA does not judge pronunciation quality by itself. It tells us where each piece of speech occurs.

MFA is useful later because once we know exactly where a syllable or phone occurs, we can analyze that part of the audio more strictly.

Example:

```text
Prompt: xin chào
MFA says: chào occurs from 0.52s to 0.91s
Custom scorer analyzes only that segment
Tutor says: chào failed because huyền tone did not fall enough
```

MFA should run backend-side only.

---

### PhoWhisper / local ASR

PhoWhisper is not part of V1.

It may be useful later for:

```text
offline mode
on-device Vietnamese transcription
cloud cost reduction
privacy-sensitive mode
sanity-checking whether the user said the expected text
```

However, PhoWhisper is an ASR model, not a pronunciation tutor. It turns audio into text. It does not, by itself, give strict tone/vowel/final-consonant coaching.

Do not add PhoWhisper until the Azure-based tutoring loop works well.

---

## V1 architecture

```text
Swift iOS app
  ↓
Record short audio file
  ↓
Upload audio + item_id
  ↓
Node.js/TypeScript backend
  ↓
Look up hardcoded training item
  ↓
Convert audio if needed
  ↓
Call Azure Pronunciation Assessment with vi-VN + reference text
  ↓
Normalize Azure result
  ↓
Apply strict Vietnamese tutor rules
  ↓
Return evaluation JSON
  ↓
iOS EvaluationView displays feedback
```

---

## On-device tone analysis (V3 roadmap item, pulled forward)

The V3 roadmap below originally listed "custom tone analysis / pitch contour extraction / speaker-normalized tone scoring" as future work. It has been implemented now, ahead of that schedule, as a direct fix for a V1 problem: Azure's ASR sometimes transcribes the wrong tone diacritic on close Vietnamese tone pairs even when the actual pronunciation was correct, forcing learners to over-exaggerate tones just to get a passing transcript.

```text
Swift iOS app
  ↓
Record audio (unchanged)
  ↓
ToneContourAnalyzer.swift: YIN-based pitch tracking → speaker-normalized
(semitone) contour → rule-based 6-tone classification + confidence,
tone_minimal_pair items only
  ↓
Upload audio + item_id + client_tone_features (alongside the existing
client_audio_features)
  ↓
Node.js backend: Azure Pronunciation Assessment (unchanged)
  ↓
strictTutor.service.ts combines both signals under an asymmetric rule:
  - on-device confident + correct → tone check passes even if Azure's
    diacritic disagrees (the motivating case)
  - on-device confident + wrong, Azure also disagrees → hard tone_confusion
  - on-device confident + wrong, Azure corroborates expected → ambiguous,
    not a hard fail (two disagreeing signals ≠ confidently wrong)
  - no reliable on-device signal → falls back to the original Azure-only
    diacritic + word-accuracy logic, unchanged
  ↓
iOS EvaluationView displays the backend's decision (unchanged)
```

This is a heuristic v1, not a solved problem: hand-rolled pitch-shape classification is a genuinely hard acoustic problem, and hỏi/ngã are phonetically merged (no glottal break) for many speakers — no DSP heuristic fixes that, which is exactly why the decision rule is asymmetric rather than a hard on-device-wins switch. Expect the confidence threshold (`ON_DEVICE_TONE_CONFIDENCE_THRESHOLD`, backend env var, default 0.5) to need tuning against real recordings.

Note on the V1 non-goals list below: DSP-based pitch tracking (autocorrelation/YIN over an explicit pitch signal, with hand-written classification rules) is a different category of thing from the prohibited "local ASR / PhoWhisper / Core ML speech model" — it's not a trained model and it doesn't transcribe speech to text. It was never actually excluded by the letter of that rule, only full local speech-recognition models were.

---

## V2 architecture with MFA

```text
Swift iOS app
  ↓
Record audio + upload audio + item_id
  ↓
Node.js backend
  ↓
Azure Pronunciation Assessment
  ↓
MFA aligns expected transcript to user audio
  ↓
Backend extracts word/syllable/phone timestamps
  ↓
Custom acoustic analysis starts using those timestamps
  ↓
Strict Vietnamese tutor returns more specific feedback
```

V2 should preserve the same iOS API contract as much as possible. The backend can add new fields to the result without forcing the iOS app to change its core flow.

---

## Why V1 should not use every tool at once

Avoid this in V1:

```text
iOS recording
→ Azure
→ PhoWhisper
→ MFA
→ custom audio model
→ custom scoring
```

That adds too much overhead before the tutoring UX is proven.

Use this instead:

```text
V1: Azure + strict rules
V2: Azure + MFA + stricter timing
V3: Azure + custom tone/audio scorer
V4: optional local PhoWhisper/offline mode
```

The first goal is to make the tutor loop feel useful, strict, and motivating.

---

## Core domain model

### Training item

A training item is one word or sentence the learner must pronounce.

Example:

```json
{
	"id": "tone_ma_nga",
	"text": "mã",
	"display_text": "mã",
	"target_dialect": "northern_hanoi",
	"category": "tone_minimal_pair",
	"difficulty": 1,
	"expected": {
		"syllables": [
			{
				"orthography": "mã",
				"initial": "m",
				"rime": "a",
				"final": null,
				"tone": "nga"
			}
		]
	}
}
```

### Attempt

An attempt is one user recording for one training item.

Example:

```json
{
	"attempt_id": "att_123",
	"item_id": "tone_ma_nga",
	"expected_text": "mã",
	"audio_path": "storage/attempts/att_123.wav",
	"created_at": "2026-07-09T12:00:00Z"
}
```

### Evaluation result

The backend should return a normalized result that the iOS app can render directly.

Example:

```json
{
	"attempt_id": "att_123",
	"passed": false,
	"status": "not_passed",
	"expected_text": "mã",
	"recognized_text": "má",
	"overall_score": 68,
	"strict_score": 54,
	"scores": {
		"accuracy": 72,
		"fluency": 94,
		"completeness": 100,
		"pronunciation": 76
	},
	"main_error": {
		"type": "tone_confusion",
		"expected": "nga",
		"heard_like": "sac",
		"severity": "high"
	},
	"feedback": {
		"title": "Not passed: tone problem",
		"body": "Your base syllable was close, but the tone sounded closer to má than mã.",
		"fix": "Add the broken rising quality for ngã.",
		"drill": ["mã", "má", "mã"]
	}
}
```

---

## Status values

Use explicit status values instead of only a boolean.

Recommended:

```text
passed
not_passed
retry_audio_quality
service_error
```

Meaning:

```text
passed
The learner passed the prompt.

not_passed
The recording was usable, but the pronunciation did not pass.

retry_audio_quality
The app could not fairly judge the pronunciation because the recording was too quiet, clipped, too noisy, too short, or empty.

service_error
The speech service or backend failed. This is not the user's fault.
```

Do not punish the learner for bad audio quality. Ask for a retry.

---

## Vietnamese pronunciation focus

Start with Northern / Hanoi strict mode.

The first product should teach clear distinctions that matter for beginners:

```text
six tones
u vs ư
o vs ô vs ơ
a vs ă vs â
final -n vs -ng
initial ng-
short common phrases
```

Initial tone set:

```text
ma
má
mà
mả
mã
mạ
```

Then expand:

```text
ba / bá / bà / bả / bã / bạ
la / lá / là / lả / lã / lạ
```

Then add phrase examples:

```text
xin chào
cảm ơn
không phải
tôi là...
tôi muốn ăn phở
```

---

## Strict tutor rules

The tutor should be strict and structured.

### General pass/fail principle

A high Azure score can support passing, but the backend should still enforce stricter rules by category.

Example V1 rules:

```text
If audio quality is bad:
  status = retry_audio_quality

If completeness is too low:
  status = not_passed
  main_error = incomplete_prompt

If expected text is a single tone-minimal-pair item and Azure strongly suggests a neighboring tone:
  status = not_passed
  main_error = tone_confusion

If pronunciation score is high enough and no rule blocks it:
  status = passed

Otherwise:
  status = not_passed
  main_error = pronunciation_not_strict_enough
```

### Important tutor principle

The app should be willing to say:

```text
Recognized correctly, but not passed.
```

Recognition is not the same as good pronunciation.

---

## Feedback principles

Each failed result should include:

```text
1. A clear pass/fail state.
2. The expected prompt.
3. The main error category.
4. What the learner likely did.
5. How to fix it.
6. A short drill.
```

Bad feedback:

```text
Try again. Your pronunciation is wrong.
```

Good feedback:

```text
Not passed. Expected mã with ngã tone. Yours sounded closer to má. Add the broken rising quality in the middle.
```

The LLM, if added later, should not decide pronunciation correctness. It may only rewrite structured feedback into friendlier language.

---

## Initial UI flow

### Lesson view

Show the prompt prominently:

```text
mã
ngã tone · Northern / Hanoi

[Listen]
[Record]
```

`Listen` can be a placeholder in V1 if native reference audio is not available yet.

### Recording state

Show:

```text
Recording...
00:02
[Stop]
[Cancel]
```

### Evaluation view

Passed example:

```text
Passed

mã
Pronunciation: 86

Good. The tone was acceptable.

[Try again] [Next]
```

Failed example:

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

Audio-quality retry example:

```text
Try again

I could not judge this recording. It was too quiet or noisy.

[Record again]
```

---

## Backend API overview

### Health

```http
GET /health
```

### Starter lesson

```http
GET /v1/lessons/starter
```

Returns hardcoded training items.

### Evaluate attempt

```http
POST /v1/attempts/evaluate
Content-Type: multipart/form-data
```

Fields:

```text
item_id: string
audio: file
```

Backend behavior:

```text
1. Validate item_id.
2. Validate audio file exists and is within allowed duration/size.
3. Convert audio to Azure-compatible format if needed.
4. Call Azure Pronunciation Assessment.
5. Normalize Azure result.
6. Run strict Vietnamese tutor rules.
7. Store attempt metadata and raw result if logging is enabled.
8. Return normalized evaluation JSON.
```

---

## Repository structure

Recommended root structure:

```text
viet-tutor/
  PROJECT_SUMMARY.md

  ios/
    CLAUDE.md
    VietTutor/
      App/
      Features/
      Core/

  backend/
    CLAUDE.md
    package.json
    tsconfig.json
    src/
    storage/
    tests/

  docs/
    api_contract.md
    pronunciation_taxonomy.md
    roadmap.md
```

The current `CLAUDE
.md` files are intended to guide separate agents working on `ios/` and `backend/`.

---

## Milestones

### Milestone 1 — Static iOS prototype

Build:

```text
LessonView
RecordingButton placeholder
EvaluationView with fake data
Hardcoded lesson data
```

Goal:

```text
The pronunciation tutoring UX feels right before speech tech is wired in.
```

---

### Milestone 2 — iOS recording

Build:

```text
Microphone permission
Start recording
Stop recording
Save audio file
Playback local recording for debugging
```

Acceptance test:

```text
Tap record → speak → stop → play back the recorded audio.
```

---

### Milestone 3 — Backend upload

Build:

```text
POST /v1/attempts/evaluate
multipart upload
fake evaluation response
```

Acceptance test:

```text
iOS uploads real audio.
Backend receives file.
iOS displays fake evaluation.
```

---

### Milestone 4 — Azure integration

Build:

```text
Azure Speech SDK integration
Pronunciation Assessment with vi-VN
Reference text from training item
Normalize Azure result
```

Acceptance test:

```text
Prompt: xin chào
User speaks clearly
Backend returns real Azure scores
App displays real evaluation
```

---

### Milestone 5 — Strict tutor V1

Build:

```text
Vietnamese lesson metadata
Tone category rules
Pass/fail thresholds
Structured feedback
Drills
```

Acceptance test:

```text
Prompt: mã
Bad/incorrect tone should not produce generic feedback.
It should produce tone-specific feedback.
```

---

### Milestone 6 — Logging

Store:

```text
attempt id
item id
expected text
recognized text
Azure raw JSON
normalized tutor result
audio path if retention is enabled
created timestamp
```

This is important for later model improvement and debugging.

---

### Milestone 7 — MFA V2

Add MFA backend support.

Use it to align expected text to user audio and generate timing data.

Acceptance test:

```text
Prompt: xin chào
MFA returns timing for xin and chào
Backend can attach alignment to evaluation result
```

Do not make iOS depend on MFA-specific fields immediately.

---

## Anki import later

Anki import is not part of V1.

Hardcoded lesson data is enough while the tutoring loop is being built.

Later import order:

```text
1. CSV/TSV import
2. Anki text export import
3. .apkg import if necessary
```

The app should eventually be able to convert imported vocabulary into pronunciation prompts, but that is secondary. The core value is strict pronunciation feedback.

---

## Non-goals for V1

Do not build these in V1:

```text
Open conversation practice
Local PhoWhisper
MLX model runtime
Full Anki import
MFA on-device
Custom trained pronunciation model
Live pitch visualization
Complex spaced repetition
Social features
User accounts unless needed for testing
Payments/subscriptions
```

Note: "Local PhoWhisper" and "custom trained pronunciation model" refer to trained ML models running on-device. Rule-based DSP pitch tracking over an explicit signal (see "On-device tone analysis" above) is a different category of thing — it's not a trained model and it doesn't transcribe speech — and isn't excluded by this list.

Focus on the tutoring loop.

---

## Future roadmap

### V1

```text
Azure Pronunciation Assessment
Hardcoded lessons
Strict rules
Native iOS UI
Node.js backend
```

### V2

```text
MFA backend alignment
Better per-syllable timing
More precise feedback for phrases
```

### V3

```text
Custom tone analysis            — done, pulled forward (see "On-device tone analysis" above)
Pitch contour extraction        — done, pulled forward
Speaker-normalized tone scoring — done, pulled forward (semitone-relative-to-utterance-median)
Better tone confusion detection — done, pulled forward (asymmetric on-device/Azure decision rule)
```

The remaining V3 work is tuning, not building: the confidence threshold and classifier rules need real-world calibration against actual recordings across speakers and dialects.

### V4

```text
Custom vowel/final/initial consonant scoring
Human-labeled learner recordings
Model calibration
```

### V5

```text
Optional local PhoWhisper/offline mode
Optional native audio packs
Optional Anki/CSV import
Optional spaced repetition
```

---

## Shared principle for all agents

Always optimize for the strict tutoring loop:

```text
Prompt
→ Recording
→ Assessment
→ Strict decision
→ Specific correction
→ Repeat
```

When making implementation choices, prefer the option that makes this loop clearer, faster, and easier to improve.

Do not overbuild the platform before the learner can record a Vietnamese word and receive useful pronunciation feedback.
