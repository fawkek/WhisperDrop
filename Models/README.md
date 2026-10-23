# Local model storage

Only the transcription tokenizer source files are bundled from this directory.
Core ML and MLX model weights are downloaded at runtime to Application Support
and intentionally excluded from Git and the app archive.

```text
~/Library/Application Support/WhisperDrop/Models/
  openai_whisper-large-v3-v20240930/      # transcription, about 1.62 GB
  Proofreading/
    Qwen3.5-0.8B-4bit/                  # 645,302,309 bytes
    Qwen3.5-2B-4bit/                    # 1,742,354,857 bytes
    Qwen3.5-4B-4bit/                    # 3,054,404,243 bytes; default
    gemma-4-e2b-it-4bit/                # 3,583,085,182 bytes
```

Proofreading sizes include the tokenizer, config, chat template and weights.
Each model is independent and downloads only when chosen. The catalog in
`Sources/WhisperDrop/Services/TextImprovementModelLocator.swift` defines the
required files and integrity hashes. The in-app download preserves `.partial`
files for resumption; do not rename an incomplete file to mark it installed.

Qwen3.5 4B is the default for both interface languages. The other models remain
experimental alternatives; see the [model evaluation](../Docs/MLX-proofreading-benchmark.md).
MLX proofreading requires Apple Silicon.

Models are not covered by WhisperDrop's own MIT license; their repositories
provide their respective license terms. Runtime model sources:

- [Whisper Large v3 Core ML](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930)
- [Qwen3.5 0.8B 4-bit](https://huggingface.co/mlx-community/Qwen3.5-0.8B-4bit)
- [Qwen3.5 2B 4-bit](https://huggingface.co/mlx-community/Qwen3.5-2B-4bit)
- [Qwen3.5 4B 4-bit](https://huggingface.co/mlx-community/Qwen3.5-4B-4bit)
- [Gemma 4 E2B 4-bit](https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit)

Never move or delete a model belonging to another installed application.
