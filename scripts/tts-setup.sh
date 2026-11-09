#!/usr/bin/env bash
# Install the local neural TTS stack used by the `local` engine:
#   mlx-audio (server) + Kokoro-82M (model) + the extras the server needs.
#
# macOS / Apple Silicon only. Re-runnable; already-installed pieces are skipped.
set -euo pipefail

MODEL="${TRANSLATOR_TTS_MODEL:-mlx-community/Kokoro-82M-4bit}"
HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export HF_ENDPOINT

need() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "error: '$1' not found. $2" >&2
		exit 1
	fi
}

need uv "Install it with: brew install uv"
need brew "Install Homebrew from https://brew.sh"

if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "==> installing ffmpeg"
	brew install ffmpeg
fi

if ! uv tool list 2>/dev/null | grep -q '^mlx-audio'; then
	echo "==> installing mlx-audio"
	uv tool install mlx-audio
fi

VP="$(uv tool dir)/mlx-audio/bin/python"
echo "==> installing server extras"
uv pip install --python "$VP" \
	uvicorn fastapi webrtcvad python-multipart "setuptools<81" "misaki[en]"

if ! "$VP" -c "import spacy, spacy.util, sys; sys.exit(0 if spacy.util.is_package('en_core_web_sm') else 1)" 2>/dev/null; then
	echo "==> installing en_core_web_sm"
	WHEEL="en_core_web_sm-3.8.0-py3-none-any.whl"
	TMP="$(mktemp -d)"
	curl -fsSL -o "$TMP/$WHEEL" \
		"https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/$WHEEL"
	uv pip install --python "$VP" "$TMP/$WHEEL"
	rm -rf "$TMP"
fi

echo "==> pre-downloading $MODEL (this can take a few minutes)"
if ! "$VP" - "$MODEL" <<'PY'
import sys
from huggingface_hub import snapshot_download
path = snapshot_download(
    sys.argv[1], allow_patterns=["*.json", "*.safetensors", "*.pth", "voices/*"]
)
print("model ready:", path)
PY
then
	echo "warning: model download incomplete; it will be fetched on first use"
fi

echo
echo "Done. Start the service with :TranslateTtsServer inside Neovim,"
echo "or let tts.autostart handle it on the first :TranslateSay."
