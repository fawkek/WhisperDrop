# MLX proofreading checks — 2026-10-23

Test machine: Apple M1 Max, 64 GiB RAM. These are short development fixtures,
not a representative quality or performance benchmark.

## Reproduce the comparison

Fixtures and the scorer are committed in
[`Tests/Fixtures/Proofreading`](../Tests/Fixtures/Proofreading). Russian has
12 cues; English has 10. Both typo files start with 13 token differences from
their clean references under `score.py`, which ignores wrapping and normalizes
ё/е. This is an edit-distance metric, not a count of misspelled words.

Build with `./script/build_and_run.sh --package`, install the desired model
through the app, and run:

```bash
dist/WhisperDrop.app/Contents/MacOS/WhisperDrop \
  --proofread Tests/Fixtures/Proofreading/ru-typos.srt /tmp/ru-proofread.srt \
  --model qwen3.5-4b
python3 Tests/Fixtures/Proofreading/score.py \
  Tests/Fixtures/Proofreading/ru-clean.srt \
  Tests/Fixtures/Proofreading/ru-typos.srt /tmp/ru-proofread.srt
```

Repeat for `en` and the other catalog IDs. Also inspect failed-chunk and rejected
edit counts in `~/Library/Application Support/WhisperDrop/Logs/WhisperDrop.log`;
a successful CLI exit can include chunks whose original text was retained.

## Results

All eight runs below used the same Release build (0.4.0, build 8), prompt and
unchanged `ProofreadingGuard`. Each run loads its model in a fresh process,
uses temperature 0, disables thinking in the chat template, and processes two
chunks of up to six cues. Metal's compilation cache is warm; these times are
not clean-machine startup measurements.

| Model | Language | Time | Errors before → after | Failed chunks | Guard-rejected cues |
| --- | --- | ---: | ---: | ---: | ---: |
| Qwen3.5 0.8B | Russian | 2.1 s | 13 → 13 | 2/2 | 0 |
| Qwen3.5 0.8B | English | 1.9 s | 13 → 9 | 0/2 | 0 |
| Qwen3.5 2B | Russian | 2.8 s | 13 → 13 | 2/2 | 0 |
| Qwen3.5 2B | English | 2.5 s | 13 → 7 | 0/2 | 0 |
| Qwen3.5 4B | Russian | 4.4 s | 13 → 8 | 0/2 | 0 |
| Qwen3.5 4B | English | 3.7 s | 13 → 3 | 0/2 | 0 |
| Gemma 4 E2B | Russian | 6.4 s | 13 → 10 | 0/2 | 4 |
| Gemma 4 E2B | English | 3.9 s | 13 → 9 | 1/2 | 1 |

All eight output files preserved cue count, order and exact timestamps. Smaller
Qwen models merged Russian array elements, causing their responses to be
rejected. Gemma loaded through MLXLLM, but its output sometimes moved or dropped
text within an otherwise valid array; the guard rejected those cue edits. One
English Gemma chunk failed the output-format check. No guard rules were relaxed.
The saved final-chunk responses contained no thinking text.

**Decision:** Qwen3.5 4B is the default for Russian, English and fallback interface
languages. It had the lowest error count in both fixtures and returned valid
responses in every chunk. Saved user choices still take precedence. The other
models remain selectable alternatives with experimental/lower-accuracy notes.

The prompt explicitly states the required element count and forbids merging cues
when a sentence spans adjacent subtitles. Before that clarification, 0.8B failed
both chunks in both languages, 2B failed both Russian chunks and one English
chunk, and 4B left 8 Russian / 4 English differences. The clarification improved
format compliance without loosening parsing or spelling checks.

## Metal packaging checks

`swift build` alone does not compile MLX's Metal resources. The main build script
now calls `script/build_mlx_metallib.sh`, which uses Xcode and caches the library
by package manifest/lockfile, helper script, Xcode, SDK and architecture. It
stages `Contents/MacOS/mlx.metallib` before signing. Repeated helper invocations
reuse the cache without another Xcode build.

Debug `--verify` and Release `--package` succeeded. An earlier local development
ZIP was extracted into a temporary folder outside the checkout and passed
`codesign --verify --deep --strict`. It contained the shader library and all
three new dependency license files. Proofreading from that relocated app
completed without `Failed to load the default metallib`; 4B produced the same
8 Russian / 3 English remaining errors. The 0.8B smoke run also completed without
a Metal crash, retaining its rejected chunks.

## Limits and remaining release checks

These runs use installed model folders. They do not establish general subtitle
accuracy, live download/cancel/resume behavior, network-interruption recovery,
long-file reliability, minimum-macOS compatibility or cold-start performance.
See the [release checks](DEVELOPMENT.md#packaging-and-release-checks) before
publishing 0.4.0.
