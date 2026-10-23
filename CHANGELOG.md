# Changelog

## 0.4.0 — Unreleased

- Replace the bundled BaseRT proofreading engine with in-process MLX Swift.
- Add a proofreading model menu for Qwen3.5 0.8B, 2B, 4B and Gemma 4 E2B.
  Qwen3.5 4B is the default for Russian and English based on the short subtitle
  fixtures; saved user choices take precedence.
- Download model files with resume support, exact byte counts and SHA-256
  verification for weights and tokenizers.
- Compile MLX Metal resources through Xcode, cache them by dependencies and
  toolchain, and include `mlx.metallib` before signing and ZIP packaging.
- Include the new runtime/tokenizer dependency license texts in the app.
- State cue boundaries and the exact output element count explicitly in the
  model prompt. Keep strict JSON parsing and the conservative spelling guard.
- Add catalog/downloader tests, a development guide and measured model results.

The experimental alternatives can merge or alter cues; rejected responses keep
the original text. See [test results](Docs/MLX-proofreading-benchmark.md) and the
[remaining release checks](Docs/DEVELOPMENT.md#packaging-and-release-checks).

## 0.3.1

Published test release before the MLX migration. Its existing download links
remain in the README; this changelog does not imply that those archives contain
the 0.4.0 changes.
