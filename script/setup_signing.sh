#!/bin/zsh
# Explicit one-time setup on a build Mac. Never run on end-user machines.
set -euo pipefail
umask 077
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYCHAIN="${JARVIS_SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
case "${1:-}" in
  --development) IDENTITY='Jarvis Dev Signing'; PUBLIC_CERT='' ;;
  --release) IDENTITY='Jarvis Release Signing'; PUBLIC_CERT="$ROOT_DIR/Resources/JarvisReleaseSigning.pem" ;;
  *) print -ru2 -- 'Usage: setup_signing.sh --development|--release'; exit 2 ;;
esac
MATCHES="$(security find-identity -p codesigning "$KEYCHAIN" | sed -n "s/.*) \([0-9A-Fa-f]\{40\}\) \"$IDENTITY\".*/\1/p" | sort -u)"
if [[ -n "$MATCHES" ]]; then
  [[ "$MATCHES" != *$'\n'* ]] || { print -ru2 -- 'Multiple matching certificates; restore a unique identity before continuing.'; exit 1; }
  if [[ -n "$PUBLIC_CERT" ]]; then
    [[ -f "$PUBLIC_CERT" ]] || security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$PUBLIC_CERT"
    EXPECTED="$(openssl x509 -in "$PUBLIC_CERT" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
    [[ "$EXPECTED" == "$MATCHES" ]] || { print -ru2 -- 'Release identity differs from the pinned certificate; restore the original private key.'; exit 1; }
  fi
  print -r -- "Existing identity preserved: $IDENTITY ($MATCHES)"
  exit 0
fi
if [[ -n "$PUBLIC_CERT" && -f "$PUBLIC_CERT" ]]; then
  print -ru2 -- 'Release certificate is already pinned. Restore its original private key; setup will not replace it.'
  exit 1
fi
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-signing.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
openssl req -x509 -newkey rsa:3072 -sha256 -days 10950 -nodes \
  -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
  -subj "/CN=$IDENTITY/O=Jarvis" \
  -addext 'basicConstraints=critical,CA:false' \
  -addext 'keyUsage=critical,digitalSignature' \
  -addext 'extendedKeyUsage=critical,codeSigning' >/dev/null 2>&1
security import "$WORK_DIR/cert.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
security import "$WORK_DIR/key.pem" -k "$KEYCHAIN" -T /usr/bin/codesign
if [[ -n "$PUBLIC_CERT" ]]; then
  cp "$WORK_DIR/cert.pem" "$PUBLIC_CERT"
  chmod 644 "$PUBLIC_CERT"
fi
print -r -- "Created $IDENTITY. Back up the certificate and private key as an encrypted .p12 in Keychain Access."
