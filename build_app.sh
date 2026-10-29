#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# File Provider can attach FinderInfo to SwiftPM resource bundles inside the
# project directory, which prevents SwiftPM's own code-signing step.
SWIFTPM_SCRATCH_DIR="${JARVIS_SWIFTPM_SCRATCH_DIR:-/Users/Shared/Jarvis/SwiftPM}"
BUILD_DIR="$SWIFTPM_SCRATCH_DIR/release"
JARVIS_DEV_BUILD="${JARVIS_DEV_BUILD:-0}"
if [[ "$JARVIS_DEV_BUILD" == "1" ]]; then
  DEFAULT_APP_DIR="$ROOT_DIR/dist/Jarvis-Dev.app"
  DEFAULT_BUNDLE_IDENTIFIER="com.jarvis.mac.dev"
  DEFAULT_DISPLAY_NAME="工作搭子 Jarvis 开发版"
  DEFAULT_BUNDLE_NAME="Jarvis-Dev"
  # Development builds sign with a stable local identity so TCC and Keychain
  # grants survive rebuilds. Ad-hoc signing derives a new identity from every
  # binary, which makes macOS treat each build as a different app.
  DEFAULT_CODESIGN_IDENTITY="Jarvis Dev Signing"
  DEFAULT_INSTALL_SOURCE="development"
else
  DEFAULT_APP_DIR="$ROOT_DIR/dist/Jarvis.app"
  DEFAULT_BUNDLE_IDENTIFIER="com.jarvis.mac"
  DEFAULT_DISPLAY_NAME="工作搭子 Jarvis"
  DEFAULT_BUNDLE_NAME="Jarvis"
  DEFAULT_CODESIGN_IDENTITY=""
  DEFAULT_INSTALL_SOURCE="direct-download"
fi
JARVIS_CODESIGN_IDENTITY="${JARVIS_CODESIGN_IDENTITY:-$DEFAULT_CODESIGN_IDENTITY}"
APP_DIR="${JARVIS_APP_DIR:-$DEFAULT_APP_DIR}"
JARVIS_BUNDLE_IDENTIFIER="${JARVIS_BUNDLE_IDENTIFIER:-$DEFAULT_BUNDLE_IDENTIFIER}"
JARVIS_DISPLAY_NAME="${JARVIS_DISPLAY_NAME:-$DEFAULT_DISPLAY_NAME}"
JARVIS_BUNDLE_NAME="${JARVIS_BUNDLE_NAME:-$DEFAULT_BUNDLE_NAME}"
JARVIS_INSTALL_SOURCE="${JARVIS_INSTALL_SOURCE:-$DEFAULT_INSTALL_SOURCE}"
JARVIS_VERSION="${JARVIS_VERSION:-1.8.16}"
JARVIS_BUILD="${JARVIS_BUILD:-379}"
ICON_ASSET_NAME="jarvis-${JARVIS_VERSION//./-}"

cd "$ROOT_DIR"
swift build -c release --scratch-path "$SWIFTPM_SCRATCH_DIR"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/Jarvis" "$APP_DIR/Contents/MacOS/Jarvis"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -d "$ROOT_DIR/Resources/AIProviderIcons" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/AIProviderIcons"
  for staleIcon in \
    "$APP_DIR/Contents/Resources/AIProviderIcons"/*.png(N) \
    "$APP_DIR/Contents/Resources/AIProviderIcons"/*.svg(N); do
    rm -f "$staleIcon"
  done
  cp "$ROOT_DIR/Resources/AIProviderIcons"/*.png \
     "$ROOT_DIR/Resources/AIProviderIcons"/*.svg \
     "$APP_DIR/Contents/Resources/AIProviderIcons/"
fi

if [[ -d "$ROOT_DIR/Resources/WallpaperSourceIcons" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/WallpaperSourceIcons"
  cp "$ROOT_DIR/Resources/WallpaperSourceIcons"/*.png \
     "$APP_DIR/Contents/Resources/WallpaperSourceIcons/"
fi

if [[ -d "$ROOT_DIR/Resources/EntertainmentIcons" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/EntertainmentIcons"
  for staleIcon in "$APP_DIR/Contents/Resources/EntertainmentIcons"/*.svg(N); do
    rm -f "$staleIcon"
  done
  cp "$ROOT_DIR/Resources/EntertainmentIcons"/*.svg \
     "$APP_DIR/Contents/Resources/EntertainmentIcons/"
fi

if [[ -d "$ROOT_DIR/Resources/GameArtwork" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/GameArtwork"
  cp "$ROOT_DIR/Resources/GameArtwork"/*.svg \
     "$APP_DIR/Contents/Resources/GameArtwork/"
  cp "$ROOT_DIR/Resources/GameArtwork/mahjong-launch-background.png" \
     "$APP_DIR/Contents/Resources/GameArtwork/"
  cp "$ROOT_DIR/Resources/GameArtwork/mahjong-poster.png" \
     "$APP_DIR/Contents/Resources/GameArtwork/"
  if [[ -d "$ROOT_DIR/Resources/GameArtwork/Avatars" ]]; then
    mkdir -p "$APP_DIR/Contents/Resources/GameArtwork/Avatars"
    for staleAvatar in "$APP_DIR/Contents/Resources/GameArtwork/Avatars"/*.png(N); do
      rm -f "$staleAvatar"
    done
    cp "$ROOT_DIR/Resources/GameArtwork/Avatars"/*.png \
       "$APP_DIR/Contents/Resources/GameArtwork/Avatars/"
  fi
fi

if [[ -d "$ROOT_DIR/Resources/MahjongAudio" ]]; then
  rm -rf "$APP_DIR/Contents/Resources/MahjongAudio"
  ditto "$ROOT_DIR/Resources/MahjongAudio" "$APP_DIR/Contents/Resources/MahjongAudio"
fi

# Keep production builds compatible with the installed app. Development
# builds opt into a separate identity so LaunchServices, TCC, preferences,
# Keychain entries, and application data remain isolated from production.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $JARVIS_BUNDLE_IDENTIFIER" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $JARVIS_DISPLAY_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $JARVIS_BUNDLE_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $JARVIS_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $JARVIS_BUILD" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconName $ICON_ASSET_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :JarvisInstallSource $JARVIS_INSTALL_SOURCE" "$APP_DIR/Contents/Info.plist"

# Remove obsolete custom menu resources from upgraded bundles.
rm -f "$APP_DIR/Contents/Resources/JarvisMenuIcon.png" \
      "$APP_DIR/Contents/Resources/JarvisMenuBarIcon.png" \
      "$APP_DIR/Contents/Resources/JarvisMenuBarCapsuleDark.png" \
      "$APP_DIR/Contents/Resources/JarvisMenuBarCapsuleLight.png" \
      "$APP_DIR/Contents/Resources/HermesIcon.png"

# Use the native Icon Composer asset as the Dock/Finder icon source. This
# preserves the layered macOS 26 composition instead of flattening it into a
# square PNG inside the system's rounded Dock tile. Keep CFBundleIconFile out
# of Info.plist: that legacy key makes Dock prefer the static jarvis.icns and
# bypass the light/dark Icon Composer specialization.
ICON_COMPOSER_DIR="$ROOT_DIR/Resources/jarvis.icon"
ASSET_PARTIAL_INFO="$APP_DIR/Contents/assetcatalog-info.plist"
rm -f "$APP_DIR/Contents/Resources/Assets.car" \
      "$APP_DIR/Contents/Resources/AppIcon.icns" \
      "$APP_DIR/Contents/Resources/Jarvis.icns" \
      "$APP_DIR/Contents/Resources/jarvis.icns" \
      "$ASSET_PARTIAL_INFO"
rm -rf "$APP_DIR/Contents/Resources/DockIcons"

if [[ -d "$ICON_COMPOSER_DIR" ]]; then
  # Keep the layered asset intact: macOS controls Default, Dark, Clear, and
  # Tinted styles through its system-wide icon appearance setting.
  ICON_BUILD_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-icon-build.XXXXXX")"
  trap 'rm -rf "$ICON_BUILD_TEMP"' EXIT

  ditto "$ICON_COMPOSER_DIR" "$ICON_BUILD_TEMP/$ICON_ASSET_NAME.icon"
  xcrun actool \
    "$ICON_BUILD_TEMP/$ICON_ASSET_NAME.icon" \
    --compile "$APP_DIR/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon "$ICON_ASSET_NAME" \
    --output-partial-info-plist "$ASSET_PARTIAL_INFO" \
    --notices \
    --warnings >/dev/null
  rm -f "$ASSET_PARTIAL_INFO"
  # A version-specific asset name forces LaunchServices and Dock to resolve
  # a fresh icon after an upgrade, even when the bundle identifier is stable.
  # Keep only Assets.car so CFBundleIconName resolves the adaptive source.
  rm -f "$APP_DIR/Contents/Resources/$ICON_ASSET_NAME.icns"
fi

ENTITLEMENTS="$ROOT_DIR/Resources/Jarvis.entitlements"
# Cloud-backed workspaces can attach Finder/File Provider attributes to copied
# bundle files. Code signing rejects these attributes on the generated app.
xattr -cr "$APP_DIR"
# The self-signed development certificate is not a trusted root, so Keychain
# reports it only under the plain code-signing policy, not the "valid
# identities" list that `security find-identity -v` prints.
if [[ -n "$JARVIS_CODESIGN_IDENTITY" ]] \
   && ! security find-identity -p codesigning 2>/dev/null | grep -qF "$JARVIS_CODESIGN_IDENTITY"; then
  echo "warning: signing identity '$JARVIS_CODESIGN_IDENTITY' not found; using ad-hoc instead" >&2
  JARVIS_CODESIGN_IDENTITY=""
fi

if [[ -n "$JARVIS_CODESIGN_IDENTITY" ]]; then
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$JARVIS_CODESIGN_IDENTITY" "$APP_DIR" >/dev/null
else
  # Shipping default is ad-hoc: there is no paid Apple Developer ID to sign
  # or notarize with. Each new binary is a new TCC identity, so in-app
  # updates must tccutil-reset Screen Recording, Accessibility, Microphone,
  # and Camera before
  # replacing the bundle (see JarvisPrivacyPermissionReset).
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP_DIR" >/dev/null
fi

# Refresh the local LaunchServices registration so System Settings and Finder
# resolve the standalone ICNS immediately after a local production build.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi
echo "Built: $APP_DIR"
