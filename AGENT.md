# WhisperDrop — agent context

- About shows the purpose, version, build, embedded Git commit, `https://x.com/fawkek_obj`, and `https://github.com/fawkek/WhisperDrop`.
- Release metadata defaults to version `0.1.0`, build `1`, and the current 12-character commit. Override with `APP_VERSION` and `APP_BUILD`.
- `./script/build_and_run.sh --package` builds Release, signs with `DEVELOPER_ID_APPLICATION` when set (otherwise ad hoc), verifies the signature, and creates `dist/WhisperDrop-<version>-macOS.zip`.
- When both `DEVELOPER_ID_APPLICATION` and `NOTARY_PROFILE` are set, packaging submits the ZIP with `notarytool`, staples and validates the app, then recreates the final ZIP.

This file is the durable implementation context for future work on WhisperDrop. Read it before changing the project.

## Product goal

WhisperDrop is a focused native macOS utility that creates subtitle files locally from an audio or video file. The primary flow is deliberately linear:

1. If the model is absent, offer to download it.
2. Show only the file drop/select state.
3. After accepting a file, remove the drop field completely.
4. Show transcription animation, progress, and file name. Do not show a live line count.
5. When complete, show the exact cue count, format and encoding controls, and allow saving the selected output.
6. From the finished state, offer subtitle proofreading as a separate optional flow.

Speech language is always auto-detected. The finished state offers SRT, WebVTT, ASS, and TXT plus common encodings. Defaults remain SRT and UTF-8; WebVTT is always UTF-8.
Format and encoding controls must open their choices directly. Use direct menu buttons with a checkmark for the current value; do not wrap a Picker inside a Menu or draw a second custom disclosure arrow.

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

The current icon is a dark navy macOS tile with a large, perfectly symmetrical blue-to-cyan audio waveform made from exactly 11 separate rounded vertical bars. Do not restore the earlier dense-waveform, hearing-aid, or television concepts unless the user explicitly requests another redesign.

## Model and privacy

- Engine: open-source WhisperKit `0.18.x` through `argmaxinc/argmax-oss-swift`
- Model: full uncompressed Core ML OpenAI Whisper Large v3, build `openai_whisper-large-v3-v20240930`
- Runtime model directory: `~/Library/Application Support/WhisperDrop/Models/openai_whisper-large-v3-v20240930`
- Development tokenizer source: `Models/tokenizer`; packaged tokenizer: `WhisperDrop.app/Contents/Resources/Tokenizer`
- The model was copied from the existing MacWhisper installation. Do not move or delete the MacWhisper original.
- Official download source: `https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930`.
- The official repository reports the model download as about 1.62 GB. Do not silently switch back to the 627 MB 4-bit compressed variant.
- Model weights are intentionally ignored by Git via `Models/.gitignore`.
- The tokenizer is about 2.7 MB, is required, and is not generated per user. The build script bundles the official compatible tokenizer JSON files in app resources; downloaded model weights live separately in Application Support.
- The app bundle must not use a resource symlink to the project `Models` directory. Writing through that symlink into `Documents` causes repeated macOS privacy prompts and unreliable progress reads.
- If model files are missing, the app offers an in-app download.
- The model setup screen intentionally stays concise: localized state title, `OpenAI Whisper Large v3`, short localized accuracy/local-processing description, total size, downloaded bytes, and percentage. Keep the technical variant identifier in code/docs, not as a duplicate UI line.
- Download model files through the app's resumable `URLSessionDataDelegate` service. It reports exact cumulative bytes for every received network block and resumes `.partial` files with HTTP `Range`; do not estimate progress or poll the filesystem. Legacy WhisperKit/Hugging Face partial downloads are migrated once before the first new transfer. Keep only volume, total, and percentage visible; do not add speed or ETA unless explicitly requested.
- Retry interrupted model transfers up to five times with exponential backoff, always resuming the existing `.partial` file. Treat the model as installed only when every manifest file has its exact expected byte size. Download failures stay on the model setup screen with a localized retry action; never route them through the subtitle-transcription failure screen.
- A resumed transfer must receive HTTP 206. If a CDN returns HTTP 200 for a ranged request, cancel and retry without truncating or replacing the `.partial` file; downloaded bytes must never move backward.
- Recover an oversized weight file only when the SHA-256 of its official-length prefix matches the Hugging Face LFS hash: truncate the verified duplicate tail and remove the stale `.partial`. Never repair an oversized file based on size alone.
- Cancelling a model download must always return to `needsModel`, even if cached or partially downloaded files exist. A stale download task must never advance the UI to `ready` after cancellation.
- Transcription is on-device. Media must never be uploaded to a remote service.
- Optional subtitle proofreading is local-only. It downloads the Apache-2.0 `basecompute/Qwen3-0.6B` Q4 BaseRT model (about 430 MB) to `~/Library/Application Support/WhisperDrop/Models/TextImprovementBaseRT`; it is never required for basic subtitle creation.
- Proofreading uses the bundled BaseRT runtime (`Runtime/BaseRT` during development; `WhisperDrop.app/Contents/Resources/BaseRTRuntime` in the app). BaseRT is a direct native-Metal runtime for Apple Silicon. Keep `basert-complete` and its matching `baseRT.metallib` together.
- The `.base` model includes its compatible tokenizer. Do not download, copy, or ask users to install a separate proofreading tokenizer. Treat it as installed only when its expected file size matches. After a successful BaseRT download, remove the obsolete MLX and GGUF proofreading-model folders.
- BaseRT Q4 model download size is exactly `430,114,816` bytes. Downloads use `ResumableFileTransfer` with HTTP `Range`; received bytes are first written to a disposable `.incoming` file and appended to the persistent `.partial` file only after a valid response completes. A CDN response that ignores a range request must preserve existing progress. Never delete a partial download merely because a duplicate tail was received: trim it to the expected length and then validate/load it.
- Cancelling BaseRT-model download must stay on the proofreading model screen and immediately show the stored `.partial` byte count. Never route cancellation to the finished subtitle screen or show zero bytes when a partial file exists.
- Qwen proofreading must preserve cue count, order, start times, and end times. It may change only text spelling, punctuation, capitalization, and spacing. Do not translate, summarize, or rewrite meaning.

`ModelLocator.swift` is the single source of truth for model paths and installation checks. Application Support is the permanent no-prompt model store; no folder-permission onboarding window is needed.

## Architecture

- `App/WhisperDropApp.swift`: app entry point, foreground activation, scene and commands.
- `Models/SubtitleCue.swift`: final subtitle cue value type.
- `Models/ExportOptions.swift`: supported subtitle formats and text encodings.
- `Stores/AppStore.swift`: `@MainActor @Observable` UI state and workflow orchestration.
- `Services/AudioExtractor.swift`: converts unsupported video containers to temporary M4A with AVFoundation.
- `Services/TranscriptionService.swift`: WhisperKit setup, transcription, download, and progress callbacks.
- `Services/ModelLocator.swift`: model/tokenizer locations.
- `Services/TextImprovementModelLocator.swift`: Qwen proofreading model location, size, and download URL.
- `Services/TextImprovementModelDownloader.swift`: resumable download of the BaseRT Qwen model.
- `Services/TextImprovementService.swift`: local subtitle proofreading through bundled BaseRT / native Metal.
- `Runtime/BaseRT`: BaseRT release runtime assets bundled by `script/build_and_run.sh`; both `basert-complete` and the matching `baseRT.metallib` are required in the final app bundle.
- `Support/SRTFormatter.swift`: deterministic UTF-8 SRT rendering and timestamp formatting.
- `Support/SubtitleExporter.swift`: SRT, WebVTT, ASS, and TXT rendering plus byte encoding/BOM handling.
- `Support/WhisperTextSanitizer.swift`: removes Whisper control and timestamp tokens from decoded text.
- `Support/AppText.swift`: Russian/English UI selection and localized line-count text.
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
- `needsImprovementModel`
- `downloadingImprovementModel`
- `improvingSubtitles`
- `failed(String)`

Only one phase surface should be visible at a time. Dropping another file while work is active is rejected. Escape cancels active work. Command-O opens media. Command-S saves after completion.

Cancelling the Qwen model download or proofreading returns to the finished subtitle screen, not to the initial file drop screen. Downloading the Qwen model after transcription also returns to the finished screen; the user must explicitly press proofreading again.

## Subtitle correctness

- Default output encoding: UTF-8.
- Export encodings: UTF-8, UTF-8 BOM, UTF-16 LE, Windows-1251, and Windows-1252. The default is UTF-8.
- Export formats: SRT, WebVTT, ASS, and plain TXT. The default is SRT.
- SRT timestamps use `HH:MM:SS,mmm`; WebVTT uses a decimal point; ASS uses centiseconds and includes a standard default style/header.
- TXT exports cue text without timestamps.
- WebVTT requires UTF-8. Selecting WebVTT resets the encoding to UTF-8 and hides incompatible encodings.
- UTF-8 BOM and UTF-16 LE prepend the correct byte-order mark.
- Legacy encodings reject unsupported characters with a localized error instead of silently replacing them.
- Cues are filtered for non-empty text and positive duration, then sorted by start time.
- Whisper control and timestamp tokens in the form `<|...|>` must be stripped from cue text before display or any export.
- WhisperKit segment timestamps are converted from seconds into the timestamp syntax required by each export format.
- `SRTFormatterTests` currently has six tests covering SRT timestamps/Unicode, negative timestamp clamping, Whisper-token removal, WebVTT, ASS multiline output, and UTF-8 BOM.

Do not show a live subtitle-line counter during decoding: WhisperKit finalizes segments in batches, so an intermediate count can remain at zero or be misleading. Show the exact final cue count only on the completed state.

Transcription progress must use `WhisperKit.progress.fractionCompleted`. `TranscriptionProgress.timings.inputAudioSeconds` belongs to decoder timing statistics and is not the current playback position. WhisperKit reports progress at chunk boundaries, so the percentage may remain unchanged for a while during a long or difficult chunk even while CPU usage confirms active inference. Do not invent fake progress to hide this.

## UI and design invariants

- Single-purpose utility: no sidebar.
- Follow the installed `macos-design` skill.
- Use the 8 pt spacing grid; normal window padding is 20 pt and section gaps are 24 pt.
- macOS typography: 17 pt state title, 15 pt secondary heading, 13 pt body, 11–12 pt metadata.
- Use SF Symbols and semantic system/accent colors.
- Light and dark appearance follow the system automatically.
- Visible app text uses Russian when the primary preferred system language starts with `ru`; otherwise it uses English. Speech recognition language remains automatic and must not be exposed as an interface selector unless explicitly requested later.
- File drop state, transcription state, and finished state must remain separate.
- Primary actions keep visible shortcut hints where appropriate.
- State transitions use short 150–250 ms macOS-style fades/scales.
- The transcription ring and waveform use one oversized, smooth blue-to-light-blue linear gradient without repeating color bands. Render active animation at 60 FPS and respect Reduce Motion by freezing gradient travel and waveform movement.
- Interpolate circular progress changes with a short smooth animation so WhisperKit's chunk-level progress updates never appear as abrupt jumps.
- The transcription screen has one progress visualization only: the circular ring. Show the numeric percentage below its title and a separate Cancel action; do not add a duplicate linear progress bar or explanatory line-count placeholder.
- The finished screen shows exact cue count, format, and encoding in one compact row. Format and encoding menus open their choices directly and show a checkmark on the selected item. Never nest a `Picker` inside these `Menu` controls and never draw a second disclosure chevron.
- The finished screen may show `Исправить субтитры` / `Proofread subtitles` as a secondary action. If the Qwen model is missing, show a concise model-download screen analogous to the Whisper model setup screen. If the model exists, show a dedicated proofreading progress screen with one circular progress indicator and a bottom-up word flow; changed words can be highlighted later when the runtime returns reliable diff data.
- The proofreading word flow must stay inside its own middle slot between title and Cancel button. It shows exactly three rows; the center row is highlighted with a subtle animated blue/cyan gradient, and the top/bottom rows fade. It must not scroll under the title, progress ring, or controls.

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

Current tests cover formatting and export bytes, not visual appearance, every legacy encoding, or full-model inference. Do not claim a complete media transcription was tested unless one was actually run.

## Stabilization backlog before release

Treat the following as required release work, not optional polish:

### Transcription correctness

- Run end-to-end tests on short, long, silent, noisy, multilingual, variable-frame-rate, and multi-audio-track media.
- Compare exported SRT timestamps against playback and verify monotonic, non-overlapping cues.
- Define cue splitting limits for maximum characters, reading speed, and line count instead of relying only on raw Whisper segments.
- Add deterministic subtitle post-processing before/alongside Qwen: max line length, max two visual lines per cue, reading-speed limits, pause-aware splitting from word timestamps, and dialogue line breaks where safe.
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

- Investigate a more granular truthful progress source than WhisperKit's chunk-level `fractionCompleted`; long chunks can leave the displayed percentage unchanged despite active inference.
- Keep model loading, audio conversion, transcription, and finalization as distinct measurable phases.
- Show actionable errors rather than raw framework messages.
- Add a clear first-run model size/free-space warning and resumable download UI.

### Model management

- Keep models in the user Application Support directory, never through a project resource symlink. This is already implemented; preserve it during the Xcode-target migration.
- Download from the official Argmax/WhisperKit source; do not redistribute the model copied from MacWhisper.
- Verify downloaded files with expected size and cryptographic checksum before loading.
- Support resume, atomic installation, migration, corruption recovery, and deletion from settings.
- Document model and WhisperKit licenses in the app and distribution package.
- Document Qwen3 and BaseRT licenses in the app and distribution package before enabling proofreading in a public build.
- Add checksum verification for the Qwen BaseRT model; current implementation checks exact file size only.
- Keep the `OUTPUT_JSON:` prompt contract. The parser may accept a raw JSON array, fenced `json` block, or common object wrappers like `{"output":[...]}` only when the decoded string count exactly matches the input cue count. Never accept echoed input JSON from the prompt as a successful model response.
- After proofreading, compare original and improved cue text and show the changed cue count on the finished screen, e.g. `1243 исправления` / `1243 corrections`. This is user-facing result metadata, not diagnostic logging.
- Diagnostic logs must not be shown on the main surface. Use the top `Диагностика` / `Diagnostics` menu to open `~/Library/Application Support/WhisperDrop/Logs/WhisperDrop.log` or reveal its folder. Logs may include counts, chunk numbers, runtime mode, fallback paths, and errors, but must not include raw subtitle text.

### Subtitle proofreading stabilization

- Pin the BaseRT runtime release and smoke-test the packaged Metal runtime on Apple Silicon before release.
- Before release, perform one clean BaseRT-model download from zero, one cancel/resume test, one interrupted-network test, and one long SRT proofreading test in the packaged app.
- Add regression tests for the prompt contract: JSON array only, same cue count, same order, no translation, no meaning rewrite.
- Add chunking tests for long subtitle files, escaped quotes, emojis, multiline cues, Russian/English mixed text, and malformed model output.
- Add a visual diff model so the proofreading screen can highlight only actually corrected words, not just the currently processed word.
- Decide whether proofreading should overwrite `cues` immediately or keep original/improved variants with a compare/revert action.

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
- Verify release bundles still contain the tokenizer resources and no local model/project symlink.
- Add semantic version, build number, copyright, privacy information, and update policy.

### Compatibility and performance

- Decide whether release support is Apple Silicon only or universal; current local output is arm64.
- Measure model load time, real-time factor, peak memory, thermal behavior, and battery impact on supported Macs.
- Verify Core ML behavior after OS updates and on the minimum supported macOS version.
- Keep the UI responsive while loading and transcribing multi-hour files.

### UI, accessibility, and localization

- Test glass/titlebar rendering in light mode, dark mode, inactive windows, Reduce Transparency, Increase Contrast, and Reduce Motion.
- Add VoiceOver labels, keyboard focus order, full keyboard operation, and sufficient contrast.
- Replace the current inline `AppText.pick` localization layer with String Catalogs before release if the project migrates to a full Xcode app target.
- Current UI language policy: use Russian only when the system's primary preferred language starts with `ru`; otherwise use English. Test both language paths explicitly.
- Verify icon appearance at all required sizes in Dock, Finder, app switcher, About, and distribution storefronts.

### Distribution readiness

- Prepare privacy policy, support URL/email, screenshots, description, release notes, and App Store privacy answers.
- Add automated CI for clean release builds, tests, signing checks, and artifact validation.
- Maintain a release checklist that includes a clean-machine install and first-run model download.
- Do not call a build stable until a notarized/App Store-style artifact has completed the same end-to-end transcription tests as development builds.
