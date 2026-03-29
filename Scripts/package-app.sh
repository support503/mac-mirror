#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MacMirror.app"
VERSION="${MAC_MIRROR_VERSION:-0.1.0}"
BUILD="${MAC_MIRROR_BUILD:-1}"

cd "$ROOT_DIR"
swift build -c release --product MacMirror
swift build -c release --product mac-mirror
swift build -c release --product mac-mirror-login

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/MacMirror" "$APP_DIR/Contents/MacOS/MacMirror"
cp "$BUILD_DIR/mac-mirror" "$APP_DIR/Contents/MacOS/mac-mirror"
cp "$BUILD_DIR/mac-mirror-login" "$APP_DIR/Contents/MacOS/mac-mirror-login"
chmod +x "$APP_DIR/Contents/MacOS/MacMirror" "$APP_DIR/Contents/MacOS/mac-mirror" "$APP_DIR/Contents/MacOS/mac-mirror-login"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacMirror</string>
  <key>CFBundleIdentifier</key>
  <string>com.macmirror.app</string>
  <key>CFBundleName</key>
  <string>Mac Mirror</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
EOF

echo "Packaged $APP_DIR ($VERSION build $BUILD)"
