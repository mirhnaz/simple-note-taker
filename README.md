# SimpleNoteTaker

A macOS app for recording meetings, transcribing them locally, and summarizing them with on-device or local LLMs. Everything stays on your machine — no cloud calls, no audio leaves the box.

## What it does

- **Captures both sides of a meeting**: microphone (you) and system audio (everyone else, including when you're on AirPods) via ScreenCaptureKit.
- **Live transcription in the menu bar / main window** while recording (Apple `SpeechAnalyzer`).
- **Final transcript** written to a separate file. Pluggable: Apple `SpeechAnalyzer` (default, no setup) or **mlx-whisper** with `mlx-community/whisper-large-v3-turbo` for higher accuracy.
- **Structured summary** (title, headline, summary, key points, action items, decisions). Pluggable provider: Apple **FoundationModels** (default, no setup) or any **Ollama** model running locally.
- **Per-meeting detail window** with the summary cards. Regenerate dropdown lets you re-run the summary against any installed model without changing your default. Undo to restore the previous version.
- **Library of past meetings** as cards with title, date, duration, and summary snippet.

## Output layout

For each meeting under `~/Documents/Meetings/`:

```
meeting-2026-05-03-101530-summary.md     # headline, summary, key points, actions, decisions
meeting-2026-05-03-101530-transcript.md  # raw timestamped lines
```

Audio (`.m4a`) goes to `~/Documents/Meetings/Audio_files/` if you toggle "Keep audio files" in Settings; otherwise it's written to a temp directory and deleted after transcription.

## Requirements

- **macOS 26 (Tahoe) or later** — uses `SpeechAnalyzer` and `FoundationModels`, both new in 26.
- **Xcode 26+** to build.
- **Apple Silicon Mac** for FoundationModels and mlx-whisper.

Optional (only if you want non-default providers):

- `pip install mlx-whisper` — for higher-accuracy transcription. Requires `brew install ffmpeg` (mlx-whisper pipes audio through ffmpeg internally).
- [Ollama](https://ollama.com) running locally — for non-Apple summarization. Pull any model with `ollama pull llama3.1` (recommended starter).

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
mic ──► AVAudioEngine tap ──► .m4a + LiveTranscriber (Apple SpeechAnalyzer) ──► live partials
sys ──► ScreenCaptureKit ─► .m4a
                                                  │
                                            on Stop ▼
                              FileTranscribing  (Apple file pass / mlx-whisper subprocess)
                                                  │
                                                  ▼
                                          summary.md + transcript.md
                                                  │
                                       Summarizing (Apple FM / Ollama)
                                                  │
                                                  ▼
                                       summary.md (rewritten with sections)
```

## Settings

- **Notes folder** — where summary + transcript .md files go (default `~/Documents/Meetings`).
- **Audio Transcription** — Apple SpeechAnalyzer (default) or MLX Whisper (with model name + install path override + ffmpeg/cache status).
- **Summarization** — Apple Foundation Models (default) or Ollama (with base URL + model picker).
- **Audio retention** — keep `.m4a` files after transcription, off by default.

## Tests

Swift Testing (`import Testing`) suites under `SimpleNoteTakerTests/`. ~98 tests covering paths, settings, file naming, markdown round-tripping, transcript merging, summary parsing, library scanning, recording controller state, mlx-whisper JSON parsing, etc.

## Status

Working day-to-day app for the author. Not in the App Store, not notarized. If you want to share with others, you'd need a paid Developer Program account and a notarization step.

## Built with [Claude Code](https://claude.com/claude-code)
