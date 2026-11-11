# ci-ubuntu-24.04

Use it with `zode/ci-ubuntu-24.04`. Version 20261111.2, published 2026-11-11 from commit [571eb07](https://github.com/zodeops/runner-images/tree/571eb0752d402e84cfaba23babd6ed736206f4ce/images/ci-ubuntu-24.04).
Sizes: 2x4, 4x8, 8x16, 16x32.

Operating system: Ubuntu 24.04.5 LTS.

Written by the publish workflow from the software report in the image
(`zode-software-report`). Do not edit it by hand.

## Software

### Operating system

| Name | Version |
| --- | --- |
| OS | Ubuntu 24.04.5 LTS |
| Kernel | 6.8.0-147-generic |
| systemd | 255 |

### Languages and runtimes

| Name | Version |
| --- | --- |
| Bash | 5.2.21 |
| GCC | 13.3.0 |
| Go | 1.27.3 |
| Java | 17.0.21+9 (default), 21.0.13+9 |
| Node.js | 22.23.4 |
| Perl | 5.38.2 |
| Python | 3.12.3 |
| Rust | 1.99.1 |

### Package managers

| Name | Version |
| --- | --- |
| npm | 10.9.9 |
| pnpm | 12.18.0 |
| Yarn | 1.22.22 |
| Bun | 1.4.4 |
| pip | 24.0 |
| pipx | 1.4.3 |
| Cargo | 1.99.1 |

### Containers

| Name | Version |
| --- | --- |
| Docker client | 29.1.3 |
| Docker server | 29.1.3 |
| Docker Buildx | 0.30.1 |
| Docker Compose | 2.40.3 |

### Cloud and deploy CLIs

| Name | Version |
| --- | --- |
| AWS CLI | 2.40.1 |
| kubectl | 1.37.2 |
| Helm | 3.22.1 |
| Kustomize | 5.8.3 |

### Tools

| Name | Version |
| --- | --- |
| Git | 2.43.0 |
| Git LFS | 3.4.1 |
| GitHub CLI | 2.103.3 |
| GitHub Actions runner | 2.338.2 |
| jq | 1.7 |
| yq | 4.54.3 |
| zstd | 1.5.5 |
| CMake | 3.28.3 |
| rsync | 3.2.7 |
| OpenSSH | 9.6 |
| curl | 8.5.0 |

### Databases

| Name | Version |
| --- | --- |
| PostgreSQL | 16.15, stopped |
| Redis | 7.0.15, stopped |
| SQLite | 3.45.1 |

### Browsers

| Name | Version |
| --- | --- |
| Google Chrome | 157.0.8103.38 |
| Playwright | 1.65.0 |

### Cached tools

| Name | Version |
| --- | --- |
| Node.js | 22.23.4, 24.22.2 |
| Python | 3.12.16, 3.13.18 |
| Java (Temurin) | 17.0.21-9, 21.0.13-9 |

### Environment

| Name | Value |
| --- | --- |
| `ImageOS` | `ubuntu24` |
| `JAVA_HOME` | `/usr/lib/jvm/temurin-17-jdk-amd64` |
| `CHROME_PATH` | `/usr/bin/google-chrome` |
| `ImageVersion` | `20261111.2` |
| `JAVA_HOME_17_X64` | `/usr/lib/jvm/temurin-17-jdk-amd64` |
| `JAVA_HOME_21_X64` | `/usr/lib/jvm/temurin-21-jdk-amd64` |
| `RUNNER_TOOL_CACHE` | `/opt/hostedtoolcache` |
| `AGENT_TOOLSDIRECTORY` | `/opt/hostedtoolcache` |
| `PLAYWRIGHT_BROWSERS_PATH` | `/ms-playwright` |
