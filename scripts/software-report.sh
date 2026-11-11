#!/usr/bin/env bash
# Prints the software in this image as one line:
#   ZODE-MANIFEST {"os":"...","groups":[...],"env":{...}}
# The control plane stores that JSON on the release (docs/official-images.md
# in zodeops/zoded). A tool that is not installed is left out, never an error.
#
# Single source: scripts/render.sh copies this file into every Dockerfile,
# which installs it as /usr/local/bin/zode-software-report.
set -uo pipefail

TOOL_CACHE=${RUNNER_TOOL_CACHE:-${AGENT_TOOLSDIRECTORY:-/opt/hostedtoolcache}}
ROWS=$(mktemp)
trap 'rm -f "$ROWS"' EXIT

have() { command -v "$1" >/dev/null 2>&1; }

# run CMD...: the command's output, with a time limit when timeout exists.
run() {
  if have timeout; then timeout 20 "$@" 2>&1; else "$@" 2>&1; fi
}

# num: the first dotted version number in the input (1.2 or 1.2.3...).
num() { grep -oE '[0-9]+(\.[0-9]+)+' | head -n1; }

# add GROUP NAME VERSION: one row; an empty version is skipped.
add() {
  [ -n "${3:-}" ] || return 0
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$ROWS"
}

# tool GROUP NAME BINARY [ARGS...]: version of BINARY when it is on PATH.
tool() {
  local group=$1 name=$2 bin=$3
  shift 3
  have "$bin" || return 0
  add "$group" "$name" "$(run "$bin" "$@" | num)"
}

# service UNIT: ", running" or ", stopped" for a systemd unit.
service() {
  have systemctl || return 0
  if systemctl is-active --quiet "$1" 2>/dev/null; then
    printf ', running'
  else
    printf ', stopped'
  fi
}

# Operating system.
OS=unknown
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  OS=$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-$NAME}")
elif have sw_vers; then
  OS="macOS $(sw_vers -productVersion)"
fi
G="Operating system"
add "$G" "OS" "$OS"
add "$G" "Kernel" "$(uname -r)"
have systemctl && add "$G" "systemd" "$(run systemctl --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -n1)"

# Languages and runtimes.
G="Languages and runtimes"
tool "$G" "Bash" bash --version
have gcc && add "$G" "GCC" "$(run gcc -dumpfullversion | num)"
tool "$G" "Go" go version
java_list=""
for var in $(env | grep -oE '^JAVA_HOME_[0-9]+_X64' | sort -t_ -k3 -n); do
  dir=${!var}
  [ -x "$dir/bin/java" ] || continue
  v=$(grep -E '^JAVA_RUNTIME_VERSION=' "$dir/release" 2>/dev/null | cut -d'"' -f2)
  [ -n "$v" ] || v=$(run "$dir/bin/java" -version | num)
  v=${v%-LTS}
  [ "$(readlink -f "$dir")" = "$(readlink -f "${JAVA_HOME:-/nonexistent}")" ] && v="$v (default)"
  java_list="${java_list:+$java_list, }$v"
done
if [ -n "$java_list" ]; then
  add "$G" "Java" "$java_list"
else
  tool "$G" "Java" java -version
fi
tool "$G" "Node.js" node --version
tool "$G" "Perl" perl -e 'print $^V'
tool "$G" "Python" python3 --version
tool "$G" "Rust" rustc --version

# Package managers.
G="Package managers"
tool "$G" "npm" npm --version
tool "$G" "pnpm" pnpm --version
tool "$G" "Yarn" yarn --version
tool "$G" "Bun" bun --version
tool "$G" "pip" pip3 --version
tool "$G" "pipx" pipx --version
tool "$G" "Cargo" cargo --version

# Containers.
G="Containers"
if have docker; then
  add "$G" "Docker client" "$(run docker version --format '{{.Client.Version}}' | num)"
  add "$G" "Docker server" "$(run docker version --format '{{.Server.Version}}' | num)"
  add "$G" "Docker Buildx" "$(run docker buildx version | num)"
  add "$G" "Docker Compose" "$(run docker compose version --short | num)"
fi

# Cloud and deploy CLIs.
G="Cloud and deploy CLIs"
tool "$G" "AWS CLI" aws --version
tool "$G" "AWS Session Manager plugin" session-manager-plugin --version
tool "$G" "Google Cloud CLI" gcloud version --format='value(Google Cloud SDK)'
tool "$G" "kubectl" kubectl version --client
tool "$G" "Helm" helm version --short
tool "$G" "Kustomize" kustomize version

# Tools.
G="Tools"
tool "$G" "Git" git --version
tool "$G" "Git LFS" git-lfs --version
tool "$G" "GitHub CLI" gh --version
if [ -r /opt/zode-runner/.version ]; then
  add "$G" "GitHub Actions runner" "$(num </opt/zode-runner/.version)"
fi
tool "$G" "jq" jq --version
tool "$G" "yq" yq --version
tool "$G" "zstd" zstd --version
tool "$G" "CMake" cmake --version
tool "$G" "rsync" rsync --version
tool "$G" "OpenSSH" ssh -V
tool "$G" "curl" curl --version

# Databases. The version says whether the service runs in the image.
G="Databases"
have psql && add "$G" "PostgreSQL" "$(run psql --version | num)$(service postgresql)"
have redis-server && add "$G" "Redis" "$(run redis-server --version | num)$(service redis-server)"
tool "$G" "SQLite" sqlite3 --version

# Browsers.
G="Browsers"
tool "$G" "Google Chrome" google-chrome --version
for pkg in /usr/local/lib/node_modules/playwright/package.json /usr/lib/node_modules/playwright/package.json; do
  if [ -r "$pkg" ]; then
    add "$G" "Playwright" "$(jq -r .version "$pkg")"
    break
  fi
done

# Cached tools: what actions/setup-* find without a download.
G="Cached tools"
for entry in "node:Node.js" "Python:Python" "go:Go" "Java_Temurin-Hotspot_jdk:Java (Temurin)"; do
  dir="$TOOL_CACHE/${entry%%:*}"
  [ -d "$dir" ] || continue
  vs=$(for d in "$dir"/*/; do
    [ -e "${d%/}/x64.complete" ] && basename "$d"
  done | sort -V | paste -sd, - | sed 's/,/, /g')
  add "$G" "${entry#*:}" "$vs"
done

# Environment worth knowing, when set.
ENV_JSON=$(jq -n '$ENV | with_entries(select(.key | test(
  "^(ImageOS|ImageVersion|ZODE_IMAGE_VERSION|RUNNER_TOOL_CACHE|AGENT_TOOLSDIRECTORY|JAVA_HOME|JAVA_HOME_[0-9]+_X64|PLAYWRIGHT_BROWSERS_PATH|CHROME_PATH)$")))')

MANIFEST=$(jq -Rnc --arg os "$OS" --argjson env "$ENV_JSON" '
  [inputs | split("\t") | select(length == 3) | {g: .[0], n: .[1], v: .[2]}] as $rows
  | ($rows | reduce .[].g as $g ([]; if any(.[]; . == $g) then . else . + [$g] end)) as $order
  | {os: $os,
     groups: [$order[] as $g | {name: $g, items: [$rows[] | select(.g == $g) | {name: .n, version: .v}]}]}
  | if ($env | length) > 0 then .env = $env else . end' <"$ROWS")

printf 'ZODE-MANIFEST %s\n' "$MANIFEST"
