#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
VERSION="${MAC_MIRROR_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo '0.1.0')}"
BUILD="${MAC_MIRROR_BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo '1')}"
PACKAGE_DIR="$RELEASE_DIR/MacMirror-$VERSION"
ZIP_PATH="$RELEASE_DIR/MacMirror-$VERSION.zip"
WORKFLOW_SOURCE="$ROOT_DIR/Extras/Alfred/build/Mac Mirror.alfredworkflow"
WORKFLOW_ASSET="$RELEASE_DIR/MacMirror-$VERSION.alfredworkflow"
CHECKSUMS_PATH="$RELEASE_DIR/MacMirror-$VERSION-checksums.txt"
INSTALLER_NAME="Install Mac Mirror.command"

cd "$ROOT_DIR"
MAC_MIRROR_VERSION="$VERSION" MAC_MIRROR_BUILD="$BUILD" ./Scripts/package-app.sh
./Extras/Alfred/build-workflow.sh

rm -rf "$PACKAGE_DIR"
rm -f "$ZIP_PATH" "$WORKFLOW_ASSET" "$CHECKSUMS_PATH"
mkdir -p "$PACKAGE_DIR"

cp -R "$DIST_DIR/MacMirror.app" "$PACKAGE_DIR/"
cp "$ROOT_DIR/Scripts/install-app.sh" "$PACKAGE_DIR/$INSTALLER_NAME"
chmod +x "$PACKAGE_DIR/$INSTALLER_NAME"
cp "$WORKFLOW_SOURCE" "$WORKFLOW_ASSET"

cat > "$PACKAGE_DIR/README.txt" <<EOF
Mac Mirror $VERSION

Install:
1. Double-click "$INSTALLER_NAME"
2. Open Mac Mirror from /Applications
3. Grant Accessibility, Screen Recording, and Automation permissions
4. Save a snapshot on this Mac

Update:
- Download the newer release zip
- Run "$INSTALLER_NAME" again
- Your local snapshots in ~/Library/Application Support/MacMirror stay in place
- The app refreshes its helper binaries the next time it launches
EOF

ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$WORKFLOW_ASSET")" > "$(basename "$CHECKSUMS_PATH")"
)

echo "Release assets:"
echo "  $ZIP_PATH"
echo "  $WORKFLOW_ASSET"
echo "  $CHECKSUMS_PATH"
