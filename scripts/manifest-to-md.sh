#!/usr/bin/env bash
# Turns software manifests into Markdown.
#
#   scripts/manifest-to-md.sh LINE [CATALOGUE.json]   README for one line
#   scripts/manifest-to-md.sh --summary [CATALOGUE.json]
#                                                     table of every line
#   scripts/manifest-to-md.sh --manifest [MANIFEST.json]
#                                                     tables for a bare manifest
#
# CATALOGUE.json is the body of GET https://api.zode.dev/v1/official-images.
# Input comes from stdin when no file is given.
set -euo pipefail

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

[ $# -ge 1 ] || usage
mode=$1
input=${2:--}

# The tables of one manifest: one table per group, then the environment.
# shellcheck disable=SC2016 # jq program, not shell
tables='
  def esc: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
  (.groups // [] | .[] |
    "### " + (.name | esc) + "\n\n| Name | Version |\n| --- | --- |",
    (.items[] | "| " + (.name | esc) + " | " + (.version | esc) + " |"),
    ""),
  (if (.env // {} | length) > 0 then
    "### Environment\n\n| Name | Value |\n| --- | --- |",
    (.env | to_entries[] | "| `" + (.key | esc) + "` | `" + (.value | esc) + "` |")
  else empty end)'

case "$mode" in
  --manifest)
    jq -r "$tables" "$input"
    ;;
  --summary)
    # shellcheck disable=SC2016 # jq program, not shell
    jq -r '
      def esc: tostring | gsub("\\|"; "\\|");
      if (.images // [] | length) == 0 then "No release is published yet."
      else
        "| Line | Use it with | Version | Published | Software |",
        "| --- | --- | --- | --- | --- |",
        (.images | sort_by(.line)[] |
          "| `" + (.line | esc) + "` | `" + (.ref // ("zode/" + .line) | esc) + "` | "
          + (.version | esc) + " | " + ((.published_at // "") | .[0:10]) + " | "
          + "[images/" + .line + "](images/" + .line + "/README.md) |")
      end' "$input"
    ;;
  -*)
    usage
    ;;
  *)
    line=$mode
    jq -e -r --arg line "$line" '
      (.images // [] | map(select(.line == $line)) | first) as $img
      | if $img == null then error("no published release of " + $line) else $img end
      | "# " + .line + "\n",
        "Use it with `" + (.ref // ("zode/" + .line)) + "`. Version " + .version
          + ", published " + ((.published_at // "") | .[0:10])
          + " from commit [" + ((.commit // "") | .[0:7]) + "](" + (.source_url // "") + ").",
        "Sizes: " + ((.sizes // []) | join(", ")) + ".\n",
        "Operating system: " + (.manifest.os // "unknown") + ".\n",
        "Written by the publish workflow from the software report in the image",
        "(`zode-software-report`). Do not edit it by hand.\n",
        "## Software\n",
        (.manifest // {} | '"$tables"')' "$input"
    ;;
esac
