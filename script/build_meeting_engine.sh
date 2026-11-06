#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CARGO_BIN="${JARVIS_CARGO_BIN:-$HOME/.cargo/bin/cargo}"
if [[ ! -x "$CARGO_BIN" ]]; then
  CARGO_BIN="$(command -v cargo || true)"
fi
if [[ -z "$CARGO_BIN" || ! -x "$CARGO_BIN" ]]; then
  echo 'Rust 1.95 is required to build the meeting engine. Install rustup from https://rustup.rs.' >&2
  exit 1
fi
export CARGO_TARGET_DIR="${JARVIS_ENGINE_BUILD_DIR:-/Users/Shared/Jarvis/MeetingEngine}"
cd "$ROOT_DIR/Engine/Meeting"
"$CARGO_BIN" build --release --locked
