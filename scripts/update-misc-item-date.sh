#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 misc-items/<item>.md" >&2
  exit 1
fi

file="$1"
if [[ ! -f "$file" ]]; then
  echo "File not found: $file" >&2
  exit 1
fi

today="$(date +%Y-%m-%d)"

if rg -q "Last Updated:" "$file"; then
  perl -pi -e "s#Last Updated:\\s*\\d{4}-\\d{2}-\\d{2}#Last Updated: $today#g" "$file"
else
  echo "No 'Last Updated:' line found in $file" >&2
  exit 1
fi

echo "Updated $file -> Last Updated: $today"
