#!/usr/bin/env bash
# klaus — setup   (run with bash, e.g. ./setup.sh — not `sh setup.sh`)
#
#   ./setup.sh                       # interactive checkbox menu
#   ./setup.sh --with python,kmp     # non-interactive: pick modules directly
#   ./setup.sh --rebuild             # rebuild from the saved selection, no menu
#
# Builds the Docker image with the toolchain modules you select, and wires the
# `klaus` shell function into your shell rc. Minimal by default: only the
# modules you tick are baked in ('claude' is always included — it's the CLI).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="klaus"
MOD_DIR="$REPO_DIR/modules"

# --- discover modules -------------------------------------------------------
# Each modules/<name>.module has a '# DESC:' line. 'claude' is mandatory (the
# CLI itself) and hidden from the menu.
ALL_MODULES=()
for f in "$MOD_DIR"/*.module; do
    name="$(basename "$f" .module)"
    [ "$name" = "claude" ] && continue
    ALL_MODULES+=("$name")
done

module_desc() { grep -m1 '^# DESC:' "$MOD_DIR/$1.module" | sed 's/^# DESC:[[:space:]]*//'; }

# The chosen module list is remembered here so rebuilds (./setup.sh --rebuild,
# or `klaus ---install`) keep the same toolchains without asking again.
# KLAUS_DIR is the klaus base dir (distinct from KLAUS_CONFIG_DIR, claude's own).
KLAUS_DIR="${KLAUS_DIR:-$HOME/.klaus}"
MODULES_FILE="$KLAUS_DIR/modules"

# --- parse args -------------------------------------------------------------
PRESELECT=""        # comma-separated, non-interactive when set
REBUILD=0           # reuse the saved module selection, no menu
while [ $# -gt 0 ]; do
    case "$1" in
        --rebuild) REBUILD=1 ;;
        --with) PRESELECT="${2:-}"; [ -n "$PRESELECT" ] || { echo "--with needs a module list, e.g. --with python,kmp" >&2; exit 1; }; shift ;;
        --with=*) PRESELECT="${1#--with=}" ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# --rebuild reuses the saved selection (falls back to none if never saved).
if [ "$REBUILD" = "1" ] && [ -z "$PRESELECT" ]; then
    [ -f "$MODULES_FILE" ] && PRESELECT="$(tr '\n ' ',,' < "$MODULES_FILE" | sed 's/,,*/,/g;s/^,//;s/,$//')"
fi

# --- selection --------------------------------------------------------------
SELECTED=()

# Previously-saved modules, so the menu can pre-tick them.
SAVED_MODULES=" "
[ -f "$MODULES_FILE" ] && SAVED_MODULES=" $(tr '\n' ' ' < "$MODULES_FILE") "
_is_saved() { case "$SAVED_MODULES" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Simple numbered checkbox menu: type a number to toggle, Enter to confirm.
# Works on any shell, no raw-terminal handling. Selected names go to stdout;
# the menu is drawn to stderr so stdout stays clean for the caller.
select_menu() {
    local state=() i ans
    for i in "${!ALL_MODULES[@]}"; do
        state[$i]=0; _is_saved "${ALL_MODULES[$i]}" && state[$i]=1
    done
    while true; do
        echo "" >&2
        echo "Select toolchains (claude is always included):" >&2
        for i in "${!ALL_MODULES[@]}"; do
            local box="[ ]"; [ "${state[$i]}" = "1" ] && box="[x]"
            printf "  %d) %s %-8s %s\n" "$((i+1))" "$box" "${ALL_MODULES[$i]}" "$(module_desc "${ALL_MODULES[$i]}")" >&2
        done
        printf "Toggle a number, or Enter to confirm: " >&2
        read -r ans
        [ -z "$ans" ] && break
        if [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le "${#ALL_MODULES[@]}" ]; then
            i=$((ans-1))
            state[$i]=$([ "${state[$i]}" = "1" ] && echo 0 || echo 1)
        fi
    done
    for i in "${!ALL_MODULES[@]}"; do
        [ "${state[$i]}" = "1" ] && printf '%s ' "${ALL_MODULES[$i]}"
    done
}

if [ -n "$PRESELECT" ]; then
    IFS=',' read -ra SELECTED <<< "$PRESELECT"
elif [ "$REBUILD" = "1" ]; then
    SELECTED=()   # rebuild requested but nothing saved: just claude
elif [ -t 0 ] && [ -t 2 ]; then
    read -ra SELECTED <<< "$(select_menu)"
else
    echo "ERROR: no interactive terminal for the menu." >&2
    echo "       Pick modules non-interactively, e.g. ./setup.sh --with python,kmp" >&2
    exit 1
fi

# claude (the CLI) is always in.
MODULES="claude ${SELECTED[*]:-}"
echo "==> modules: $MODULES"

# Remember the selection (excluding the always-on 'claude') for later rebuilds.
mkdir -p "$(dirname "$MODULES_FILE")"
: > "$MODULES_FILE"
[ ${#SELECTED[@]} -gt 0 ] && printf '%s\n' "${SELECTED[@]}" | grep -v '^$' > "$MODULES_FILE"

# --- build ------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found on PATH. Install Docker first." >&2; exit 1
fi
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: docker daemon not reachable. Start Docker and re-run." >&2; exit 1
fi

# Persistent apt package list (~/.klaus/apt-packages, one package per line) is
# baked in on every build, on top of any KLAUS_APT given for this run. Managed
# with `klaus ---install` (see klaus.sh).
APT_LIST_FILE="$KLAUS_DIR/apt-packages"
APT_FROM_LIST=""
[ -f "$APT_LIST_FILE" ] && APT_FROM_LIST="$(grep -vE '^\s*(#|$)' "$APT_LIST_FILE" | tr '\n' ' ')"
APT_ALL="$APT_FROM_LIST ${KLAUS_APT:-}"

echo "==> building image '$IMAGE_NAME' ..."
[ -n "${APT_ALL// /}" ] && echo "    apt packages: $APT_ALL"
docker build \
    --build-arg KLAUS_MODULES="$MODULES" \
    --build-arg KLAUS_APT="$APT_ALL" \
    -f "$REPO_DIR/image/Dockerfile" \
    -t "$IMAGE_NAME" "$REPO_DIR"

# --- auth awareness ---------------------------------------------------------
# Just tell the user which auth klaus will use; don't store anything.
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    echo "==> found ANTHROPIC_API_KEY in your environment — klaus will use it."
elif [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    echo "==> found CLAUDE_CODE_OAUTH_TOKEN in your environment — klaus will use it."
elif [ -f "${KLAUS_CONFIG_DIR:-$KLAUS_DIR/.claude}/.credentials.json" ]; then
    echo "==> already logged in (${KLAUS_CONFIG_DIR:-$KLAUS_DIR/.claude}) — no login needed."
else
    echo "==> no login yet — the first 'klaus' will run /login."
fi

# --- wire up the shell function ---------------------------------------------
case "${SHELL:-}" in
    *zsh)  RC_FILE="$HOME/.zshrc" ;;
    *bash) RC_FILE="$HOME/.bashrc" ;;
    *)     RC_FILE="$HOME/.zshrc" ;;
esac
SOURCE_LINE="source \"$REPO_DIR/klaus.sh\""
MARKER="# >>> klaus >>>"
if grep -qF "$MARKER" "$RC_FILE" 2>/dev/null; then
    echo "==> shell function already wired in $RC_FILE (skipping)"
else
    echo "==> adding klaus to $RC_FILE"
    { echo ""; echo "$MARKER"; echo "$SOURCE_LINE"; echo "# <<< klaus <<<"; } >> "$RC_FILE"
fi

echo ""
echo "==> done. Run:  source $RC_FILE"
echo "    (or open a new shell), then 'klaus' in any project."
