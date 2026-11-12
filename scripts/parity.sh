#!/usr/bin/env bash
# Writes what differs between a Zode line and GitHub's hosted runner image,
# as Markdown, from the two software reports:
#
#   GitHub: internal.<image>.json, attached to every actions/runner-images
#           release (the source of GitHub's own Ubuntu2404-Readme.md);
#   Zode:   the line's manifest (`zode-software-report`), from the public
#           catalogue or a file.
#
#   scripts/parity.sh [options] LINE
#     --github FILE      GitHub's report instead of downloading the latest
#     --github-tag TAG   which release to download (default: newest ubuntu24/*)
#     --manifest FILE    a bare Zode manifest (the ZODE-MANIFEST JSON)
#     --catalogue FILE   GET /v1/official-images body (default: fetched)
#     --json FILE        also write the comparison as JSON
#
# Notes on why something is missing come from images/LINE/parity.tsv.
# Environment: ZODE_API (default https://api.zode.dev), GH_TOKEN (optional,
# raises GitHub's rate limit).
set -euo pipefail

usage() {
  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

GITHUB_FILE="" GITHUB_TAG="" MANIFEST_FILE="" CATALOGUE_FILE="" JSON_OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --github) GITHUB_FILE=$2; shift 2 ;;
    --github-tag) GITHUB_TAG=$2; shift 2 ;;
    --manifest) MANIFEST_FILE=$2; shift 2 ;;
    --catalogue) CATALOGUE_FILE=$2; shift 2 ;;
    --json) JSON_OUT=$2; shift 2 ;;
    -h | --help) usage ;;
    -*) echo "unknown option $1" >&2; usage ;;
    *) break ;;
  esac
done
[ $# -eq 1 ] || usage
LINE=$1
API=${ZODE_API:-https://api.zode.dev}
GH_API=https://api.github.com/repos/actions/runner-images

cd "$(dirname "$0")/.."
POLICY=images/$LINE/parity.tsv
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The GitHub image a line is compared with.
case "$LINE" in
  ci-ubuntu-24.04) GH_IMAGE=ubuntu24 ;;
  *) echo "no GitHub image to compare $LINE with" >&2; exit 1 ;;
esac

gh_get() { # URL OUT
  local auth=()
  [ -n "${GH_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GH_TOKEN")
  curl -fsSL --retry 4 --retry-delay 3 "${auth[@]}" -H 'Accept: application/vnd.github+json' -o "$2" "$1"
}

# GitHub's report.
if [ -z "$GITHUB_FILE" ]; then
  gh_get "$GH_API/releases?per_page=100" "$work/releases.json"
  if [ -z "$GITHUB_TAG" ]; then
    GITHUB_TAG=$(jq -r --arg p "$GH_IMAGE/" '[.[] | select(.tag_name | startswith($p)) | select(.draft | not)]
      | sort_by(.published_at) | last | .tag_name // empty' "$work/releases.json")
  fi
  [ -n "$GITHUB_TAG" ] || { echo "no $GH_IMAGE release in actions/runner-images" >&2; exit 1; }
  url=$(jq -r --arg t "$GITHUB_TAG" --arg a "internal.$GH_IMAGE.json" \
    '.[] | select(.tag_name == $t) | .assets[] | select(.name == $a) | .browser_download_url' "$work/releases.json")
  [ -n "$url" ] || { echo "release $GITHUB_TAG has no internal.$GH_IMAGE.json" >&2; exit 1; }
  GITHUB_FILE=$work/github.json
  gh_get "$url" "$GITHUB_FILE"
fi
[ -n "$GITHUB_TAG" ] || GITHUB_TAG="$GH_IMAGE/$(jq -r '[.. | objects | select(.ToolName? == "Image Version:") | .Version] | first // "unknown"' "$GITHUB_FILE")"

# The Zode manifest and its version.
ZODE_VERSION=local
if [ -z "$MANIFEST_FILE" ]; then
  if [ -z "$CATALOGUE_FILE" ]; then
    CATALOGUE_FILE=$work/catalogue.json
    curl -fsS --retry 4 --max-time 30 -o "$CATALOGUE_FILE" "$API/v1/official-images"
  fi
  MANIFEST_FILE=$work/manifest.json
  jq -e --arg l "$LINE" '.images[] | select(.line == $l) | .manifest' "$CATALOGUE_FILE" >"$MANIFEST_FILE" ||
    { echo "the catalogue has no $LINE" >&2; exit 1; }
  ZODE_VERSION=$(jq -r --arg l "$LINE" '.images[] | select(.line == $l) | .version' "$CATALOGUE_FILE")
fi

# Policy: "note<TAB>area<TAB>name<TAB>why" and "alias<TAB>GitHub name<TAB>Zode name".
if [ -f "$POLICY" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$POLICY" | jq -Rn '
    [inputs | split("\t") | map(select(length > 0))] as $rows
    | {notes: [$rows[] | select(.[0] == "note" and length == 4) | {area: .[1], name: .[2], why: .[3]}],
       aliases: [$rows[] | select(.[0] == "alias" and length == 3) | {github: .[1], zode: .[2]}]}' >"$work/policy.json"
else
  echo '{"notes":[],"aliases":[]}' >"$work/policy.json"
fi

# One JSON document with both sides flattened to rows {area, section, name,
# version} and the comparison. Areas: tool, cached, env, apt. Names match
# when equal after lowercasing and dropping everything but letters and
# digits, or through an alias.
# shellcheck disable=SC2016 # jq program, not shell
jq -n --slurpfile gh "$GITHUB_FILE" --slurpfile z "$MANIFEST_FILE" --slurpfile pol "$work/policy.json" \
  --arg ghtag "$GITHUB_TAG" --arg zver "$ZODE_VERSION" --arg line "$LINE" '
  def key: ascii_downcase | gsub("[^a-z0-9+#]"; "");
  def kids: (.Children // []) | if type == "array" then . else [.] end;
  def num: (tostring | [scan("[0-9]+(?:\\.[0-9]+)+")] | first) // tostring;
  def majmin: num | split(".") | .[0:2] | join(".");

  # GitHub report -> rows. Java is a table of JDKs: one software row for
  # all of them (as in the Zode manifest) and one env row per JAVA_HOME_*.
  def ghrows(sec):
    if .NodeType == "HeaderNode" then
      (.Title) as $t
      | (if $t == "Installed Software" or ($t | startswith("Ubuntu")) then sec else $t end) as $s
      | kids[] | ghrows($s)
    elif .NodeType == "ToolVersionNode" then
      {area: (if sec == "Cached Tools" then "cached" else "tool" end), section: (sec // "Operating system"),
       name: (.ToolName | sub(":$"; "")), version: (.Version | tostring)}
    elif .NodeType == "ToolVersionsListNode" then
      {area: (if sec == "Cached Tools" then "cached" else "tool" end), section: sec,
       name: .ToolName, version: (.Versions | join(", ")), versions: .Versions}
    elif .NodeType == "TableNode" then
      (.Headers | split("|")) as $h
      | if sec == "Java" then
          {area: "tool", section: "Java", name: "Java", version: ([.Rows[] | split("|")[0]] | join(", "))},
          (.Rows[] | split("|") | {area: "env", section: "Java", name: .[1], version: "(a JDK path)"})
        else
          .Rows[] | split("|") as $r
          | if sec == "Installed apt packages" then {area: "apt", section: sec, name: $r[0], version: $r[1]}
            elif $h[0] == "Name" and $h[1] == "Value" then {area: "env", section: sec, name: $r[0], version: $r[1]}
            else {area: "tool", section: sec,
                  name: (if sec == "Android" and ($r[0] | startswith("Android") | not) then "Android " + $r[0] else $r[0] end),
                  version: ($r[1] | gsub("<br>"; ", "))} end
        end
    else empty end;

  ($gh[0] | [ghrows(null)]) as $grows

  # Zode manifest -> rows.
  | ($z[0]) as $m
  | ([$m.groups[]? | .name as $s | .items[] |
       {area: (if $s == "Cached tools" then "cached" elif $s == "Installed apt packages" then "apt" else "tool" end),
        section: $s, name: .name, version: .version}]
     + [($m.env // {}) | to_entries[] | {area: "env", section: "Environment", name: .key, version: .value}]) as $zrows

  | ($pol[0].aliases | map({key: (.github | key), value: (.zode | key)}) | from_entries) as $alias
  | ($pol[0].notes) as $notes
  | def zkey: . as $r | ($r.name | key) as $k | (if $r.area == "tool" then ($alias[$k] // $k) else $k end);
    def note($r): first($notes[] | select((.area == $r.area or .area == "*") and (.name | key) == ($r.name | key)) | .why) // "";
    ($zrows | map({key: (.area + ":" + (.name | key)), value: .}) | from_entries) as $zi
  | [$grows[] | . as $r | ($r.area + ":" + ($r | zkey)) as $k | ($zi[$k]) as $zr
      | $r + {zode: ($zr.version // null), zode_name: ($zr.name // null), why: note($r)}
      # Lists (tool cache, Java, Clang, ...) are the same when every GitHub
      # version is there: by major.minor in the tool cache, exactly elsewhere.
      | .missing_versions = (
          if .zode == null or .area == "env" or .area == "apt" then []
          elif .area == "cached" then
            ((.versions // (.version | split(", "))) | map(majmin)) - ((.zode | split(", ")) | map(majmin))
          elif (.version | test(", ")) then
            ((.versions // (.version | split(", "))) | map(num)) - ((.zode | split(", ")) | map(num))
          else [] end)
      | .status = (
          if .zode == null then "missing"
          elif .version == "(a JDK path)" then "same"
          elif .area == "env" then (if .version == .zode then "same" else "differs" end)
          elif .area == "apt" then "same"
          elif .area == "cached" or (.version | test(", ")) then
            (if (.missing_versions | length) == 0 then "same" else "differs" end)
          elif (.version | num) == (.zode | num) then "same"
          else "differs" end)
    ] as $cmp
  | ($grows | map(.area + ":" + (. | zkey))) as $gk
  | {line: $line, zode_version: $zver, github: $ghtag,
     rows: $cmp,
     only_zode: [$zrows[] | select((.area + ":" + (.name | key)) as $k | ($gk | index($k)) == null)]}
' >"$work/parity.json"

[ -z "$JSON_OUT" ] || cp "$work/parity.json" "$JSON_OUT"

# Markdown.
# shellcheck disable=SC2016 # jq program, not shell
jq -r '
  def esc: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
  def areaname: {tool: "Software", cached: "Tool cache", env: "Environment", apt: "apt package"}[.] // .;
  .rows as $r
  | ($r | map(select(.status == "missing"))) as $missing
  | ($r | map(select(.status == "differs"))) as $differs
  | ($r | map(select(.status == "same"))) as $same
  | "# " + .line + " compared with GitHub'"'"'s ubuntu-24.04\n",
    "Zode `" + .line + "` " + .zode_version + " against GitHub `" + .github + "`, from both images'"'"' own",
    "software reports. Written by `scripts/parity.sh` with every release; do not",
    "edit it by hand. Why something is left out: `images/" + .line + "/parity.tsv`.\n",
    "| | Count |", "| --- | --- |",
    "| Same | " + ($same | length | tostring) + " |",
    "| Different version | " + ($differs | length | tostring) + " |",
    "| Missing on Zode | " + ($missing | length | tostring) + " |",
    "| Only on Zode | " + (.only_zode | length | tostring) + " |",
    "",
    "## Missing on Zode\n",
    (if ($missing | map(select(.area != "apt")) | length) == 0 then "Nothing.\n" else
      "| Area | Section | Name | GitHub | Why |", "| --- | --- | --- | --- | --- |",
      ($missing | map(select(.area != "apt")) | sort_by(.area, .section, .name)[] |
        "| " + (.area | areaname) + " | " + (.section | esc) + " | " + (.name | esc) + " | " + (.version | esc)
        + " | " + (if .why == "" then "not added yet" else (.why | esc) end) + " |"), ""
    end),
    (($missing | map(select(.area == "apt"))) as $ma
     | if ($ma | length) == 0 then "Every apt package GitHub lists is installed.\n" else
       "apt packages GitHub lists that are not installed: "
       + ($ma | map("`" + .name + "`" + (if .why != "" then " (" + .why + ")" else "" end)) | join(", ")) + ".\n" end),
    "## Different versions\n",
    (if ($differs | length) == 0 then "None.\n" else
      "| Area | Name | GitHub | Zode |", "| --- | --- | --- | --- |",
      ($differs | sort_by(.area, .name)[] |
        "| " + (.area | areaname) + " | " + (.name | esc) + " | " + (.version | esc) + " | " + (.zode | esc)
        + (if (.missing_versions // [] | length) > 0 then " (missing " + (.missing_versions | join(", ")) + ")" else "" end) + " |"), ""
    end),
    "## Only on Zode\n",
    (if (.only_zode | length) == 0 then "Nothing.\n" else
      (.only_zode | map(select(.area != "apt")) | map(.name + " " + .version) | join(", ")) + ".\n" end),
    "<details><summary>Same on both (" + ($same | length | tostring) + ")</summary>\n",
    ($same | map(select(.area != "apt")) | sort_by(.area, .name) | map(.name) | join(", ")) + ".",
    (($same | map(select(.area == "apt"))) as $sa | if ($sa | length) > 0 then
      "\napt packages: " + ($sa | map(.name) | join(", ")) + "." else empty end),
    "\n</details>"
' "$work/parity.json"
