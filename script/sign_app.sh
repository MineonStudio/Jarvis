#!/bin/zsh
# Shared publisher signing path. Never creates identities or falls back to ad-hoc.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:?Usage: sign_app.sh <app> [development|release]}"
SIGNING_MODE="${2:-release}"
KEYCHAIN="${JARVIS_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
if [[ "$SIGNING_MODE" == development ]]; then
  IDENTITY="${JARVIS_CODESIGN_IDENTITY:-Jarvis Dev Signing}"
  MATCHES="$(security find-identity -p codesigning "$KEYCHAIN" | sed -n "s/.*) \([0-9A-Fa-f]\{40\}\) \"$IDENTITY\".*/\1/p" | sort -u)"
  [[ -n "$MATCHES" && "$MATCHES" != *$'\n'* ]] || {
    print -ru2 -- 'Missing or ambiguous development identity. Run ./script/setup_signing.sh --development, or restore your certificate.'
    exit 1
  }
  FINGERPRINT="$MATCHES"
elif [[ "$SIGNING_MODE" == release ]]; then
  CERTIFICATE="$ROOT_DIR/Resources/JarvisReleaseSigning.pem"
  [[ -f "$CERTIFICATE" ]] || { print -ru2 -- 'Release certificate not initialized. Run ./script/setup_signing.sh --release once.'; exit 1; }
  FINGERPRINT="$(openssl x509 -in "$CERTIFICATE" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
else
  print -ru2 -- "Unknown signing mode: $SIGNING_MODE"
  exit 2
fi
# Bound an unanswered macOS Keychain prompt; never leave a build hung forever.
codesign --force --options runtime --timestamp=none --keychain "$KEYCHAIN" \
  --entitlements "$ROOT_DIR/Resources/Jarvis.entitlements" --sign "$FINGERPRINT" "$APP_DIR" &
SIGN_PID=$!
(
  sleep 120
  if kill -0 "$SIGN_PID" 2>/dev/null; then
    print -ru2 -- 'Timed out waiting for code signing. Complete the macOS Keychain prompt and retry; no ad-hoc fallback was used.'
    kill -TERM "$SIGN_PID" 2>/dev/null || true
  fi
) &
WATCHDOG_PID=$!
trap 'kill "$WATCHDOG_PID" 2>/dev/null || true' EXIT
SIGN_STATUS=0
wait "$SIGN_PID" || SIGN_STATUS=$?
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true
trap - EXIT
if (( SIGN_STATUS != 0 )); then
  rm -f "$APP_DIR/Contents/MacOS/Jarvis.cstemp"
  exit "$SIGN_STATUS"
fi
codesign --verify --deep --strict "$APP_DIR"
