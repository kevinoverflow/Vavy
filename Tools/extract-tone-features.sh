#!/bin/sh
# Usage: Tools/extract-tone-features.sh <file.wav>... > tone-features.jsonl
#
# Compiles the app's tone analyzer sources (unchanged, with the app's default MainActor
# isolation) into a small macOS command-line tool and runs it on the given 16 kHz mono
# 16-bit PCM WAV files. See vavy-backend/eval/README.md.
set -eu

repo="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${TMPDIR:-/tmp}/vavy-extract-tone-features"
mkdir -p "$build_dir"

swiftc -O -swift-version 5 -default-isolation MainActor \
  -o "$build_dir/extract-tone-features" \
  "$repo/Vavy/Core/Audio/PitchEstimator.swift" \
  "$repo/Vavy/Core/Audio/ToneContourAnalyzer.swift" \
  "$repo/Vavy/Core/Audio/PCM16WAVFile.swift" \
  "$repo/Vavy/Core/Models/AppError.swift" \
  "$repo/Vavy/Core/Models/LessonModels.swift" \
  "$repo/Tools/ExtractToneFeatures/main.swift"

exec "$build_dir/extract-tone-features" "$@"
