# klaus — run Claude Code in a container, scoped to the current directory.
# Sourced from your shell rc (setup.sh adds the line). Anything outside $(pwd)
# is invisible to Claude — that's the point. See docs/how-it-works.md.
#
# Usage:
#   klaus [claude args...]        run Claude Code in this directory
#   klaus ---shell                 open a shell in the container instead of claude
#   klaus ---install <pkg>...      add apt package(s) to the image, then rebuild
#
# Optional env vars (all per-run):
#   KLAUS_HOSTS="host1 host2"                 extra firewall hosts to allow
#   KLAUS_MOUNT="/host/lib:/workspace/lib ..."  also mount paths outside the
#         project, docker-style host:container, space-separated for several

# Remember where this repo lives so `klaus install` can find setup.sh, whether
# sourced from bash or zsh.
if [ -n "${BASH_SOURCE:-}" ]; then
    KLAUS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${(%):-%x}" ] 2>/dev/null; then
    KLAUS_REPO="$(cd "$(dirname "${(%):-%x}")" && pwd)"
fi

klaus() {
    # klaus ---install <pkg>...  — add apt package(s) to the image and rebuild.
    # Does NOT start a container.
    if [ "${1:-}" = "---install" ]; then
        shift
        _klaus_install "$@"
        return $?
    fi

    # klaus ---shell — open a shell in the container instead of launching claude.
    local shell_env=()
    if [ "${1:-}" = "---shell" ]; then
        shift
        shell_env=(-e "KLAUS_SHELL=1")
    fi

    # klaus keeps its OWN claude config on the host under ~/.klaus, separate from
    # your host ~/.claude — the container never touches your Mac's claude login.
    # It mirrors the container layout: a .claude dir + a .claude.json file.
    # KLAUS_DIR is the base; KLAUS_CONFIG_DIR overrides just the .claude dir.
    local base="${KLAUS_DIR:-$HOME/.klaus}"
    local config="${KLAUS_CONFIG_DIR:-$base/.claude}"
    local config_json="$base/.claude.json"
    mkdir -p "$config"
    # Claude's onboarding/top-level state lives in the separate file
    # ~/.claude.json — persist it too, or the container re-onboards every start.
    # Pre-create it so Docker bind-mounts it as a file, not a directory.
    [ -e "$config_json" ] || echo '{}' > "$config_json"

    # Extra mounts for paths outside the project (monorepos / shared libs):
    # each entry is docker-style host:container, space-separated for several.
    local extra_mount=() m
    for m in ${KLAUS_MOUNT:-}; do
        extra_mount+=(-v "$m")
    done

    # Pass an API key / token through only if the host has one set, for headless
    # use. Otherwise you log in interactively on first run (persisted in $config).
    local auth=()
    [ -n "${ANTHROPIC_API_KEY:-}" ]      && auth+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
    [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && auth+=(-e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN")

    # Start banner: which host paths are mapped in, and which toolchains are
    # baked into the image. (The firewall lists allowed hosts from inside.)
    echo "klaus — mapped paths:"
    echo "  • $(pwd) → /workspace"
    for m in ${KLAUS_MOUNT:-}; do echo "  • ${m%%:*} → ${m#*:}"; done
    echo "  • $config → ~/.claude   (config, persisted)"
    local mods="claude"
    [ -f "$base/modules" ] && mods="claude $(tr '\n' ' ' < "$base/modules")"
    echo "modules: $mods"

    # Network is firewalled inside the container (see firewall.sh); allow extra
    # hosts ad-hoc with KLAUS_HOSTS="host1 host2" klaus.
    # Dependency caches persist across runs in named volumes, so packages
    # downloaded once (pip wheels, Gradle/Maven artifacts, npm) survive the
    # container being thrown away. The container itself stays disposable.
    docker run -it --rm \
        --cap-add=NET_ADMIN \
        -e "KLAUS_HOSTS=${KLAUS_HOSTS:-}" \
        "${shell_env[@]}" \
        "${auth[@]}" \
        -v "$(pwd):/workspace" -w /workspace \
        "${extra_mount[@]}" \
        -v "$config:/home/klaus/.claude" \
        -v "$config_json:/home/klaus/.claude.json" \
        -v klaus-data:/home/klaus/.local/share/claude \
        -v klaus-cache:/home/klaus/.cache \
        -v klaus-gradle:/home/klaus/.gradle \
        -v klaus-m2:/home/klaus/.m2 \
        klaus "$@"
}

# Add apt package(s) to the persistent list and rebuild. The rebuild is the
# test: if it fails (bad package name, virtual package, …), the list is rolled
# back so one typo can't poison every future build. The list
# (~/.klaus/apt-packages) is the source of truth — edit it by hand to remove.
_klaus_install() {
    if [ $# -eq 0 ]; then
        echo "usage: klaus ---install <apt-package>..." >&2
        return 1
    fi
    local dir="${KLAUS_DIR:-$HOME/.klaus}"
    local list="$dir/apt-packages"
    mkdir -p "$dir"
    touch "$list"

    # Back up the current list so we can restore it if the build fails.
    local backup; backup="$(cat "$list")"

    local pkg added=0
    for pkg in "$@"; do
        if grep -qxF "$pkg" "$list"; then
            echo "already listed: $pkg"
        else
            echo "$pkg" >> "$list"; echo "added: $pkg"; added=1
        fi
    done
    [ "$added" = "0" ] && { echo "nothing new to install."; return 0; }

    echo "==> rebuilding image with the updated apt list ..."
    # Pass KLAUS_DIR through explicitly so the subprocess reads the same list.
    if KLAUS_DIR="$dir" "$KLAUS_REPO/setup.sh" --rebuild; then
        return 0
    else
        printf '%s\n' "$backup" > "$list"
        echo "" >&2
        echo "build failed — reverted apt list (removed: $*)." >&2
        echo "check the package name (e.g. 'ping' is provided by 'iputils-ping')." >&2
        return 1
    fi
}
