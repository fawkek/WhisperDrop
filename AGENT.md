# WhisperDrop — agent context

This file is the durable implementation context for future work on WhisperDrop. Read it before changing the project.

## Product goal

WhisperDrop is a focused native macOS utility that creates `.srt` subtitles locally from an audio or video file. The primary flow is deliberately linear:

1. If the model is absent, offer to download it.
2. Show only the file drop/select state.
3. After accepting a file, remove the drop field completely.
4. Show transcription animation, progress, file name, and a live subtitle-line estimate.
5. When complete, show the exact cue count and allow saving UTF-8 SRT.

Do not combine these states into one dashboard. Progressive disclosure is a core requirement.

## Repository and build

- Project root: `/Users/igorsevcenko/Documents/git/WhisperDrop`
- Project type: Swift Package Manager executable packaged as a macOS `.app`
- Minimum deployment: macOS 14
- Main product/process: `WhisperDrop`
- Bundle identifier: `com.igorsevcenko.WhisperDrop`
- Build, bundle, and launch: `./script/build_and_run.sh`
- Build and verify process: `./script/build_and_run.sh --verify`
- Tests: `swift test`
- Codex Run action: `.codex/environments/environment.toml`
- Generated bundle: `dist/WhisperDrop.app`

Always use `script/build_and_run.sh` to review the GUI. Do not launch the raw SwiftPM executable as the normal app.

## Model and privacy

- Engine: open-source WhisperKit `0.18.x` through `argmaxinc/argmax-oss-swift`
- Model: Core ML Whisper Large v3 Turbo
- Model directory: `Models/openai_whisper-large-v3-v20240930`
- Tokenizer directory: `Models/tokenizer`
- The model was copied from the existing MacWhisper installation. Do not move or delete the MacWhisper original.
- Model weights are about 1.5 GB and intentionally ignored by Git via `Models/.gitignore`.
- The app bundle uses a resource symlink to the project `Models` directory during local builds.
- If model files are missing, the app offers an in-app download.
- Transcription is on-device. Media must never be uploaded to a remote service.

`ModelLocator.swift` is the single source of truth for model paths and installation checks.

## Architecture

- `App/WhisperDropApp.swift`: app entry point, foreground activation, scene and commands.
- `Models/SubtitleCue.swift`: final subtitle cue value type.
- `Stores/AppStore.swift`: `@MainActor @Observable` UI state and workflow orchestration.
- `Services/AudioExtractor.swift`: converts unsupported video containers to temporary M4A with AVFoundation.
- `Services/TranscriptionService.swift`: WhisperKit setup, transcription, download, progress, and live line callbacks.
- `Services/ModelLocator.swift`: model/tokenizer locations.
- `Support/SRTFormatter.swift`: deterministic UTF-8 SRT rendering and timestamp formatting.
- `Support/WindowGlass.swift`: narrow AppKit bridge for one continuous translucent window material.
- `Views/ContentView.swift`: mutually exclusive top-level states and drop/setup/result/failure screens.
- `Views/TranscribingView.swift`: transcription-only UI and waveform/progress animation.

Keep business logic out of SwiftUI views. SwiftUI owns presentation; `AppStore` owns user-flow state; services own inference and media processing.

## State machine

`AppStore.Phase` contains:

- `needsModel`
- `ready`
- `downloading`
- `preparing`
- `transcribing`
- `finished`
- `failed(String)`

Only one phase surface should be visible at a time. Dropping another file while work is active is rejected. Escape cancels active work. Command-O opens media. Command-S saves after completion.

## Subtitle correctness

- Output encoding: UTF-8.
- Format: SubRip `.srt`.
- Timestamp format: `HH:MM:SS,mmm`.
- Cues are filtered for non-empty text and positive duration, then sorted by start time.
- WhisperKit segment timestamps are converted from seconds to SRT milliseconds.
- `SRTFormatterTests` verifies timestamp and Unicode behavior.

The live counter during decoding is an estimate derived from draft text because WhisperKit only finalizes segments after processing a decoding window. At completion, it is replaced with the exact final segment count.

## UI and design invariants

- Single-purpose utility: no sidebar.
- Follow the installed `macos-design` skill.
- Use the 8 pt spacing grid; normal window padding is 20 pt and section gaps are 24 pt.
- macOS typography: 17 pt state title, 15 pt secondary heading, 13 pt body, 11–12 pt metadata.
- Use SF Symbols and semantic system/accent colors.
- Light and dark appearance follow the system automatically.
- File drop state, transcription state, and finished state must remain separate.
- Primary actions keep visible shortcut hints where appropriate.
- State transitions use short 150–250 ms macOS-style fades/scales.

## Window glass implementation

The title bar and content must look like one continuous glass surface with no dark top strip or separator.

`GlassWindowConfigurator` installs one `NSVisualEffectView` directly into the AppKit theme frame, below both the SwiftUI content and system traffic lights, with:

- material `.underWindowBackground`
- blending mode `.behindWindow`
- state `.followsWindowActiveState`
- constraints to all four theme-frame edges

`GlassWindowConfigurator` configures the backing `NSWindow` with:

- `.fullSizeContentView`
- no toolbar
- hidden title text
- transparent title bar
- no title-bar separator
- non-opaque, clear window/content backgrounds
- background window dragging enabled

Do not put a second material inside the SwiftUI root view. It creates a visible join because SwiftUI content does not own the title-bar area. Do not re-add `.windowToolbarStyle(.unifiedCompact)` or assign a toolbar without checking the top strip: the unified toolbar adds its own material layer and creates a color mismatch against the main glass panel.

Keep the AppKit bridge limited to window chrome. Do not migrate SwiftUI state or screens into AppKit.

## Validation before handoff

For every change:

1. Run `git diff --check`.
2. Run `swift test`.
3. Run `./script/build_and_run.sh --verify` for UI/window changes.
4. Confirm the process is running and the app bundle was regenerated.
5. Commit only relevant files; model weights must stay untracked/ignored.

Current tests cover formatting, not visual appearance or full-model inference. Do not claim a complete media transcription was tested unless one was actually run.
