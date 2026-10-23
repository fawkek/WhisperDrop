# Development guide

The current source targets **0.4.0, build 8**. Published 0.3.1 archives predate
the MLX migration. Building a ZIP locally does not publish or replace a release.

## Requirements and first build

- macOS 14 or later; Apple Silicon is required for MLX proofreading.
- Full Xcode with Swift 6.3 or later (tested with Xcode 26.6), with its command-line tools selected. Command Line Tools alone
  cannot compile the MLX Metal resources.
- Metal Toolchain installed for the selected Xcode.
- Internet access to resolve Swift packages and, when requested, download models.

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -runFirstLaunch
xcodebuild -downloadComponent MetalToolchain
git clone https://github.com/fawkek/WhisperDrop.git
cd WhisperDrop
./script/build_and_run.sh --verify
```

The project is a Swift package with a macOS app bundle staged by
`script/build_and_run.sh`. Use that script to launch the GUI. `swift build`
alone produces an executable without the required packaged Metal library.

| Command | Result |
| --- | --- |
| `./script/build_and_run.sh` | Build Debug, package, sign ad hoc and open the app |
| `./script/build_and_run.sh --verify` | Also confirm the launched process exists |
| `./script/build_and_run.sh --debug` | Launch the packaged executable in LLDB |
| `./script/build_and_run.sh --logs` | Open the app and stream process logs |
| `./script/build_and_run.sh --telemetry` | Open the app and stream subsystem logs |
| `./script/build_and_run.sh --package` | Build Release and create a verified ZIP |
| `swift test` | Run unit tests; does not run full model inference |

## MLX Metal library

The main build script calls `script/build_mlx_metallib.sh` after Swift package
resolution. The helper uses Xcode to compile MLX's Metal resources for macOS 14
and copies `mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib` into a
cache at `.build/mlx-metal/<key>/mlx.metallib`.

The key includes `Package.swift`, `Package.resolved`, the helper itself, Xcode,
the SDK version and build architecture. Debug and Release share this shader
cache. On a cache hit, no Xcode build runs. On a miss, the build log is saved
beside the cached library as `xcodebuild.log`.

The final app must contain:

```text
dist/WhisperDrop.app/Contents/
  MacOS/WhisperDrop
  MacOS/mlx.metallib
  Resources/Tokenizer/
  Resources/Licenses/
```

The library is copied before signing. `--package` archives the same signed app,
so end users do not need Xcode or the Metal Toolchain. MLX, MLX LM and
swift-transformers license texts are copied from resolved dependencies into
`Resources/Licenses`.

If the app reports `Failed to load the default metallib`, rebuild through the
main script and check `Contents/MacOS/mlx.metallib`. If Xcode cannot compile
Metal, check `xcode-select -p`, install the Metal Toolchain for that Xcode, and
read the helper's `xcodebuild.log`. To force shader recompilation, remove only
the generated `.build/mlx-metal` cache and rebuild.

## Model files and choices

Runtime models live under:

```text
~/Library/Application Support/WhisperDrop/Models/
  openai_whisper-large-v3-v20240930/
  Proofreading/<repository-name>/
```

Whisper transcription uses the bundled `Models/tokenizer` source files.
Proofreading downloads each model's own config, weights, chat template and
tokenizer. Model weights belong in Application Support, not Git or the app ZIP.
See [model storage](../Models/README.md).

The proofreading catalog and exact byte counts are in
`Sources/WhisperDrop/Services/TextImprovementModelLocator.swift`. Installation
requires all manifest files at their exact sizes; completed downloads also
validate weight/tokenizer SHA-256 hashes. Transfers write directly to durable
`.partial` files and resume with HTTP Range.

`ProofreadingModelID` in UserDefaults stores the user's choice. Without a saved
choice, Qwen3.5 4B is selected for Russian, English and other interface languages.
The CLI `--model` override is in memory and does not change that preference.
The alternative models remain available for evaluation; their known limitations
are documented in the [model comparison](MLX-proofreading-benchmark.md).

## Headless checks

Run developer modes from the executable inside the packaged app:

```bash
dist/WhisperDrop.app/Contents/MacOS/WhisperDrop \
  --proofread input.srt output.srt --model qwen3.5-4b

dist/WhisperDrop.app/Contents/MacOS/WhisperDrop \
  --transcribe video.mp4 output.srt --segments segments.json

dist/WhisperDrop.app/Contents/MacOS/WhisperDrop \
  --resegment segments.json output.srt
```

Valid proofreading IDs are `qwen3.5-0.8b`, `qwen3.5-2b`, `qwen3.5-4b` and
`gemma-4-e2b`. Install the chosen model through the app before running the CLI.

A zero CLI exit code means an output file was written. Failed model chunks may
retain their original text, so also inspect the log and compare the output:

```text
~/Library/Application Support/WhisperDrop/Logs/WhisperDrop.log
```

Logs record selected model, chunk success/failure, rejected edits and duration.
They do not normally contain subtitle text. For a deliberate local diagnostic,
set `WHISPERDROP_DEBUG_PROOFREAD=/tmp/proofreading-answer.txt` on the command;
that file contains the last chunk's input and raw answer, so do not upload it
when it contains private subtitles.

`ProofreadingGuard` must keep rejecting meaning changes, correctly spelled word
substitutions and moved text. Invalid JSON or wrong cue counts keep the original
chunk. Never weaken these checks to improve a benchmark score.

## Packaging and release checks

```bash
swift test
git diff --check
./script/build_and_run.sh --package
codesign --verify --deep --strict --verbose=2 dist/WhisperDrop.app
shasum -a 256 dist/WhisperDrop-0.4.0-macOS.zip
```

`APP_VERSION` and `APP_BUILD` override the default metadata. The current
12-character Git commit is embedded in About; package from a committed checkout
when producing a release artifact.

For Developer ID signing, set `DEVELOPER_ID_APPLICATION` to the keychain
identity. Also set `NOTARY_PROFILE` to a configured notarytool keychain profile
to submit, staple, validate, and recreate the final archive. Without an identity,
the script creates an ad hoc signed test build.

Before publishing 0.4.0, test the extracted archive outside the checkout, verify
its signature and hash, and run proofreading with installed models. Live clean
model download, cancellation/resumption, interrupted-network recovery and a long
subtitle file still need release validation. Unit tests and the short fixtures
do not establish those properties.

The source CI runs tests and packages the app as a downloadable build artifact;
it does not publish releases. Existing published archives are historical and
must not be overwritten by the source CI.

CI selects Xcode 26.6 on the `macos-26` Apple Silicon runner; see GitHub's
[runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).
