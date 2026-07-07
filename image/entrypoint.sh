#!/usr/bin/env bash
# entrypoint.sh — runs as root: set up the firewall, then drop to the `klaus`
# user and hand off to Claude Code.

set -euo pipefail

/usr/local/bin/firewall.sh

# Drop privileges and run as the unprivileged user. KLAUS_SHELL=1 opens an
# interactive shell instead of launching claude (for poking around the container).
if [ "${KLAUS_SHELL:-}" = "1" ]; then
    exec gosu klaus bash
fi
exec gosu klaus claude "$@"
