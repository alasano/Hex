# Hex AI — Voice → Text

A macOS menu bar app for on-device voice-to-text. Press-and-hold a hotkey to transcribe your voice and paste the result wherever you're typing.

Fork of [kitlangton/Hex](https://github.com/kitlangton/Hex) with AI text transforms powered by OpenAI.

## Features

- On-device transcription via [Parakeet TDT v3](https://github.com/FluidInference/FluidAudio) (default) and [WhisperKit](https://github.com/argmaxinc/WhisperKit)
- AI transforms — apply custom prompts to transcriptions before pasting
- Word remappings and filler word removal
- Global hotkey with press-and-hold or double-tap modes
- Built with [Swift Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)

## Instructions

Grant microphone and accessibility permissions when prompted.

Two recording modes:

1. **Press-and-hold** the hotkey to record, release to transcribe
2. **Double-tap** the hotkey to lock recording, tap again to transcribe

## Building

```bash
xcodebuild -scheme Hex -configuration Release build DEVELOPMENT_TEAM=<your_team_id>
```

## License

MIT License. See `LICENSE` for details.
