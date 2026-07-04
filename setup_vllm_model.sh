#!/bin/bash
set -e
SRC="/root/.cache/modelscope/Qwen/Qwen3-0___6B"
HF_DIR="/root/.cache/huggingface/hub/models--Qwen--Qwen3-0.6B"
SNAP_DIR="${HF_DIR}/snapshots/main123"

mkdir -p "$SNAP_DIR"
cp "$SRC"/* "$SNAP_DIR"/
mkdir -p "${HF_DIR}/refs"
echo "main123" > "${HF_DIR}/refs/main"

echo "Files in snapshot:"
ls "$SNAP_DIR"
echo "DONE"
