#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

cat > "$ROOT_DIR/project.yml" <<EOF
name: MacMirror
options:
  bundleIdPrefix: com.macmirror
targets:
  MacMirror:
    type: application
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - Sources/MacMirrorCore
      - Sources/MacMirrorApp
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.macmirror.app
        INFOPLIST_KEY_LSUIElement: YES
  mac-mirror:
    type: tool
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - Sources/MacMirrorCore
      - Sources/MacMirrorCLI
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.macmirror.cli
  mac-mirror-login:
    type: tool
    platform: macOS
    deploymentTarget: "13.0"
    sources:
      - Sources/MacMirrorCore
      - Sources/MacMirrorLogin
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.macmirror.login
EOF

cd "$ROOT_DIR"
xcodegen generate
