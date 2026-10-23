# Handoff: proofreading on MLX (for Codex)

Read this first, then AGENT.md. Branch: `mlx-proofreading` (work in progress, not pushed).

## Goal

Replace the BaseRT proofreading runtime with Apple's MLX (MIT, can be bundled), and let the user pick the proofreading model from a drop-down on the proofreading screen. The default model follows the system language (Russian vs English); English may use a larger model.

Why: the BaseRT engine license (inside `basert-engine-macos-arm64-0.4.1.tar.gz`, file `LICENSE`) forbids redistribution, and the old bundled BaseRT could not run Qwen3.5 (it produced garbage). The user chose MLX.

## Already done on this branch

- `Package.swift`: added `mlx-swift-lm` 3.32.3 (`MLXLLM`, `MLXLMCommon`) and `swift-transformers` (`Tokenizers`). `swift build` succeeds.
- `Services/MLXProofreadingEngine.swift`: actor that loads an MLX model from a local folder (`loadModelContainer(from:using:)`), runs one fresh `ChatSession` per chunk with `temperature: 0` and `additionalContext: ["enable_thinking": false]`, unloads after a run. Contains a swift-transformers → MLXLMCommon tokenizer bridge.
- `Services/TextImprovementModelLocator.swift`: `ProofreadingModelCatalog` with 4 MLX models (files, sizes, SHA-256 from the Hugging Face API): `qwen3.5-0.8b`, `qwen3.5-2b`, `qwen3.5-4b`, `gemma-4-e2b` (all `mlx-community/*-4bit`). Selected model is stored in UserDefaults key `ProofreadingModelID`; `defaultModelID(forLanguage:)` currently returns `qwen3.5-2b` for both languages — **must be set from test results**. Models live in `~/Library/Application Support/WhisperDrop/Models/Proofreading/<repo-name>/`.
- `Services/TextImprovementModelDownloader.swift`: per-file resumable download with exact sizes and SHA-256; removes legacy folders (`TextImprovementBaseRT`, `TextImprovementMLX`, `TextImprovement`) after a successful download.
- `Services/TextImprovementService.swift`: `runModel` now calls `MLXProofreadingEngine` (no child process). Prompt, JSON parsing, 6-cue chunks and `ProofreadingGuard` unchanged.
- `Services/ProofreadingGuard.swift` (moved out of the deleted `BaseRTProcess.swift`): keeps only punctuation/case/spacing edits and misspelled→real-word fixes via `NSSpellChecker`. **Never loosen this.**
- `Stores/AppStore.swift` + `Views/ContentView.swift`: "Исправить текст" and dropped subtitle files open the proofreading screen with a model drop-down (`ProofreadingModelMenu`); button is "Исправить" when installed, otherwise "Скачать и исправить · size". "Назад" returns to the subtitles. `proofreadingModelID` mirrors the choice so SwiftUI redraws.
- `App/Entry.swift`: `--proofread <in.srt> <out.srt> [--model <id>]` (in-memory override, does not touch the saved choice). `App/Snapshots.swift`: demo screen `proofread-model`.
- `script/build_and_run.sh`: BaseRT copy/sign steps removed. `Runtime/BaseRT` removed with `git rm`.

## Blocker to fix first: MLX Metal shaders

Running the app gives `MLX error: Failed to load the default metallib`. `swift build` cannot compile Metal shaders. MLX looks for `mlx.metallib` next to the executable (see `.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/device.cpp`, "colocated mlx.metallib").

- Metal Toolchain is now installed (`xcodebuild -downloadComponent MetalToolchain` done).
- An `xcodebuild` was started: `xcodebuild build -scheme WhisperDrop -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode -skipPackagePluginValidation -skipMacroValidation`, log `/tmp/wd-xcb.log` (ends with `XCB <exit code>`).
- Then find `default.metallib` (expected in `.build/xcode/Build/Products/Release/mlx-swift_Cmlx.bundle/…`) and in `build_and_run.sh` copy it to `$APP_MACOS/mlx.metallib` before signing. Cache it (rebuild only when `Package.resolved` changes). Make `--package` include it. Document "Xcode + Metal Toolchain required" in README build steps. The GitHub release workflows (`.github/workflows/release-*.yml`) will need the same.
- Verify: `dist/WhisperDrop.app/Contents/MacOS/WhisperDrop --proofread ~/git/WhisperDrop-testdata/ru-typos.srt /tmp/out.srt --model qwen3.5-0.8b` must produce output without the metallib error.

## Then: choose the default models

Test data in `~/git/WhisperDrop-testdata/`:
- `ru-clean.srt` / `ru-typos.srt`, `en-clean.srt` / `en-typos.srt` (11–12 inserted typos each).
- `score.py clean.srt typos.srt proofread.srt` → errors before/after.
- Models: `qwen3.5-0.8b` and `qwen3.5-2b` are already in the app's `Proofreading` folder. `qwen3.5-4b` and `gemma-4-e2b` are downloading via `fetch_mlx.sh` into `mlx-models/` (log `fetch.log`); move each finished folder into `~/Library/Application Support/WhisperDrop/Models/Proofreading/`.
- For each model and language run `--proofread … --model <id>` (run in background, it can take > 60 s), score it, and read `~/Library/Application Support/WhisperDrop/Logs/WhisperDrop.log` (`rejectedEdits`, failed chunks, `Proofreading took`). `WHISPERDROP_DEBUG_PROOFREAD=/tmp/x.txt` writes the raw model answer.
- Pick per language the best quality with acceptable speed; set `defaultModelID(forLanguage:)`, adjust picker notes, drop models that fail to load or perform badly. Check that `enable_thinking: false` really stops Qwen3.5 thinking; check Gemma 4 loads in MLXLLM (`Gemma4Text`).

## Then: finish and release 0.4.0

1. `swift test` (update/add tests: catalog file sizes, default by language, downloader with a fake manifest like `ModelDownloaderTests`).
2. README "Как устроена вычитка / How proofreading works": replace BaseRT text and hashes with MLX + model list + guard. AGENT.md lines ~67–90, 239–249, 304: replace BaseRT notes with MLX.
3. Ask the user before touching published releases: v0.3.0, v0.3.1 and older zips contain the BaseRT binary — the user may want those assets removed or replaced.
4. Version `0.4.0`, build `8` in `build_and_run.sh`; `./script/build_and_run.sh --package`; verify the downloaded zip (hash, `codesign --verify`, proofreading works on a clean model folder).
5. Commits: **no `Co-Authored-By` or `Claude-Session` trailers** (user preference). Merge to `main`, push, `gh release create v0.4.0`.

## Useful developer commands

- `WhisperDrop --transcribe <media> <out.srt> [--segments <json>]`, `--resegment <json> <out.srt>`, `--snapshots <folder>`.
- `open -n --env WHISPERDROP_DEMO=<screen> --env WHISPERDROP_APPEARANCE=dark dist/WhisperDrop.app` for screenshots (`proofread-model`, `finished`, `drop`, …).
