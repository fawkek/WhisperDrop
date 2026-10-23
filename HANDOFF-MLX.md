# Handoff: MLX proofreading

Read this and `AGENT.md` before changing the project. Integration target: `main`;
implementation branch: `mlx-proofreading`. Current source version: **0.4.0,
build 8**. The 0.4.0 release has not been published.

## Goal and implementation

Replace the old BaseRT proofreading runtime with redistributable MLX Swift and
let the user select a local proofreading model. BaseRT is removed from the
current app sources and packaging; do not restore its binaries.

- `MLXProofreadingEngine` loads a local model in-process, uses a fresh ChatSession
  per chunk with temperature 0 and `enable_thinking: false`, and unloads after
  the run. A swift-transformers bridge supplies the tokenizer.
- `ProofreadingModelCatalog` has Qwen3.5 0.8B, 2B, 4B and Gemma 4 E2B in MLX
  4-bit format. File sizes and weight/tokenizer SHA-256 hashes live in
  `Services/TextImprovementModelLocator.swift`.
- Default is **Qwen3.5 4B for Russian and English**, also used for fallback
  languages. `ProofreadingModelID` in UserDefaults takes precedence when saved.
  CLI `--model` is an in-memory override. Exact default IDs are tested.
- The proofreading screen has a model menu, download size, installed/download
  action and a Back button. Dropped SRT/VTT files use the same flow.
- Models live in `~/Library/Application Support/WhisperDrop/Models/Proofreading/`.
  Downloads use persistent `.partial` files, HTTP Range, exact sizes and hashes.
  Successful installation removes obsolete proofreading-engine model folders.
- Six-cue chunks must return an equal-length JSON array in the same order. The
  prompt explicitly forbids merging adjacent cues. Invalid chunks retain their
  original text.
- `ProofreadingGuard` permits only punctuation, case, spacing and small
  misspelled-to-real-word corrections accepted by NSSpellChecker. **Never loosen
  this guard.** Cue timestamps and order remain unchanged.

## Metal blocker: resolved

`swift build` cannot compile MLX's Metal resources. Full Xcode with Swift 6.3+
(tested with Xcode 26.6) and its Metal Toolchain are required to build.

`script/build_mlx_metallib.sh` uses Xcode to build the dependency resources and
caches `default.metallib` under `.build/mlx-metal`, keyed by package manifests,
helper source, Xcode, SDK and architecture. The main build script copies it to
`Contents/MacOS/mlx.metallib` **before signing**, including for `--package`.
Dependency licenses are included in Resources. End users do not need Xcode.

Debug launch/process verification, Release packaging, cache reuse, signature
verification and proofreading from a ZIP extracted outside the checkout passed.
A successful 0.8B CLI smoke run verifies the Metal fix but not correction quality:
its invalid Russian chunks retain their original text.

## Model comparison: complete on short fixtures

Gemma finished downloading, passed size/hash checks and loaded through MLXLLM.
All four models were scored in the same Release build on M1 Max / 64 GiB.

- Initial differences: 13 per language under the fixture scorer.
- Remaining RU / EN differences: 0.8B 13 / 9; 2B 13 / 7; 4B 8 / 3; Gemma 10 / 9.
- 4B returned valid responses in all chunks, in 4.4 s RU / 3.7 s EN. It is the
  default for both languages. Alternative model notes reflect lower accuracy or
  experimental status; do not promise broad accuracy from this small sample.
- Smaller Qwen models merged Russian elements. Gemma sometimes moved/dropped
  text; the unchanged guard rejected those edits. All output files preserved cue
  count/order/timestamps. Saved final-chunk answers contained no thinking text.

Committed fixtures/scorer: `Tests/Fixtures/Proofreading/`.
Full results: `Docs/MLX-proofreading-benchmark.md`.
Build/model/packaging guide: `Docs/DEVELOPMENT.md`.
README is updated in Russian and English; `Models/README.md` documents storage
and exact download totals; `CHANGELOG.md` records unreleased 0.4.0 changes.

## Validation and CI

`swift test`: 86 XCTest + 3 Swift Testing tests pass. Tests cover catalog sizes,
exact language defaults, complete partial installation, verified oversized
partial recovery, cancellation preserving files and installation checks.
`git diff --check` and shell syntax checks pass; 0.4.0 Release packaging and
codesign verification pass. Short inference runs use installed models.

`.github/workflows/ci.yml` selects Xcode 26.6 on macOS 26, installs Metal Toolchain,
runs tests, packages/verifies the app and uploads a test-build artifact. It
replaces the obsolete version-specific 0.2.x release publishers and does not
publish or overwrite GitHub releases.

## Remaining before publishing 0.4.0

1. Validate live clean-model download, cancel/resume, interrupted network and a
   long SRT in the packaged app. Check minimum supported macOS separately.
2. Package from the final committed checkout so About contains the right commit.
   Extract the ZIP outside the project, verify its hash/signature and test it.
3. Decide whether to keep all experimental alternatives in the final release;
   the present source retains the user's model choices and recommends 4B.
4. Ask before deleting/replacing existing published assets: older releases still
   contain the old BaseRT binary. Publishing source changes does not authorize
   removing historical release assets.
5. Release 0.4.0 only after the required validation. Build metadata is already
   0.4.0 / 8. Commits must have **no Co-Authored-By or Claude-Session trailers**.

## Developer commands

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --package
swift test

dist/WhisperDrop.app/Contents/MacOS/WhisperDrop \
  --proofread Tests/Fixtures/Proofreading/ru-typos.srt /tmp/proofread.srt \
  --model qwen3.5-4b
```

Other modes: `--transcribe <media> <out.srt> [--segments <json>]`,
`--resegment <json> <out.srt>`, `--snapshots <folder>`.
GUI demo: `WHISPERDROP_DEMO=proofread-model`; appearance override:
`WHISPERDROP_APPEARANCE=light|dark`. Use `open -n --env ... dist/WhisperDrop.app`.
`WHISPERDROP_DEBUG_PROOFREAD=<path>` writes the last chunk's input/raw response;
normal logs contain counts/errors, not subtitle text.
