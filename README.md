# SimpleNoteTaker

A macOS app for recording meetings, transcribing them locally, and summarizing them with on-device or local LLMs. Everything stays on your machine — no cloud calls, no audio leaves the box.

## What it does

- **Captures both sides of a meeting**: microphone (you) and system audio (everyone else, including when you're on AirPods) via ScreenCaptureKit.
- **Live transcription of both speakers** in the menu bar / main window while recording — your mic *and* the other participants' system audio are transcribed live and shown as labeled "You" / "Them" turns (Apple `SpeechAnalyzer`). System audio stays clean even when your own mic drops into low-quality Bluetooth call mode.
- **Import existing recordings**: drop in an audio *or* video file (mp4/mov are extracted via ffmpeg) and it runs through the same transcribe → summarize → save pipeline, with a live progress bar and a Cancel button.
- **Final transcript** written to separate files. Pluggable: Apple `SpeechAnalyzer` (default, no setup) or **mlx-whisper** (`whisper-base-mlx` / `whisper-large-v3-turbo` / `whisper-large-v3-mlx`) for higher accuracy.
- **Structured summary** (title, headline, summary, key points, action items, decisions). Pluggable provider: Apple **FoundationModels** (default, no setup) or any **Ollama** model running locally. For long meetings that exceed Apple's ~4K-token on-device context, Settings suggests large-context Ollama models (Llama 3.1 8B at 128K, Qwen 2.5 at 32K).
- **Per-meeting detail window** with the summary cards. Regenerate dropdown lets you re-run the summary against any installed model without changing your default. Undo to restore the previous version.
- **Library of past meetings** as cards with title, date, duration, and summary snippet.

## Output layout

For each meeting under `~/Documents/Meetings/`:

```
meeting-2026-05-03-101530-summary.md     # headline, summary, key points, actions, decisions
meeting-2026-05-03-101530-transcript.md  # raw timestamped lines, labeled by speaker (me/them)
meeting-2026-05-03-101530-reading.md     # YAML frontmatter + clean prose — built for agent consumption
meeting-2026-05-03-101530-transcript.json # structured turn-level data (speaker/start/end/text) for agents
```

Audio (`.m4a`) goes to `~/Documents/Meetings/Audio_files/` if you toggle "Keep audio files" in Settings; otherwise it's written to a temp directory and deleted after transcription.

`reading.md` is designed to be fed to downstream agents, so it leads with a stable YAML frontmatter block (treat the keys as an API — additive changes are safe, renames/removals are breaking):

```yaml
---
title: "Q3 roadmap sync"
date: 2026-05-03T10:15:30Z
duration: "30:30"
duration_seconds: 1830
speakers: [me, them]
word_count: 4213
---
```

## Requirements

- **macOS 26 (Tahoe) or later** — uses `SpeechAnalyzer` and `FoundationModels`, both new in 26.
- **Xcode 26+** to build.
- **Apple Silicon Mac** for FoundationModels and mlx-whisper.

Optional (only if you want non-default providers):

- `pip install mlx-whisper` — for higher-accuracy transcription. Requires `brew install ffmpeg` (mlx-whisper pipes audio through ffmpeg internally).
- [Ollama](https://ollama.com) running locally — for non-Apple summarization, and the recommended choice for meetings longer than ~10 minutes (Apple's on-device model has a ~4K-token context that long transcripts overflow). Pull a large-context model with `ollama pull llama3.1:8b` (128K context, recommended starter).

## Build & run

1. Open `SimpleNoteTaker.xcodeproj` in Xcode.
2. In *Signing & Capabilities* for both **SimpleNoteTaker** and **SimpleNoteTakerTests** targets, set the team to your Apple ID (a free Personal Team works fine — no paid Developer Program needed).
3. ⌘R to build and run.

From the command line:

```bash
xcodebuild -project SimpleNoteTaker.xcodeproj -scheme SimpleNoteTaker \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild -project SimpleNoteTaker.xcodeproj -scheme SimpleNoteTaker \
  -destination 'platform=macOS' test
```

## Permissions

On first launch macOS will ask for:

- **Microphone** — to record your voice.
- **Speech Recognition** — for live transcription via `SpeechAnalyzer`.
- **Screen Recording** — required by ScreenCaptureKit to capture system audio (the only macOS API that exposes it). After granting, you may need to quit and relaunch once.

With a stable signing identity (Personal Team works), grants persist across rebuilds.

## Architecture

```
mic ──► AVAudioEngine tap ──► .m4a + LiveTranscriber (SpeechAnalyzer) ─┐
sys ──► ScreenCaptureKit ───► .m4a + LiveTranscriber (SpeechAnalyzer) ─┴─► merged "You"/"Them" live partials
                                                  │
                                            on Stop ▼
                              FileTranscribing  (Apple file pass / mlx-whisper subprocess)
                                                  │
                                                  ▼
                                  summary.md + transcript.md + reading.md
                                                  │
                                       Summarizing (Apple FM / Ollama)
                                                  │
                                                  ▼
                                       summary.md (rewritten with sections)
```

Imported files (`ImportSession`) skip the capture stage and enter at `FileTranscribing`; video containers are extracted to audio via ffmpeg first.

mlx-whisper subprocesses are launched at `.userInitiated` QoS (so they stay on performance cores / GPU), tracked so they're terminated on app quit or Cancel, and their output is hardened against Python `NaN`/`Infinity` JSON tokens and repetition-loop runs (collapsed to `[inaudible]`).

## Settings

Settings re-probes provider availability whenever a relevant setting changes (no relaunch needed), and shows dense per-row status — colored ✓/⚠︎ pills, download progress, and on-disk cache sizes.

- **Notes folder** — where summary + transcript + reading .md files go (default `~/Documents/Meetings`).
- **Audio Transcription** — Apple SpeechAnalyzer (default) or MLX Whisper. The model picker lists presets plus any `mlx-community/whisper*` models already in your Hugging Face cache (honoring `HF_HOME` / `HF_HUB_CACHE`), with green checkmarks for downloaded ones. Advanced: install-path override and a language code (defaults to `en`; blank = auto-detect, which adds ~3–5s per import).
- **Summarization** — Apple Foundation Models (default) or Ollama (with base URL + model picker, suggested large-context models, and one-click pull).
- **Audio retention** — keep `.m4a` files after transcription, off by default.

## Tests

Swift Testing (`import Testing`) suites under `SimpleNoteTakerTests/`. ~98 tests covering paths, settings, file naming, markdown round-tripping, transcript merging, summary parsing, library scanning, recording controller state, mlx-whisper JSON parsing, etc.

## Status

Working day-to-day app for the author. Not in the App Store, not notarized. If you want to share with others, you'd need a paid Developer Program account and a notarization step.

## Built with [Claude Code](https://claude.com/claude-code)
