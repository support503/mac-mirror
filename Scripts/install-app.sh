#!/bin/zsh
set -euo pipefail

APP_NAME="MacMirror.app"
SOURCE_APP="${1:-$(cd "$(dirname "$0")" && pwd)/$APP_NAME}"
TARGET_APP="/Applications/$APP_NAME"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Source app not found: $SOURCE_APP" >&2
  exit 1
fi

osascript -e 'tell application id "com.macmirror.app" to quit' >/dev/null 2>&1 || true
sleep 1

rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" >/dev/null 2>&1 || true

open "$TARGET_APP"
echo "Installed $TARGET_APP"
