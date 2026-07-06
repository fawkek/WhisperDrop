# WhisperDrop

Native macOS application for private, on-device subtitle transcription with Whisper Large v3 Turbo.

## Run

```bash
./script/build_and_run.sh
```

Drop an audio or video file onto the window, wait for transcription, then save a UTF-8 `.srt` file.
The app follows the current macOS light or dark appearance automatically.

## Model

Local Core ML weights live under `Models/openai_whisper-large-v3-v20240930`. They are excluded from Git due to size. If absent, the app offers to download a compatible model on first launch.

