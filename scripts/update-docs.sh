#!/usr/bin/env bash
# Rewrites images/<LINE>/README.md and the software section of README.md
# from the public catalogue, once it shows LINE at VERSION.
#
#   scripts/update-docs.sh LINE VERSION
#
# The catalogue is cached for 60 s, so a just-published release can take a
# minute to appear. Environment: ZODE_API (default https://api.zode.dev).
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 LINE VERSION" >&2; exit 2; }
LINE=$1
VERSION=$2
API=${ZODE_API:-https://api.zode.dev}

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for i in $(seq 1 20); do
  if curl -fsS --max-time 30 -o "$work/catalogue.json" "$API/v1/official-images" &&
    [ "$(jq -r --arg l "$LINE" '.images[]? | select(.line == $l) | .version' "$work/catalogue.json")" = "$VERSION" ]; then
    break
  fi
  if [ "$i" = 20 ]; then
    echo "the catalogue does not show $LINE $VERSION yet" >&2
    exit 1
  fi
  sleep 15
done

scripts/manifest-to-md.sh "$LINE" "$work/catalogue.json" >"images/$LINE/README.md"

# Replace what sits between the markers in README.md.
scripts/manifest-to-md.sh --summary "$work/catalogue.json" >"$work/summary.md"
awk -v summary="$work/summary.md" '
  /<!-- software:start -->/ { print; while ((getline l < summary) > 0) print l; skip = 1; next }
  /<!-- software:end -->/ { skip = 0 }
  !skip { print }
' README.md >"$work/README.md"
grep -q '<!-- software:end -->' "$work/README.md" || { echo "README.md lost its software:end marker" >&2; exit 1; }
mv "$work/README.md" README.md
echo "updated images/$LINE/README.md and README.md"
