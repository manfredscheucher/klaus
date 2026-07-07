# Modules

Opt-in toolchains baked into the image at setup time. Nothing here is installed
unless selected. `claude` is mandatory (it's the CLI) and always included.

| Module   | Installs                       | Notes |
|----------|--------------------------------|-------|
| `claude` | Claude Code CLI + Node runtime | always included; not in the menu |
| `python` | python3 + venv + pip           | apt only |
| `kmp`    | JDK + Gradle                   | opens Gradle/Maven/Google in the firewall; `KLAUS_ANDROID=1` adds the Android SDK |

A toolchain only needs a module here if it requires firewall hosts or
non-trivial install steps. Pure-apt tooling (e.g. a C++ toolchain) goes through
the extra-apt field instead:

```bash
KLAUS_APT="build-essential cmake ninja-build gdb" ./setup.sh
```

## Format

Each `<name>.module` is a shell fragment:

```sh
# DESC: one-line label shown in the setup menu
# HOSTS: space-separated hostnames to allow in the firewall (empty if apt-only)
install_module() { apt-get install -y --no-install-recommends <packages>; }
```
