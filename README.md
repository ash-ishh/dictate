# Whisper Dictation

A small Mac dictation project with swappable transcription models.

Goal:

1. Press/click once to record.
2. Press/click again to stop.
3. Transcribe the recording.
4. Paste text into the input box/app that was focused when recording started.

## Best hotkey option

For this project, the best first option is **Hammerspoon**:

- free and scriptable,
- can create a menu-bar button,
- can bind global hotkeys,
- can remember the focused app,
- can paste back into the original input box,
- easy to modify while developing.

Recommended hotkeys:

- `Cmd + Option + Ctrl + Space`: start/stop recording
- `Cmd + Option + Ctrl + M`: choose model

Alternatives later:

- Keyboard Maestro: polished but paid.
- Raycast extension: nice UI, more ceremony.
- Native macOS menu bar app: best UX eventually, more engineering.

## Setup

```bash
brew install ffmpeg
brew install --cask hammerspoon
```

This project currently uses your existing `uv` at:

```text
/Users/ashish/.local/bin/uv
```

If `which uv` differs, update `uvPath` in `hammerspoon.lua`.

Initialize config:

```bash
cd /Users/ashish/Projects/MLX/whisper-exploration/whisper-dictation
uv run --python 3.12 whisper-dictation init-config
uv run --python 3.12 whisper-dictation models
```

The config lives at:

```text
~/.whisper-dictation/config.json
```

## Current backend

The first backend is `insanely-fast-whisper` PR #273 with MLX:

```text
/Users/ashish/Projects/MLX/whisper-exploration/insanely-fast-whisper
```

Make sure that repo is on the PR branch:

```bash
cd /Users/ashish/Projects/MLX/whisper-exploration/insanely-fast-whisper
git checkout pr-273
```

## Test transcription manually

```bash
cd /Users/ashish/Projects/MLX/whisper-exploration/whisper-dictation
uv run --python 3.12 whisper-dictation transcribe \
  ../insanely-fast-whisper/test.wav \
  --model ifw_mlx_tiny
```

Try another model:

```bash
uv run --python 3.12 whisper-dictation transcribe \
  ../insanely-fast-whisper/test.wav \
  --model ifw_mlx_large_v3
```

## Install Hammerspoon script

Add this to `~/.hammerspoon/init.lua`:

```lua
dofile("/Users/ashish/Projects/MLX/whisper-exploration/whisper-dictation/hammerspoon.lua")
```

Then reload Hammerspoon.

Grant permissions:

```text
System Settings → Privacy & Security → Accessibility → Hammerspoon
System Settings → Privacy & Security → Microphone → Hammerspoon
```

Find mic device if recording does not work:

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

Then update this in `hammerspoon.lua`:

```lua
local micDevice = ":0"
```

## Model swapping design

Models are configured in `~/.whisper-dictation/config.json`:

```json
{
  "default_model": "ifw_mlx_tiny",
  "python": "3.12",
  "models": {
    "ifw_mlx_tiny": {
      "backend": "insanely_fast_whisper_pr273",
      "repo": "/Users/ashish/Projects/MLX/whisper-exploration/insanely-fast-whisper",
      "mlx_family": "whisper",
      "model_name": "mlx-community/whisper-tiny",
      "extra_args": []
    }
  }
}
```

To test a future backend, add another backend implementation in:

```text
src/whisper_dictation/cli.py
```

and add a model entry with a new `backend` key.

## Architecture

```text
Hammerspoon
  ├─ starts/stops ffmpeg recording
  ├─ remembers focused app
  └─ calls Python CLI
        ↓
whisper-dictation transcribe audio.m4a --model <key>
        ↓
backend adapter
  ├─ insanely-fast-whisper PR #273 MLX
  ├─ future MLX Whisper direct backend
  ├─ future Parakeet direct backend
  └─ future local/remote model
        ↓
plain transcript
        ↓
Hammerspoon pastes into original app
```
