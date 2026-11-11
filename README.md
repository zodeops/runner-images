# Zode runner images

The source of Zode's official images: the images every Zode sandbox and
every GitHub Actions job on Zode can boot. It plays the part
[actions/runner-images](https://github.com/actions/runner-images) plays for
GitHub-hosted runners.

Each line is one Dockerfile under `images/`. Zode builds it on every node
and in every size, and publishes all of them at once.

## Lines

| Line | Used by | What it adds to the Zode base image |
| --- | --- | --- |
| [`ci-ubuntu-24.04`](images/ci-ubuntu-24.04) | every CI job (`runs-on: zode-*`) | AWS CLI, kubectl, Helm, Kustomize, yq, Temurin JDK 17 and 21, the hosted tool cache (Node.js 22 and 24, Python 3.12 and 3.13), `ImageOS`; PostgreSQL and Redis installed but stopped, as on GitHub's runners |
| [`base`](images/base) | sandboxes that ask for `zode/base` | zstd, Git LFS, yq; PostgreSQL and Redis keep running |

The Zode base image itself is Ubuntu 24.04 with Docker (Buildx, Compose),
Node.js, pnpm, Yarn, Bun, Python, Go, Rust, the GitHub CLI, Chrome,
Playwright, PostgreSQL, Redis and the coding agents.

## Use them

CI jobs get `ci-ubuntu-24.04` with nothing to change:

```yaml
jobs:
  test:
    runs-on: zode-4x8
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-node@v6
        with:
          node-version: 24 # found in the tool cache, no download
```

A sandbox asks for a line by name and keeps its own size:

```sh
zode new --image zode/base
```

In the API: `"image": "zode/<line>"` on `POST /v1/sandboxes`.

## Software

The lists below come from each image's own report
(`zode-software-report`, the last build step). The publish workflow writes
them after every release.

<!-- software:start -->
| Line | Use it with | Version | Published | Software |
| --- | --- | --- | --- | --- |
| `base` | `zode/base` | 20261111.2 | 2026-11-11 | [images/base](images/base/README.md) |
<!-- software:end -->

## How a release works

1. A push to `main` that changes `images/<line>/Dockerfile` starts the
   [publish workflow](.github/workflows/publish.yml) for that line. A change
   to `scripts/software-report.sh` releases every line. A maintainer can
   also run it by hand for one line or all of them.
2. The workflow sends the Dockerfile to `POST /v1/official/releases`,
   signed with its GitHub OIDC token. Only this repository's `main` branch
   is accepted. The version is `YYYYMMDD.<run number>`.
3. Zode builds the image once per node and per size, one official build per
   node at a time so customer sandboxes keep their room.
4. When every build is ready, the release is published everywhere at once.
   New sandboxes and CI jobs use it from then on. The previous release is
   retired and its images are deleted after 24 hours; sandboxes already
   running from it keep running.
5. If any build fails, the release fails, the other builds are cancelled and
   the published release stays as it was. The workflow prints each failed
   build's log.
6. The workflow then writes `images/<line>/README.md` and the table above
   from the public catalogue (`GET https://api.zode.dev/v1/official-images`).

## How a Dockerfile is read

Lines build `FROM zode`, so each step runs in a Zode VM, not in a container:

- every `RUN` runs with `bash -lc` as root;
- `ENV` is kept for every login shell (`/etc/profile.d`) and in
  `/etc/environment`; `ARG` is for the build only;
- `COPY` and `ADD` are refused, so files are written inline with a heredoc;
- a Dockerfile is at most 64 KB and 200 instructions, a step at most 16 KB,
  and a build at most 60 minutes.

## Contributing

- Edit `images/<line>/Dockerfile.in`, never the `Dockerfile` next to it.
  Run `scripts/render.sh` and commit both. The render copies
  `scripts/software-report.sh` into every Dockerfile, because the image cannot
  copy it in.
- Pin every version in an `ARG` at the top of the file, with its sha256
  when the project publishes one.
- Keep the last step `RUN /usr/local/bin/zode-software-report`. It prints
  the one `ZODE-MANIFEST {...}` line Zode stores with the release.
- Pull requests run [check](.github/workflows/check.yml): shellcheck,
  the render check, hadolint, actionlint and a smoke test of the report.
- Keep the images lean. Large toolchains (Android, .NET, Haskell, Swift)
  belong in a workspace's own custom image, not here.

To add a line, create `images/<name>/Dockerfile.in`, render it, and merge.
The name must match `^[a-z0-9][a-z0-9.-]{0,40}$`.

## License

[MIT](LICENSE). The software installed in the images keeps its own licenses.
