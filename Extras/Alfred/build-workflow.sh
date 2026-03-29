#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_DIR="$ROOT_DIR/Extras/Alfred/build/workflow-src"
OUTPUT_DIR="$ROOT_DIR/Extras/Alfred/build"
CLI_PATH="$HOME/Library/Application Support/MacMirror/bin/mac-mirror"

rm -rf "$WORK_DIR"
rm -rf "$OUTPUT_DIR/Mac Mirror.alfredworkflow"
mkdir -p "$WORK_DIR"

cat > "$WORK_DIR/info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>bundleid</key>
  <string>com.macmirror.alfred</string>
  <key>category</key>
  <string>Productivity</string>
  <key>connections</key>
  <dict>
    <key>picker</key>
    <array>
      <dict>
        <key>destinationuid</key>
        <string>restore</string>
        <key>modifiers</key>
        <integer>0</integer>
        <key>modifiersubtext</key>
        <string></string>
      </dict>
    </array>
  </dict>
  <key>createdby</key>
  <string>Mac Mirror</string>
  <key>description</key>
  <string>Pick and restore Mac Mirror snapshots.</string>
  <key>name</key>
  <string>Mac Mirror</string>
  <key>objects</key>
  <array>
    <dict>
      <key>config</key>
      <dict>
        <key>keyword</key>
        <string>mm</string>
        <key>title</key>
        <string>Mac Mirror snapshots</string>
        <key>withspace</key>
        <true/>
      </dict>
      <key>type</key>
      <string>alfred.workflow.input.keyword</string>
      <key>uid</key>
      <string>keyword</string>
    </dict>
    <dict>
      <key>config</key>
      <dict>
        <key>escaping</key>
        <integer>0</integer>
        <key>script</key>
        <string>$CLI_PATH snapshot list | awk 'BEGIN { print "{\"items\":[" } NR&gt;1 { printf "," } { split(\$0, parts, "\t"); gsub(/^\* /, "", parts[1]); printf "{\"title\":\"%s\",\"subtitle\":\"Restore snapshot\",\"arg\":\"%s\"}", parts[1], parts[1] } END { print "]}" }'</string>
      </dict>
      <key>type</key>
      <string>alfred.workflow.input.scriptfilter</string>
      <key>uid</key>
      <string>picker</string>
    </dict>
    <dict>
      <key>config</key>
      <dict>
        <key>script</key>
        <string>$CLI_PATH snapshot restore "{query}"</string>
        <key>type</key>
        <integer>0</integer>
      </dict>
      <key>type</key>
      <string>alfred.workflow.action.script</string>
      <key>uid</key>
      <string>restore</string>
    </dict>
  </array>
  <key>uidata</key>
  <dict>
    <key>keyword</key>
    <dict>
      <key>xpos</key>
      <real>20</real>
      <key>ypos</key>
      <real>50</real>
    </dict>
    <key>picker</key>
    <dict>
      <key>xpos</key>
      <real>220</real>
      <key>ypos</key>
      <real>50</real>
    </dict>
    <key>restore</key>
    <dict>
      <key>xpos</key>
      <real>420</real>
      <key>ypos</key>
      <real>50</real>
    </dict>
  </dict>
  <key>variablesdontexport</key>
  <array/>
  <key>version</key>
  <string>1.0</string>
  <key>webaddress</key>
  <string>https://github.com/support503/mac-mirror</string>
</dict>
</plist>
EOF

mkdir -p "$OUTPUT_DIR"
cd "$WORK_DIR"
zip -r "$OUTPUT_DIR/Mac Mirror.alfredworkflow" . >/dev/null
echo "Built $OUTPUT_DIR/Mac Mirror.alfredworkflow"
