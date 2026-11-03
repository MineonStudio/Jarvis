#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
FIXTURE_ROOT="$(mktemp -d /tmp/jarvis-layout-fixture.XXXXXX)"
FIXTURE_APP="$FIXTURE_ROOT/JarvisLayoutFixture.app"
FIXTURE_BINARY="$FIXTURE_APP/Contents/MacOS/JarvisLayoutFixture"
FIXTURE_PID=""
cleanup() {
  if [[ -n "$FIXTURE_PID" ]]; then kill "$FIXTURE_PID" 2>/dev/null || true; fi
  rm -rf "$FIXTURE_ROOT"
}
trap cleanup EXIT
mkdir -p "$FIXTURE_APP/Contents/MacOS"
xcrun swiftc -parse-as-library TestAssets/WindowLayoutFixture.swift -o "$FIXTURE_BINARY" -framework AppKit
cat > "$FIXTURE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.jarvis.window-layout-fixture</string>
<key>CFBundleName</key><string>JarvisLayoutFixture</string>
<key>CFBundleExecutable</key><string>JarvisLayoutFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$FIXTURE_APP"
open -n "$FIXTURE_APP"
for _ in {1..30}; do
  FIXTURE_PID="$(pgrep -f -- "$FIXTURE_BINARY" || true)"
  if [[ -n "$FIXTURE_PID" ]]; then break; fi
  sleep 0.1
done
test -n "$FIXTURE_PID"
JARVIS_WINDOW_LAYOUT_FIXTURE_PID="$FIXTURE_PID" swift test \
  --scratch-path /Users/Shared/Jarvis/SwiftPM --filter WindowDragExternalWindowTests
