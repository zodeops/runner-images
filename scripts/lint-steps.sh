#!/usr/bin/env bash
# Checks every RUN <<'ZODE_STEP' body in images/*/Dockerfile with shellcheck
# as bash, the shell Zode runs them with. ARG and ENV values reach the
# steps as environment variables, so SC2154 (unassigned) is off.
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
status=0
for df in images/*/Dockerfile; do
  line=$(basename "$(dirname "$df")")
  awk -v q="'" -v m=ZODE_STEP -v dir="$work" -v name="$line" '
    inbody { if ($0 == m) { inbody = 0; close(f) } else print > f; next }
    /^RUN / && index($0, "<<" q m q) { inbody = 1; f = dir "/" name "-line" NR ".sh"; print "#!/usr/bin/env bash" > f }
  ' "$df"
done
for f in "$work"/*.sh; do
  [ -e "$f" ] || continue
  if ! shellcheck -s bash -e SC2154 "$f"; then
    echo "^ in $(basename "$f" .sh)" >&2
    status=1
  fi
done
exit "$status"
