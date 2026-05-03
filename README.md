# Dictate

Dictate is a macOS speech-to-text utility that records from the microphone, transcribes the audio with a configurable model backend, and pastes the transcript into the app that was focused when recording started.

The project currently provides:

- a `dictate` Python CLI for testing transcription models,
- a Hammerspoon integration for global hotkey/menu-bar dictation,
- a config file for swapping transcription models without changing the hotkey script.

## Requirements

- macOS
- Apple Silicon for MLX-backed models
- Python 3.12 via `uv`
- `ffmpeg`
- Hammerspoon for the hotkey/menu-bar integration

Install system tools:

```bash
brew install ffmpeg
brew install --cask hammerspoon
```

Install `uv` if it is not already available:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

The Hammerspoon integration looks for `uv` in `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`.

## Installation

Clone or enter the project directory:

```bash
cd /path/to/dictate
```

Create the default config:

```bash
uv run --python 3.12 dictate init-config
```

List available configured models:

```bash
uv run --python 3.12 dictate models
```

The user config is stored at:

```text
~/.dictate/config.json
```

## Transcription backend

The initial backend uses the MLX backend from `insanely-fast-whisper` PR #273. Until that backend is available in a released package, Dictate runs it from a local checkout.

Set up the checkout:

```bash
git clone https://github.com/Vaibhavs10/insanely-fast-whisper.git
cd insanely-fast-whisper
git fetch origin pull/273/head:pr-273
git checkout pr-273
```

When `dictate init-config` creates `~/.dictate/config.json`, it chooses the checkout path in this order:

1. `DICTATE_IFW_REPO` environment variable, if set.
2. A sibling directory named `insanely-fast-whisper` next to the Dictate checkout.
3. The development fallback path used by this workspace.

If needed, edit the generated `repo` fields in:

```text
~/.dictate/config.json
```

## Manual transcription test

From the Dictate project directory:

```bash
uv run --python 3.12 dictate transcribe /path/to/audio.wav --model ifw_mlx_tiny
```

Write outputs to files:

```bash
uv run --python 3.12 dictate transcribe /path/to/audio.wav \
  --model ifw_mlx_tiny \
  --output-json /tmp/dictate.json \
  --output-text /tmp/dictate.txt
```

## Hammerspoon hotkey setup

### 1. Install and open Hammerspoon

```bash
brew install --cask hammerspoon
open -a Hammerspoon
```

### 2. Create the Hammerspoon config file

```bash
mkdir -p ~/.hammerspoon
nano ~/.hammerspoon/init.lua
```

Add this line, replacing the path with your Dictate checkout path:

```lua
dofile("/path/to/dictate/hammerspoon.lua")
```

Example:

```lua
dofile("/Users/ashish/Projects/MLX/whisper-exploration/dictate/hammerspoon.lua")
```

### 3. Reload Hammerspoon

From the Hammerspoon menu-bar icon, choose:

```text
Reload Config
```

Or reload from the terminal:

```bash
osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"'
```

### 4. Grant macOS permissions

Enable Hammerspoon in:

```text
System Settings → Privacy & Security → Accessibility → Hammerspoon
```

This lets Hammerspoon paste the transcript into the focused app.

Enable Hammerspoon in:

```text
System Settings → Privacy & Security → Microphone → Hammerspoon
```

This lets Hammerspoon record microphone audio. If Hammerspoon does not appear in the Microphone list, trigger recording once with the hotkey or menu-bar icon so macOS prompts for permission.

### 5. Use Dictate

Click into any text input, then press:

```text
Cmd + S
```

Speak, then press again:

```text
Cmd + S
```

A red on-screen indicator appears while recording is active.

Dictate stops recording, hides the indicator, transcribes the audio, and pastes the transcript into the app that was focused when recording started.

Other controls:

```text
Cmd + Option + Ctrl + M: choose model
Menu bar "D" item: start/stop recording
```

Menu-bar states:

```text
Dictate waveform icon: idle/transcribing
Red record icon: recording
```

The menu-bar artwork is stored in `assets/` as SVG sources plus 22×22 PNG files used by Hammerspoon.

Recent transcripts are available from the Dictate menu-bar menu. Selecting a transcript copies it back to the clipboard. Dictate keeps the last five transcripts for the current Hammerspoon session.

Because `Cmd + S` is also the standard Save shortcut, change the binding in `hammerspoon.lua` if you do not want Dictate to intercept it globally.

## Microphone device

Find available AVFoundation devices:

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

Update this value in `hammerspoon.lua` if your microphone is not device `0`:

```lua
local micDevice = ":0"
```

## Model configuration

Models are configured in:

```text
~/.dictate/config.json
```

Example:

```json
{
  "default_model": "ifw_mlx_tiny",
  "python": "3.12",
  "models": {
    "ifw_mlx_tiny": {
      "backend": "insanely_fast_whisper_pr273",
      "repo": "/path/to/insanely-fast-whisper",
      "mlx_family": "whisper",
      "model_name": "mlx-community/whisper-tiny",
      "extra_args": []
    }
  }
}
```

Switch models from the CLI:

```bash
uv run --python 3.12 dictate transcribe /path/to/audio.wav --model ifw_mlx_large_v3
```

Switch models from Hammerspoon:

```text
Cmd + Option + Ctrl + M
```

## Architecture

```text
Hammerspoon
  ├─ records microphone audio with ffmpeg
  ├─ remembers the focused app
  └─ calls the Dictate CLI
        ↓
dictate transcribe <audio> --model <model-key>
        ↓
backend adapter
  ├─ insanely-fast-whisper PR #273 MLX
  └─ future transcription backends
        ↓
plain transcript
        ↓
Hammerspoon pastes text into the original app
```

To add a backend, implement it in:

```text
src/dictate/cli.py
```

Then add a model entry in `~/.dictate/config.json` with a distinct `backend` value.
