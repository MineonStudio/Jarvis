#!/bin/zsh
# Installs the publisher-signed app without creating or modifying any keys.
set -euo pipefail
umask 077
REPOSITORY="MineonStudio/Jarvis"
BUNDLE_IDENTIFIER="com.jarvis.mac"
RELEASE_CERTIFICATE_SHA1="775BBDC3A7E604D25E2FABB204E2FD23349A61C8"
INSTALL_DIR="${JARVIS_INSTALL_DIR:-/Applications}"
APP_PATH="$INSTALL_DIR/Jarvis.app"
LAUNCH_AFTER_INSTALL=1
UNINSTALL=0
WORK_DIR=''
BACKUP_PATH=''
cleanup() {
  [[ -z "$WORK_DIR" ]] || rm -rf "$WORK_DIR"
}
trap cleanup EXIT
die() { print -ru2 -- "错误：$*"; exit 1; }
for argument in "$@"; do
  case "$argument" in
    --uninstall) UNINSTALL=1 ;;
    --no-launch) LAUNCH_AFTER_INSTALL=0 ;;
    -h|--help) print -r -- '用法：zsh install.sh [--no-launch] [--uninstall]'; exit 0 ;;
    *) die "未知参数：$argument" ;;
  esac
done
[[ "$(uname -s)" == Darwin ]] || die '只能在 macOS 上运行。'
quit_running_app_if_replacing() {
  [[ -d "$APP_PATH" ]] || return 0
  local target="$APP_PATH/Contents/MacOS/Jarvis"
  app_is_running() {
    /bin/ps -axo pid=,command= | /usr/bin/grep -F "$target" | /usr/bin/grep -v -F /usr/bin/grep >/dev/null 2>&1
  }
  app_is_running || return 0
  osascript -e 'tell application id "com.jarvis.mac" to quit' >/dev/null 2>&1 || true
  local tick
  for tick in {1..150}; do
    app_is_running || return 0
    sleep 0.1
  done
  die 'Jarvis 仍在运行，请先退出后再安装。'
}
if (( UNINSTALL )); then
  quit_running_app_if_replacing
  rm -rf "$APP_PATH"
  print -r -- "已移除 $APP_PATH；应用数据与钥匙串未改动。"
  exit 0
fi
mkdir -p "$INSTALL_DIR"
[[ -w "$INSTALL_DIR" ]] || die "$INSTALL_DIR 不可写。"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-install.XXXXXX")"
curl -fsSL -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/$REPOSITORY/releases/latest" -o "$WORK_DIR/release.json"
# Native JSON parsing, with exact asset selection; no Python or Swift install required.
cat > "$WORK_DIR/release.js" <<'JXA'
ObjC.import('Foundation');
function run(args) {
  const content = $.NSString.stringWithContentsOfFileEncodingError(args[0], $.NSUTF8StringEncoding, null);
  const release = JSON.parse(ObjC.unwrap(content));
  const version = release.tag_name.replace(/^v/, '');
  if (!/^\d+(\.\d+)*$/.test(version) || release.prerelease || release.draft) throw Error('Invalid stable release');
  const asset = release.assets.find(a => a.name === 'Jarvis-' + version + '-macos.zip');
  if (!asset || !/^sha256:[a-f0-9]{64}$/.test(asset.digest || '')) throw Error('Missing archive digest');
  const url = 'https://github.com/MineonStudio/Jarvis/releases/download/v' + version + '/' + asset.name;
  if (asset.browser_download_url !== url) throw Error('Unexpected asset URL');
  return [version, url, asset.digest].join('\n');
}
JXA
RELEASE_INFO="$(osascript -l JavaScript "$WORK_DIR/release.js" "$WORK_DIR/release.json")"
FIELDS=("${(@f)RELEASE_INFO}")
[[ "${#FIELDS}" == 3 ]] || die '无法读取发布信息。'
VERSION="$FIELDS[1]"
curl -fsSL "$FIELDS[2]" -o "$WORK_DIR/Jarvis.zip"
ACTUAL="sha256:$(shasum -a 256 "$WORK_DIR/Jarvis.zip" | cut -d' ' -f1)"
[[ "$ACTUAL" == "$FIELDS[3]" ]] || die '安装包校验和不匹配。'
ditto -x -k "$WORK_DIR/Jarvis.zip" "$WORK_DIR/extracted"
SOURCE_APP="$WORK_DIR/extracted/Jarvis.app"
[[ -d "$SOURCE_APP" ]] || die '安装包中没有 Jarvis.app。'
REQUIREMENT="identifier \"$BUNDLE_IDENTIFIER\" and certificate root = H\"$RELEASE_CERTIFICATE_SHA1\""
codesign --verify --deep --strict -R "=$REQUIREMENT" "$SOURCE_APP" || die '发布证书校验失败。'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")" == "$BUNDLE_IDENTIFIER" ]] || die 'Bundle ID 不匹配。'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_APP/Contents/Info.plist")" == "$VERSION" ]] || die '版本不匹配。'
# Stage and validate at the destination before interrupting an installed copy.
STAGED_PATH="$(mktemp -d "$INSTALL_DIR/.jarvis-install.XXXXXX")"
if ! ditto "$SOURCE_APP" "$STAGED_PATH/Jarvis.app" || ! codesign --verify --deep --strict -R "=$REQUIREMENT" "$STAGED_PATH/Jarvis.app"; then
  rm -rf "$STAGED_PATH"
  die '复制或签名校验失败，原安装未改动。'
fi
xattr -dr com.apple.quarantine "$STAGED_PATH/Jarvis.app" 2>/dev/null || true
quit_running_app_if_replacing
BACKUP_PATH="$STAGED_PATH/Previous.app"
if [[ -e "$APP_PATH" ]]; then
  mv "$APP_PATH" "$BACKUP_PATH" || die '无法备份原安装。'
fi
if ! mv "$STAGED_PATH/Jarvis.app" "$APP_PATH"; then
  [[ ! -e "$BACKUP_PATH" ]] || mv "$BACKUP_PATH" "$APP_PATH"
  die '安装失败，已尝试恢复原安装。'
fi
if (( LAUNCH_AFTER_INSTALL )) && ! open "$APP_PATH"; then
  rm -rf "$APP_PATH"
  [[ ! -e "$BACKUP_PATH" ]] || mv "$BACKUP_PATH" "$APP_PATH"
  die '启动失败，已尝试恢复原安装。'
fi
rm -rf "$STAGED_PATH"
print -r -- "已安装 $VERSION 到 $APP_PATH。首次使用请在应用中授权。"
