# How klaus works

## Overview

klaus runs Claude Code inside a Docker container scoped to a single directory.
Two things are isolated:

- **Disk** — Claude sees only the directory you launch from.
- **Network** — the container can only reach the Anthropic API (plus hosts a
  selected module explicitly needs).

The container is created fresh on each run and destroyed on exit; only your
auth/config and session history persist.

## Filesystem isolation

`klaus` mounts **only** the current directory (`$(pwd)`) into the container at
`/workspace`. Everything above it — your home directory, SSH keys, sibling
folders, the rest of the filesystem — is physically absent from the container,
not merely permission-blocked.

Inside the mounted folder Claude has full read/write access, including `.env`
files. The isolation protects everything *outside* the mount, not the mounted
folder itself — so don't launch klaus from your home directory or `/`.

### Paths outside the project

If a project depends on a folder outside the current directory (a monorepo, a
shared library one level up), mount it explicitly. Each entry is docker-style
`host:container`; separate several with spaces:

```bash
KLAUS_MOUNT=/host/shared-lib:/workspace/lib klaus

# several at once:
KLAUS_MOUNT="/host/lib:/workspace/lib /host/proto:/workspace/proto" klaus
```

## Network isolation

On start the container firewalls its own network: default policy `DROP`, DNS
allowed so hostnames resolve, and outbound HTTPS permitted only to an
allow-list. By default that list is just `api.anthropic.com`. npm, GitHub and
everything else are blocked.

Consequently `pip install`, `git clone` and `git push` over the network fail
by default — intentionally. There are three ways a host ends up allowed:

1. **`api.anthropic.com`** — always (Claude needs it).
2. **Module hosts** — a selected module can declare hosts it needs; `kmp`, for
   example, opens the Gradle/Maven/Google repositories.
3. **Ad-hoc, per run** — `KLAUS_HOSTS="pypi.org files.pythonhosted.org" klaus`.

The rules live in `image/firewall.sh`. Note that allowing a broad host like
`github.com` also permits pushing data *to* repos there, so keep the list as
tight as the task allows.

There's one more way data crosses the boundary: anything you *write into* the
mounted directory becomes readable by Claude. That's deliberate and useful (see
[advanced usage](advanced-usage.md) for bridging host logs in), but it means a
host logfile piped into the mount can carry tokens or env vars into the sandbox
— bridge deliberately, not blindly.

## Lifecycle

`klaus` runs `docker run --rm`, so when Claude exits the container stops and is
deleted. Every process Claude started inside it — a dev server, a test runner —
dies with the container. Nothing leaks onto your host.

To check for a stray container (e.g. if a terminal was killed without a clean
exit): `docker ps`, then `docker rm -f <name>`.

### What persists

- **Auth/config** — host `~/.klaus/.claude` (dir) + `~/.klaus/.claude.json`
  (onboarding/top-level state). Separate from your host `~/.claude`; override
  the dir with `KLAUS_CONFIG_DIR`. (On native Linux, if the container user's uid
  doesn't match the host file owner, Claude may fail to write these — fine on
  Docker Desktop for Mac/Windows, which maps ownership transparently.)
- **Sessions/history** — the named Docker volume `klaus-data`.
- **Dependency caches** — named volumes `klaus-cache` (`~/.cache`, incl. pip),
  `klaus-gradle` (`~/.gradle`) and `klaus-m2` (`~/.m2`). So a package downloaded
  once isn't re-fetched on the next run, even though the container is thrown
  away.
- **Image config** — plain files `~/.klaus/modules` (selected toolchains) and
  `~/.klaus/apt-packages` (extra apt packages). These define what's baked into
  the image; a rebuild reads them, so the image is reproducible.

All are shared across projects; the container's own filesystem is ephemeral.

This is the key point about *runtime* installs: anything installed into the
cached locations above, or into the mounted project directory (a `./.venv`,
`node_modules/`), **survives** across runs. Only installs into other parts of
the container's filesystem are lost.

**System (apt) packages** are the exception — they belong in the image, not the
running container. Add them with `klaus ---install <pkg>...`, which appends to
`~/.klaus/apt-packages` and rebuilds. `setup.sh --rebuild` rebuilds from the
saved module + apt lists without re-asking.

## Running several at once

Each `klaus` call starts its own container, so multiple projects run in
parallel without seeing each other's files, and each has its own network
namespace and firewall. They share only the persisted config and history.

## Environment variables

Set at **setup** time (`./setup.sh`), baked into the image:

| Variable        | Effect                                                       |
|-----------------|--------------------------------------------------------------|
| `KLAUS_APT`     | Extra apt packages to install (e.g. `"build-essential cmake"`) |

Set at **run** time (`klaus`), per invocation:

| Variable            | Effect                                                    |
|---------------------|-----------------------------------------------------------|
| `KLAUS_MOUNT`       | Extra mounts, docker-style `host:container`, space-separated |
| `KLAUS_HOSTS`       | Extra firewall hosts to allow, space-separated            |
| `KLAUS_DIR`         | klaus's base dir — holds `modules`, `apt-packages`, config (default `~/.klaus`) |
| `KLAUS_CONFIG_DIR`  | Just claude's own config/credentials dir (default `$KLAUS_DIR/.claude`) |

Most arguments to `klaus` pass straight through to `claude`
(`klaus --resume`, `klaus --dangerously-skip-permissions`, …). The exceptions
are klaus's own subcommands: `klaus ---shell` (a shell in the container instead
of claude) and `klaus ---install <pkg>...` (add apt packages + rebuild, no
container).

## Repository layout

You only ever run `setup.sh` (once) and `klaus` (sourced from `klaus.sh`).
Everything under `image/` is image internals, invoked during the build or
inside the container — never by you directly.

| Path                            | Purpose                                          |
|---------------------------------|--------------------------------------------------|
| `setup.sh`                      | Module menu, builds the image, wires the shell fn |
| `uninstall.sh`                  | Removes the image, volume, config, and shell block |
| `klaus.sh`                      | The `klaus` shell function                        |
| `modules/`                      | Opt-in toolchains                                 |
| `docs/`                         | This file + [advanced usage](advanced-usage.md)   |
| `image/Dockerfile`              | Ubuntu base; installs the selected modules        |
| `image/build-install-modules.sh`| Build-time module installer + firewall host list  |
| `image/entrypoint.sh`           | Sets up the firewall, then drops to an unprivileged user |
| `image/firewall.sh`             | Locks the network to Anthropic + module hosts     |
