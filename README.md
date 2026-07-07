# klaus

klaus is a wrapper that runs [Claude Code](https://claude.com/claude-code)
inside a Docker container scoped to a single directory. Claude sees nothing else
on your disk, and the container can only reach the Anthropic API. You can grant
exceptions per run — extra hosts (`KLAUS_HOSTS`) or extra mounted paths
(`KLAUS_MOUNT`). See [`docs/how-it-works.md`](docs/how-it-works.md) for details.

## Requirements

Docker, installed and running (Docker Desktop on macOS/Windows, Docker Engine
on Linux). On macOS, also `coreutils` for `timeout` (`brew install coreutils`) and`newt` for a nicer setup menu (`brew install newt`).

## Install

```bash
git clone https://github.com/manfredscheucher/klaus.git
cd klaus
./setup.sh
```

`setup.sh` lets you pick toolchains, builds the image, and wires up your shell.
It also offers to guard the bare `claude` command — so typing `claude` asks
whether you want sandboxed klaus or the original, avoiding an un-sandboxed run
out of habit (`command claude` always bypasses it). Open a new shell afterwards
(or `source ~/.zshrc` / `~/.bashrc`).

## First run

Authentication works one of two ways:

- **If a key is in your host environment** (`ANTHROPIC_API_KEY` or
  `CLAUDE_CODE_OAUTH_TOKEN`), klaus passes it through automatically — no login
  needed. `setup.sh` tells you if it finds one.
- **Otherwise**, the first `klaus` runs Claude Code's `/login` — a login of its
  own, separate from any Claude Code on your host.

Either way, klaus's config lives in `~/.klaus` on the host and is shared across
all klaus instances: the login, config, skills and the like persist there.

## Use

```bash
cd ~/any/project
klaus                                   # Claude Code, scoped to this directory
klaus --resume                          # any claude flag/arg passes through
klaus ---shell                           # a shell in the container, not claude
klaus ---install cmake                   # add apt package(s) to the image, rebuild
KLAUS_MOUNT=/host/lib:/workspace/lib klaus   # mount a path outside the project
```

Session history persists across runs too.

Need something the container can't do (an emulator, a GUI, hardware), or want to
run test suites fully sandboxed? See [advanced usage](docs/advanced-usage.md).

## Network is blocked by default

The container can only reach the Anthropic API. `pip install`, `git clone`,
`git push` and the like fail unless you allow the hosts they need, for one run:

```bash
KLAUS_HOSTS="pypi.org files.pythonhosted.org" klaus   # e.g. for pip
KLAUS_HOSTS="github.com" klaus                        # e.g. for git
```

## Toolchains

The image is minimal by default. Languages and build tools are opt-in modules
you tick during setup:

- **python** — Python 3 + pip/venv
- **kmp** — Kotlin Multiplatform / Gradle (JDK + Gradle)

For extra system (apt) packages, add them to the image and rebuild:

```bash
klaus ---install build-essential cmake   # appends to the list, then rebuilds
```

This triggers an image rebuild, so it takes longer than a plain `apt install`
(incremental, but not instant). The packages are remembered in
`~/.klaus/apt-packages`. To **remove** one, delete its line from that file and
run `./setup.sh --rebuild`. See [`modules/`](modules/).

Only **system** packages (`apt`) need this. Project dependencies you install at
runtime persist on their own: `pip`, Gradle and Maven caches live in named
volumes, and installs into the project (a `./.venv`, `node_modules/`) sit in the
mount — so they aren't re-downloaded each run.

## Safety

The isolation protects everything *outside* the launch directory. *Inside* it,
Claude has full read/write access — including `.env` and secrets. So launch
klaus from a project directory, never from your home directory or `/`.

## Uninstall

```bash
./uninstall.sh
```

Removes the shell block, the image, and (after asking) the session history and
login. Open a new shell afterwards.

---

More detail — repo layout, all env vars, internals:
[`docs/how-it-works.md`](docs/how-it-works.md).
