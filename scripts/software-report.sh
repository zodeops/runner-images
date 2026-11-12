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
# rustup lives in CARGO_HOME (GitHub's layout); report the toolchain it runs.
if [ -n "${CARGO_HOME:-}" ] && [ -d "$CARGO_HOME/bin" ]; then PATH="$CARGO_HOME/bin:$PATH"; fi
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
if have dpkg-query && dpkg-query -W systemd >/dev/null 2>&1; then
  add "$G" "systemd" "$(dpkg-query -W -f='${Version}' systemd)"
else
  have systemctl && add "$G" "systemd" "$(run systemctl --version | head -n1 | grep -oE '[0-9]+(\.[0-9]+)*' | head -n1)"
fi

# Languages and runtimes.
G="Languages and runtimes"
tool "$G" "Bash" bash --version
have dpkg-query && add "$G" "Dash" "$(dpkg-query -W -f='${Version}' dash 2>/dev/null)"
have gcc && add "$G" "GCC" "$(run gcc -dumpfullversion | num)"
have gfortran && add "$G" "GNU Fortran" "$(run gfortran -dumpfullversion | num)"
tool "$G" "Clang" clang --version
tool "$G" "Clang-format" clang-format --version
tool "$G" "Clang-tidy" clang-tidy --version
tool "$G" "Go" go version
java_list=""
for var in $(env | grep -oE '^JAVA_HOME_[0-9]+_X64' | sort -t_ -k3 -n); do
  dir=${!var}
  [ -x "$dir/bin/java" ] || continue
  # SEMANTIC_VERSION says 8.0.512+9 where Java 8 itself says 1.8.0_512.
  v=$(grep -E '^SEMANTIC_VERSION=' "$dir/release" 2>/dev/null | cut -d'"' -f2)
  [ -n "$v" ] || v=$(grep -E '^JAVA_RUNTIME_VERSION=' "$dir/release" 2>/dev/null | cut -d'"' -f2)
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
tool "$G" "PowerShell" pwsh --version
tool "$G" "Python" python3 --version
tool "$G" "Ruby" ruby --version
tool "$G" "Rust" rustc --version
tool "$G" "Rustdoc" rustdoc --version
tool "$G" "Rustfmt" rustfmt --version

# Package managers.
G="Package managers"
tool "$G" "npm" npm --version
tool "$G" "pnpm" pnpm --version
tool "$G" "Yarn" yarn --version
tool "$G" "Bun" bun --version
tool "$G" "pip" pip3 --version
tool "$G" "pipx" pipx --version
tool "$G" "RubyGems" gem --version
tool "$G" "Cargo" cargo --version
tool "$G" "Rustup" rustup --version

# Build tools.
G="Build tools"
tool "$G" "CMake" cmake --version
tool "$G" "Ninja" ninja --version
tool "$G" "Maven" mvn -v
tool "$G" "Gradle" gradle --version
tool "$G" "Ant" ant -version
# Bazelisk prints its own version, then runs Bazel: hand it /bin/true as
# Bazel so it downloads nothing.
have bazelisk && add "$G" "Bazelisk" "$(HOME=${HOME:-/tmp} USE_BAZEL_VERSION=/bin/true run bazelisk version |
  grep -i '^bazelisk' | num)"

# Containers.
G="Containers"
if have docker; then
  add "$G" "Docker client" "$(run docker version --format '{{.Client.Version}}' | num)"
  add "$G" "Docker server" "$(run docker version --format '{{.Server.Version}}' | num)"
  add "$G" "Docker Buildx" "$(run docker buildx version | num)"
  add "$G" "Docker Compose" "$(run docker compose version --short | num)"
fi
tool "$G" "Podman" podman --version
tool "$G" "Buildah" buildah --version
tool "$G" "Skopeo" skopeo --version
tool "$G" "Kind" kind version

# Cloud and deploy CLIs.
G="Cloud and deploy CLIs"
tool "$G" "AWS CLI" aws --version
tool "$G" "AWS CLI Session Manager Plugin" session-manager-plugin --version
have az && add "$G" "Azure CLI" "$(run az version --query '"azure-cli"' --output tsv | num)"
tool "$G" "Google Cloud CLI" gcloud --version
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
tool "$G" "rsync" rsync --version
tool "$G" "OpenSSH" ssh -V
tool "$G" "OpenSSL" openssl version
tool "$G" "curl" curl --version
tool "$G" "Mercurial" hg --version
tool "$G" "MediaInfo" mediainfo --version
tool "$G" "ShellCheck" shellcheck --version
tool "$G" "yamllint" yamllint --version
tool "$G" "Ansible" ansible --version
have searchd && add "$G" "Sphinx Open Source Search Server" "$(dpkg-query -W -f='${Version}' sphinxsearch 2>/dev/null | num)"
have haveged && add "$G" "Haveged" "$(dpkg-query -W -f='${Version}' haveged 2>/dev/null | num)"

# Databases. The version says whether the service runs in the image.
G="Databases"
have psql && add "$G" "PostgreSQL" "$(run psql --version | num)$(service postgresql)"
have mysqld && add "$G" "MySQL" "$(run mysqld --version | num)$(service mysql)"
have redis-server && add "$G" "Redis" "$(run redis-server --version | num)$(service redis-server)"
tool "$G" "SQLite" sqlite3 --version

# Browsers and drivers.
G="Browsers"
tool "$G" "Google Chrome" google-chrome --version
tool "$G" "ChromeDriver" chromedriver --version
tool "$G" "Mozilla Firefox" firefox --version
tool "$G" "Geckodriver" geckodriver --version
if [ -n "${SELENIUM_JAR_PATH:-}" ] && [ -r "$SELENIUM_JAR_PATH" ]; then
  add "$G" "Selenium server" "$(basename "$(readlink -f "$SELENIUM_JAR_PATH")" | num)"
fi
for pkg in /usr/local/lib/node_modules/playwright/package.json /usr/lib/node_modules/playwright/package.json; do
  if [ -r "$pkg" ]; then
    add "$G" "Playwright" "$(jq -r .version "$pkg")"
    break
  fi
done

# Cached tools: what actions/setup-* find without a download.
G="Cached tools"
for entry in "node:Node.js" "Python:Python" "PyPy:PyPy" "go:Go" "Ruby:Ruby" "Java_Temurin-Hotspot_jdk:Java (Temurin)" "CodeQL:CodeQL"; do
  dir="$TOOL_CACHE/${entry%%:*}"
  [ -d "$dir" ] || continue
  vs=$(for d in "$dir"/*/; do
    [ -e "${d%/}/x64.complete" ] && basename "$d"
  done | sort -V | paste -sd, - | sed 's/,/, /g')
  add "$G" "${entry#*:}" "$vs"
done

# apt packages GitHub's ubuntu-24.04 lists (its toolset's apt section), when
# installed here.
G="Installed apt packages"
if have dpkg-query; then
  for p in acl aria2 autoconf automake binutils bison brotli bzip2 coreutils curl \
    dbus dnsutils dpkg dpkg-dev fakeroot file findutils flex fonts-noto-color-emoji \
    ftp g++ gcc gnupg2 haveged iproute2 iputils-ping jq libicu-dev libnss3-tools \
    libsqlite3-dev libssl-dev libtool libyaml-dev locales lz4 m4 make mediainfo \
    mercurial net-tools netcat openssh-client p7zip-full p7zip-rar parallel patchelf \
    pigz pkg-config pollinate python-is-python3 rpm rsync shellcheck sphinxsearch \
    sqlite3 ssh sshpass sudo swig systemd-coredump tar telnet texinfo time tk tree \
    tzdata unzip upx wget xvfb xz-utils zip zsync; do
    # Virtual packages (netcat) resolve to the package that provides them.
    v=$(dpkg-query -W -f='${db:Status-Abbrev}${Version}' "$p" 2>/dev/null | sed -n 's/^ii *//p')
    if [ -z "$v" ] && have apt-cache; then
      for q in $(apt-cache showpkg "$p" 2>/dev/null | awk '/^Reverse Provides:/{f=1; next} f && NF {print $1}'); do
        v=$(dpkg-query -W -f='${db:Status-Abbrev}${Version}' "$q" 2>/dev/null | sed -n 's/^ii *//p')
        [ -n "$v" ] && break
      done
    fi
    add "$G" "$p" "$v"
  done
fi

# Environment worth knowing, when set.
ENV_JSON=$(jq -n '$ENV | with_entries(select(.key | test(
  "^(ImageOS|ImageVersion|ZODE_IMAGE_VERSION|RUNNER_TOOL_CACHE|AGENT_TOOLSDIRECTORY|JAVA_HOME|JAVA_HOME_[0-9]+_X64|GOROOT_[0-9_]+_X64|PLAYWRIGHT_BROWSERS_PATH|CHROME_PATH|CHROMEWEBDRIVER|GECKOWEBDRIVER|EDGEWEBDRIVER|SELENIUM_JAR_PATH|CONDA|VCPKG_INSTALLATION_ROOT|ANDROID_[A-Z_]+|ACCEPT_EULA|XDG_CONFIG_HOME|CARGO_HOME|RUSTUP_HOME|PIPX_HOME|PIPX_BIN_DIR|ANT_HOME|GRADLE_HOME|M2_HOME|POWERSHELL_DISTRIBUTION_CHANNEL)$")))')

MANIFEST=$(jq -Rnc --arg os "$OS" --argjson env "$ENV_JSON" '
  [inputs | split("\t") | select(length == 3) | {g: .[0], n: .[1], v: .[2]}] as $rows
  | ($rows | reduce .[].g as $g ([]; if any(.[]; . == $g) then . else . + [$g] end)) as $order
  | {os: $os,
     groups: [$order[] as $g | {name: $g, items: [$rows[] | select(.g == $g) | {name: .n, version: .v}]}]}
  | if ($env | length) > 0 then .env = $env else . end' <"$ROWS")

printf 'ZODE-MANIFEST %s\n' "$MANIFEST"
