# Changelog

Changes to the lines, newest first. Each release's full software list is in
`images/<line>/README.md`, written by the publish workflow.

## Unreleased

- `ci-ubuntu-24.04`: parity with GitHub's `ubuntu-24.04` for common actions
  and workflows. Tool cache: Python 3.11, 3.14 and 3.15, Go 1.24.13, 1.25.14
  and 1.26.11 (1.24 is `go` on PATH, `GOROOT_*_X64` set), Temurin 8, 11 and 25
  (`JAVA_HOME_*_X64`). Maven 3.10.0, Gradle 9.9.1, Ant, PowerShell 7.6.10,
  Azure CLI 2.92.0, Google Cloud CLI 593.0.0, Firefox 160.0, ChromeDriver
  (matching Chrome), geckodriver 0.37.1, Selenium server 4.52.0, kind 0.33.0,
  Bazelisk 1.28.1 (`bazel`), AWS Session Manager plugin, yamllint, Ansible,
  rustup with stable, Clang, gfortran, Ruby, Podman, Buildah, Skopeo, MySQL
  (stopped, root/root) and GitHub's apt package list. A `runner` user (uid
  1001, group docker, passwordless sudo) that zode-api runs jobs as, with
  work folder `/home/runner/work`; GitHub's PATH order and kernel settings
  (`vm.max_map_count`, inotify). Install hook for `zode-ci` (off).
- Software report: many more tools, an apt package group and more
  environment variables, so it can be compared with GitHub's.
- `scripts/parity.sh`: the difference list against GitHub's image, written to
  `images/ci-ubuntu-24.04/PARITY.md` and the GitHub release of every version.

- `ci-ubuntu-24.04`: first version. AWS CLI 2.40.1, kubectl 1.37.2,
  Helm 3.22.1, Kustomize 5.8.3, yq 4.54.3, Temurin 17.0.21+9 (default) and
  21.0.13+9, tool cache with Node.js 22.23.4 and 24.22.2 and Python 3.12.16
  and 3.13.18, `ImageOS=ubuntu24`. PostgreSQL and Redis stopped and disabled.
- `base`: first version. zstd, Git LFS, yq 4.54.3.
