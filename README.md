# WhisperDrop

Native macOS application for private, on-device subtitle transcription with OpenAI Whisper Large v3.

## Run

```bash
./script/build_and_run.sh
```

Drop an audio or video file onto the window, wait for transcription, then save a UTF-8 `.srt` file.
The app follows the current macOS light or dark appearance automatically. Russian and English interfaces follow the system language.

## Model

Downloaded Core ML weights live in Application Support and are excluded from Git. If absent, the app offers to download the model. Required tokenizer files are bundled with the app.

## Package

```bash
./script/build_and_run.sh --package
```

For public distribution, install an Apple Developer ID Application certificate and provide its exact Keychain identity:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" ./script/build_and_run.sh --package
```

Without it, the ZIP is ad hoc signed and suitable only for local testing.

## Links

- X/Twitter: [@fawkek_obj](https://x.com/fawkek_obj)
- GitHub project URL: to be added after publication.
