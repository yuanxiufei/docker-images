#!/usr/bin/env python3
"""Download model from Hugging Face mirror for vLLM."""
import os
import sys

# Use HF mirror for China
os.environ["HF_ENDPOINT"] = "https://hf-mirror.com"

from huggingface_hub import snapshot_download

MODEL_ID = "Qwen/Qwen3-0.6B"
CACHE_DIR = "/mnt/d/docker-images/models"

print(f"Downloading {MODEL_ID} to {CACHE_DIR}...")
print(f"HF_ENDPOINT: {os.environ['HF_ENDPOINT']}")

try:
    path = snapshot_download(
        MODEL_ID,
        cache_dir=CACHE_DIR,
        resume_download=True,
        max_workers=4,
    )
    print(f"Done! Model saved to: {path}")
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
