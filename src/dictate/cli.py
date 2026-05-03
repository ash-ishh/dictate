from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

APP_DIR = Path.home() / ".dictate"
CONFIG_PATH = APP_DIR / "config.json"


def default_ifw_repo() -> Path:
    """Return the local insanely-fast-whisper checkout used by the experimental PR backend."""
    if env_path := os.environ.get("DICTATE_IFW_REPO"):
        return Path(env_path).expanduser()

    project_root = Path(__file__).resolve().parents[2]
    sibling_checkout = project_root.parent / "insanely-fast-whisper"
    if sibling_checkout.exists():
        return sibling_checkout

    return Path.home() / "Projects" / "MLX" / "whisper-exploration" / "insanely-fast-whisper"


DEFAULT_IFW_REPO = default_ifw_repo()

DEFAULT_CONFIG: dict[str, Any] = {
    "default_model": "ifw_mlx_tiny",
    "python": "3.12",
    "models": {
        "ifw_mlx_tiny": {
            "backend": "insanely_fast_whisper_pr273",
            "repo": str(DEFAULT_IFW_REPO),
            "mlx_family": "whisper",
            "model_name": "mlx-community/whisper-tiny",
            "extra_args": [],
        },
        "ifw_mlx_large_v3": {
            "backend": "insanely_fast_whisper_pr273",
            "repo": str(DEFAULT_IFW_REPO),
            "mlx_family": "whisper",
            "model_name": "mlx-community/whisper-large-v3-mlx",
            "extra_args": [],
        },
        "ifw_mlx_turbo": {
            "backend": "insanely_fast_whisper_pr273",
            "repo": str(DEFAULT_IFW_REPO),
            "mlx_family": "whisper",
            "model_name": "mlx-community/whisper-large-v3-turbo",
            "extra_args": [],
        },
        "ifw_mlx_parakeet": {
            "backend": "insanely_fast_whisper_pr273",
            "repo": str(DEFAULT_IFW_REPO),
            "mlx_family": "parakeet",
            "model_name": "mlx-community/parakeet-tdt_ctc-110m",
            "extra_args": [],
        },
    },
}


def load_config() -> dict[str, Any]:
    if not CONFIG_PATH.exists():
        return DEFAULT_CONFIG.copy()
    with CONFIG_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


def save_default_config(force: bool = False) -> Path:
    APP_DIR.mkdir(parents=True, exist_ok=True)
    if CONFIG_PATH.exists() and not force:
        return CONFIG_PATH
    with CONFIG_PATH.open("w", encoding="utf-8") as f:
        json.dump(DEFAULT_CONFIG, f, indent=2)
        f.write("\n")
    return CONFIG_PATH


def run(cmd: list[str], cwd: Path | None = None, quiet: bool = False) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.setdefault("PYTHONUNBUFFERED", "1")
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )


def transcribe_insanely_fast_whisper(model: dict[str, Any], audio: Path, output_json: Path, python: str) -> str:
    repo = Path(model["repo"]).expanduser()
    if not repo.exists():
        raise SystemExit(f"insanely-fast-whisper repo not found: {repo}")

    cmd = [
        "uv",
        "run",
        "--python",
        python,
        "--extra",
        "mlx",
        "insanely-fast-whisper",
        "--backend",
        "mlx",
        "--mlx-family",
        model.get("mlx_family", "whisper"),
        "--model-name",
        model["model_name"],
        "--file-name",
        str(audio),
        "--transcript-path",
        str(output_json),
    ]
    cmd.extend(model.get("extra_args", []))

    proc = run(cmd, cwd=repo)
    if proc.returncode != 0:
        raise SystemExit(proc.stderr or proc.stdout or f"Command failed: {' '.join(cmd)}")

    with output_json.open("r", encoding="utf-8") as f:
        payload = json.load(f)
    return (payload.get("text") or "").strip()


def cmd_init_config(args: argparse.Namespace) -> int:
    path = save_default_config(force=args.force)
    print(path)
    return 0


def cmd_models(args: argparse.Namespace) -> int:
    config = load_config()
    default = config.get("default_model")
    for name, model in config.get("models", {}).items():
        mark = "*" if name == default else " "
        print(f"{mark} {name}: {model.get('backend')} / {model.get('model_name')}")
    return 0


def cmd_transcribe(args: argparse.Namespace) -> int:
    config = load_config()
    model_name = args.model or config.get("default_model")
    models = config.get("models", {})
    if model_name not in models:
        raise SystemExit(f"Unknown model '{model_name}'. Run: dictate models")

    audio = Path(args.audio).expanduser().resolve()
    if not audio.exists():
        raise SystemExit(f"Audio file not found: {audio}")

    output_json = Path(args.output_json or APP_DIR / "last-transcript.json").expanduser()
    output_json.parent.mkdir(parents=True, exist_ok=True)

    model = models[model_name]
    backend = model.get("backend")
    if backend == "insanely_fast_whisper_pr273":
        text = transcribe_insanely_fast_whisper(model, audio, output_json, config.get("python", "3.12"))
    else:
        raise SystemExit(f"Unsupported backend '{backend}' for model '{model_name}'")

    if args.output_text:
        out = Path(args.output_text).expanduser()
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text + "\n", encoding="utf-8")

    print(text)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="dictate")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("init-config", help="Create ~/.dictate/config.json")
    p.add_argument("--force", action="store_true", help="Overwrite existing config")
    p.set_defaults(func=cmd_init_config)

    p = sub.add_parser("models", help="List configured transcription models")
    p.set_defaults(func=cmd_models)

    p = sub.add_parser("transcribe", help="Transcribe an audio file and print text to stdout")
    p.add_argument("audio")
    p.add_argument("--model", help="Model key from config.json")
    p.add_argument("--output-json", help="Where to write raw JSON")
    p.add_argument("--output-text", help="Where to write plain text")
    p.set_defaults(func=cmd_transcribe)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
