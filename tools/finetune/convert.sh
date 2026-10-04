#!/usr/bin/env bash
# Merged HF model -> GGUF (Q8_0, ~290 MB) that llamadart / llama.cpp can run.
set -euo pipefail
cd "$(dirname "$0")"
[ -d llama.cpp ] || git clone --depth 1 https://github.com/ggml-org/llama.cpp
.venv/bin/python llama.cpp/convert_hf_to_gguf.py out/merged \
  --outtype q8_0 --outfile health-extractor-270m-q8_0.gguf
ls -lh health-extractor-270m-q8_0.gguf
