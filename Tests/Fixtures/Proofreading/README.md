# Proofreading fixtures

Small Russian and English subtitle examples used for manual model evaluation.
Each `*-typos.srt` retains the corresponding clean file's cue count, order and
timestamps while introducing spelling, case and punctuation differences.

Run the packaged app with an installed model:

```bash
dist/WhisperDrop.app/Contents/MacOS/WhisperDrop \
  --proofread Tests/Fixtures/Proofreading/ru-typos.srt /tmp/ru-proofread.srt \
  --model qwen3.5-4b
python3 Tests/Fixtures/Proofreading/score.py \
  Tests/Fixtures/Proofreading/ru-clean.srt \
  Tests/Fixtures/Proofreading/ru-typos.srt /tmp/ru-proofread.srt
```

`score.py` reports token edit distance from the clean reference. Both typo files
start at 13 differences under this metric; this is not a count of distinct
misspelled words. The scorer normalizes ё/е and ignores subtitle line wrapping.
It does not verify timestamps, cue boundaries, meaning preservation or arbitrary
subtitle quality; check those separately and inspect failed-chunk logs.

The fixtures do not download models or run automatically in `swift test`.
See the [recorded evaluation](../../../Docs/MLX-proofreading-benchmark.md).
