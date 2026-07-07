# WhisperDrop — agent context

This file is the durable implementation context for future work on WhisperDrop. Read it before changing the project.

## Product goal

WhisperDrop is a focused native macOS utility that creates `.srt` subtitles locally from an audio or video file. The primary flow is deliberately linear:

1. If the model is absent, offer to download it.
2. Show only the file drop/select state.
3. After accepting a file, remove the drop field completely.
4. Show transcription animation, progress, and file name. Do not show a live line count.
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
- App icon source: `Assets/AppIcon.png`
- App icon catalog: `Assets/Assets.xcassets/AppIcon.appiconset`

Always use `script/build_and_run.sh` to review the GUI. Do not launch the raw SwiftPM executable as the normal app.

The build script compiles the icon catalog with `actool`, copies `Assets.car` and `AppIcon.icns` into the bundle, and declares both `CFBundleIconName` and `CFBundleIconFile`. Keep the 1024 px source image; regenerate all catalog sizes from it when the icon changes.

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
- `Services/TranscriptionService.swift`: WhisperKit setup, transcription, download, and progress callbacks.
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
- Whisper control and timestamp tokens in the form `<|...|>` must be stripped from cue text before display or SRT export.
- WhisperKit segment timestamps are converted from seconds to SRT milliseconds.
- `SRTFormatterTests` verifies timestamp and Unicode behavior.

Do not show a live subtitle-line counter during decoding: WhisperKit finalizes segments in batches, so an intermediate count can remain at zero or be misleading. Show the exact final cue count only on the completed state.

Transcription progress must use `WhisperKit.progress.fractionCompleted`. `TranscriptionProgress.timings.inputAudioSeconds` belongs to decoder timing statistics and is not the current playback position.

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

Some macOS versions draw an additional `NSTitlebarView` background above the theme-frame material. To prevent a dark strip behind the traffic lights, the configurator also installs the same material directly in `standardWindowButton(.closeButton).superview`, positioned below the buttons. Keep both identifiers (`WhisperDrop.WindowGlass` and `WhisperDrop.TitlebarGlass`) to avoid duplicate layers when SwiftUI recreates the representable.

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

## Stabilization backlog before release

Treat the following as required release work, not optional polish:

### Transcription correctness

- Run end-to-end tests on short, long, silent, noisy, multilingual, variable-frame-rate, and multi-audio-track media.
- Compare exported SRT timestamps against playback and verify monotonic, non-overlapping cues.
- Define cue splitting limits for maximum characters, reading speed, and line count instead of relying only on raw Whisper segments.
- Detect and suppress repeated hallucinated phrases during silence or credits.
- Preserve exact final cue count separately from the live draft estimate.
- Add regression fixtures and tests for Russian, English, mixed speech, punctuation, Unicode, and hour-long timestamps.

### Reliability and cancellation

- Make cancellation propagate into WhisperKit inference and AVFoundation export, not only into the outer Swift task.
- Remove every temporary audio file on success, failure, cancellation, and app termination.
- Handle sleep/wake, low disk space, model load failure, memory pressure, corrupted media, and interrupted downloads.
- Prevent concurrent jobs or explicitly implement a queue.
- Persist enough job state to recover gracefully after a crash without falsely claiming completion.

### Progress and user feedback

- Replace the current timing approximation with progress based on processed audio position or WhisperKit windows.
- Keep model loading, audio conversion, transcription, and finalization as distinct measurable phases.
- Show actionable errors rather than raw framework messages.
- Add a clear first-run model size/free-space warning and resumable download UI.

### Model management

- For release, store models in the user Application Support directory, never through the project resource symlink.
- Download from the official Argmax/WhisperKit source; do not redistribute the model copied from MacWhisper.
- Verify downloaded files with expected size and cryptographic checksum before loading.
- Support resume, atomic installation, migration, corruption recovery, and deletion from settings.
- Document model and WhisperKit licenses in the app and distribution package.

### Sandbox and file access

- Create a real Xcode macOS app target before App Store distribution.
- Enable App Sandbox with only user-selected file read/write and outbound network access for model download/license checks.
- Use security-scoped access correctly for dropped/opened files and release it after processing.
- Store persistent user data only in sandbox-safe Application Support locations.

### Packaging and security

- Remove ad-hoc/debug signing and `com.apple.security.get-task-allow` from release artifacts.
- Enable Hardened Runtime and sign every nested executable/framework with the correct identity.
- For direct distribution, sign with Developer ID Application, notarize, staple, and validate with `codesign`, `spctl`, and `stapler`.
- For Mac App Store, use Apple Distribution, provisioning, App Sandbox, App Store Connect validation, and Review.
- Replace the local model symlink in release bundles; it is development-only.
- Add semantic version, build number, copyright, privacy information, and update policy.

### Compatibility and performance

- Decide whether release support is Apple Silicon only or universal; current local output is arm64.
- Measure model load time, real-time factor, peak memory, thermal behavior, and battery impact on supported Macs.
- Verify Core ML behavior after OS updates and on the minimum supported macOS version.
- Keep the UI responsive while loading and transcribing multi-hour files.

### UI, accessibility, and localization

- Test glass/titlebar rendering in light mode, dark mode, inactive windows, Reduce Transparency, Increase Contrast, and Reduce Motion.
- Add VoiceOver labels, keyboard focus order, full keyboard operation, and sufficient contrast.
- Localize all visible strings instead of leaving Russian strings in source.
- Verify icon appearance at all required sizes in Dock, Finder, app switcher, About, and distribution storefronts.

### Distribution readiness

- Prepare privacy policy, support URL/email, screenshots, description, release notes, and App Store privacy answers.
- Add automated CI for clean release builds, tests, signing checks, and artifact validation.
- Maintain a release checklist that includes a clean-machine install and first-run model download.
- Do not call a build stable until a notarized/App Store-style artifact has completed the same end-to-end transcription tests as development builds.
