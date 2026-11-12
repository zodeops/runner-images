#!/usr/bin/env bash
# Creates a release of one line on Zode and follows it until it is published
# or failed. Runs in the publish workflow on main: the API only takes a
# GitHub Actions OIDC token from zodeops/runner-images at refs/heads/main.
#
#   scripts/release.sh LINE VERSION
#
# Environment: ZODE_API (default https://api.zode.dev), GITHUB_SHA,
# ACTIONS_ID_TOKEN_REQUEST_URL and ACTIONS_ID_TOKEN_REQUEST_TOKEN (set by
# GitHub when the job has id-token: write), POLL_SECONDS (30),
# TIMEOUT_SECONDS (10800). Writes release_id to GITHUB_OUTPUT when set.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 LINE VERSION" >&2; exit 2; }
LINE=$1
VERSION=$2
API=${ZODE_API:-https://api.zode.dev}
AUDIENCE=https://api.zode.dev
POLL=${POLL_SECONDS:-30}
TIMEOUT=${TIMEOUT_SECONDS:-10800}
DOCKERFILE=images/$LINE/Dockerfile

cd "$(dirname "$0")/.."
[ -f "$DOCKERFILE" ] || { echo "no $DOCKERFILE" >&2; exit 1; }
grep -qE '^ARG IMAGE_VERSION=' "$DOCKERFILE" || { echo "$DOCKERFILE has no ARG IMAGE_VERSION=" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The Dockerfile as sent: the release version stamped into ARG IMAGE_VERSION.
sed -E "s/^ARG IMAGE_VERSION=.*/ARG IMAGE_VERSION=$VERSION/" "$DOCKERFILE" >"$work/Dockerfile"

# GitHub Actions OIDC token for the Zode API.
: "${ACTIONS_ID_TOKEN_REQUEST_URL:?the job needs permissions: id-token: write}"
: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?the job needs permissions: id-token: write}"
token=$(curl -fsS --retry 3 -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=$(jq -rn --arg a "$AUDIENCE" '$a | @uri')" | jq -r .value)
if [ -z "$token" ] || [ "$token" = null ]; then echo "no OIDC token" >&2; exit 1; fi
echo "::add-mask::$token"

jq -n --arg line "$LINE" --arg version "$VERSION" --arg commit "${GITHUB_SHA:-$(git rev-parse HEAD)}" \
  --rawfile dockerfile "$work/Dockerfile" \
  '{line: $line, version: $version, dockerfile: $dockerfile, commit: $commit}' >"$work/request.json"

code=$(curl -sS -o "$work/created.json" -w '%{http_code}' -X POST "$API/v1/official/releases" \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json' --data-binary "@$work/request.json")
if [ "$code" != 202 ] && [ "$code" != 201 ] && [ "$code" != 200 ]; then
  echo "POST /v1/official/releases answered $code:" >&2
  cat "$work/created.json" >&2
  echo >&2
  exit 1
fi
id=$(jq -r .id "$work/created.json")
echo "release $id: $LINE $VERSION"
if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "release_id=$id" >>"$GITHUB_OUTPUT"; fi

# table: tab-separated rows as aligned columns.
table() {
  if command -v column >/dev/null; then column -t -s "$(printf '\t')"; else cat; fi
}

# Follow it. The build table is printed whenever it changes.
deadline=$(($(date +%s) + TIMEOUT))
last=""
misses=0
while :; do
  if curl -fsS --max-time 30 -o "$work/release.json" "$API/v1/official/releases/$id"; then
    misses=0
    status=$(jq -r .status "$work/release.json")
    rows=$(jq -r '.builds // [] | sort_by(.node, .size)[] | [.node, .size, .status] | @tsv' "$work/release.json")
    if [ "$status|$rows" != "$last" ]; then
      echo "$(date -u +%H:%M:%S) release $status"
      { printf 'NODE\tSIZE\tSTATUS\n'; printf '%s\n' "$rows"; } | table
      last="$status|$rows"
    fi
    case "$status" in
      published)
        echo "published $LINE $VERSION"
        exit 0
        ;;
      failed)
        err=$(jq -r '.error // ""' "$work/release.json")
        echo "::error title=release failed::$LINE $VERSION: ${err:-a build failed}"
        jq -r '.builds[] | select(.status == "failed")
          | "::group::build on \(.node) \(.size) failed: \(.error // "")\n\(.log_tail // "(no log)")\n::endgroup::"' \
          "$work/release.json"
        exit 1
        ;;
      building) ;;
      *)
        echo "::error::release $id is $status (a newer release may have replaced it)"
        exit 1
        ;;
    esac
  else
    misses=$((misses + 1))
    echo "could not read the release ($misses in a row)" >&2
    [ "$misses" -lt 10 ] || exit 1
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "::error::release $id still building after $((TIMEOUT / 60)) minutes"
    exit 1
  fi
  sleep "$POLL"
done
