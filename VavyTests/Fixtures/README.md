# Test audio fixtures

16 kHz mono 16-bit PCM WAVs converted from the repository's `tones/*.mp3` with
`afconvert -f WAVE -d LEI16@16000 -c 1`.

| Fixture | Source file |
|---|---|
| `ref-label-ngang.wav` | `tones/má-ngang.mp3` |
| `ref-label-huyen.wav` | `tones/ma-huyền.mp3` |
| `ref-label-sac.wav` | `tones/mà-sắc.mp3` |
| `ref-label-nga.wav` | `tones/ma-ngã.mp3` |
| `ref-label-hoi.wav` | `tones/mả-hỏi.mp3` |
| `ref-label-nang.wav` | `tones/mạ-nặng.mp3` |

**The labels are unverified.** Fixtures are named after the tone *name* in each source filename. In four of the six files the spelling contradicts that name (e.g. `má-ngang`: "má" is sắc). A native Northern listener must confirm the actual tone of each recording before these are used as ground truth. Until then they are characterization fixtures only: `ToneContourAnalyzerTests` pins what the analyzer outputs on them, not what it should output.

All six come from a single speaker of unknown provenance; they say nothing about how the analyzer generalizes.
