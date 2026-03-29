#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

patterns=(
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]+'
  'AKIA[0-9A-Z]{16}'
  'AIza[0-9A-Za-z\-_]{35}'
  'xox[baprs]-[A-Za-z0-9-]+'
  '-----BEGIN (RSA|OPENSSH|EC|DSA|PGP|PRIVATE KEY)'
  '/Users/'
  '@topsearchresult\.'
  '@rbdawson\.'
  '@codesm\.'
  'support@'
  'robert dawson'
)

if command -v rg >/dev/null 2>&1; then
  files=("${(@f)$(git ls-files | rg -v '^Scripts/privacy-audit\.sh$')}")
  search_tool=(rg -n -i --)
else
  files=("${(@f)$(git ls-files | grep -Ev '^Scripts/privacy-audit\.sh$')}")
  search_tool=(grep -E -n -i --)
fi

if (( ${#files[@]} == 0 )); then
  echo "No tracked files to audit."
  exit 0
fi

exit_code=0
audit_output="/tmp/mac-mirror-privacy-audit.txt"
for pattern in "${patterns[@]}"; do
  if "${search_tool[@]}" "${pattern}" "${files[@]}" >"$audit_output" 2>/dev/null; then
    echo "Privacy audit failed for pattern: ${pattern}" >&2
    cat "$audit_output" >&2
    exit_code=1
  fi
done

rm -f "$audit_output"

if (( exit_code != 0 )); then
  exit "$exit_code"
fi

echo "Privacy audit passed."
