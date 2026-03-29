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

files=("${(@f)$(git ls-files | rg -v '^Scripts/privacy-audit\.sh$')}")
if (( ${#files[@]} == 0 )); then
  echo "No tracked files to audit."
  exit 0
fi

exit_code=0
for pattern in "${patterns[@]}"; do
  if rg -n -i --glob '!dist/**' --glob '!.build/**' --glob '!Extras/Alfred/build/**' -- "${pattern}" "${files[@]}" >/tmp/mac-mirror-privacy-audit.txt 2>/dev/null; then
    echo "Privacy audit failed for pattern: ${pattern}" >&2
    cat /tmp/mac-mirror-privacy-audit.txt >&2
    exit_code=1
  fi
done

rm -f /tmp/mac-mirror-privacy-audit.txt

if (( exit_code != 0 )); then
  exit "$exit_code"
fi

echo "Privacy audit passed."
